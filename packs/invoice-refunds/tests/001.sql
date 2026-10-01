begin;
do $$
declare a uuid; b uuid; s uuid; c uuid; inv uuid; inv2 uuid; r1 uuid; r2 uuid; r3 uuid;
begin
  a := t.make_user('owner@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  insert into public.ir_customers (subject_id, name) values (s, 'Acme') returning id into c;
  insert into public.ir_invoices (subject_id, customer_id, number) values (s, c, 'INV-1') returning id into inv;

  -- Formula + Sum: line amount and invoice total are derived, never client-set
  insert into public.ir_invoice_lines (invoice_id, subject_id, description, quantity, unit_price) values (inv, s, 'Design', 2, 40.00), (inv, s, 'Hosting', 1, 20.00);
  perform t.assert(t.rows('select 1 from public.ir_invoices where id = ''' || inv || ''' and total = 100.00') = 1, 'invoice total = sum of line amounts');
  perform t.assert(t.denied('insert into public.ir_invoice_lines (invoice_id, subject_id, description, quantity, unit_price, amount) values (''' || inv || ''', ''' || s || ''', ''x'', 1, 1, 999)'), 'clients cannot set line amount');
  perform t.assert(t.denied('update public.ir_invoices set total = 1 where id = ''' || inv || ''''), 'clients cannot set invoice total');
  perform t.assert(t.denied('update public.ir_customers set balance = 1 where id = ''' || c || ''''), 'clients cannot set customer balance');
  update public.ir_invoice_lines set unit_price = 45.00 where description = 'Design';
  perform t.assert(t.rows('select 1 from public.ir_invoices where id = ''' || inv || ''' and total = 110.00') = 1, 'editing a line updates the total');
  update public.ir_invoice_lines set unit_price = 40.00 where description = 'Design';

  -- a refund needs a paid invoice
  perform t.assert(t.denied('insert into public.ir_refunds (invoice_id, subject_id, amount) values (''' || inv || ''', ''' || s || ''', 10)'), 'no refund on a draft invoice');
  perform t.assert(t.denied('update public.ir_invoices set status = ''paid'' where id = ''' || inv || ''''), 'draft cannot jump to paid');
  perform t.assert(t.rows('select 1 from public.ir_customers where id = ''' || c || ''' and balance = 0') = 1, 'draft invoices are not owed');
  update public.ir_invoices set status = 'sent' where id = inv;
  perform t.assert(t.rows('select 1 from public.ir_customers where id = ''' || c || ''' and balance = 100.00') = 1, 'customer balance = sum of sent invoices');
  perform t.assert(t.denied('insert into public.ir_invoice_lines (invoice_id, subject_id, description, quantity, unit_price) values (''' || inv || ''', ''' || s || ''', ''late'', 1, 1)'), 'lines are frozen once the invoice is sent');
  perform t.assert(t.denied('insert into public.ir_refunds (invoice_id, subject_id, amount) values (''' || inv || ''', ''' || s || ''', 10)'), 'no refund on an unpaid (sent) invoice');
  update public.ir_invoices set status = 'paid' where id = inv;
  perform t.assert(t.rows('select 1 from public.ir_customers where id = ''' || c || ''' and balance = 0') = 1, 'paying the invoice clears the balance');
  perform t.assert(t.denied('update public.ir_invoices set status = ''sent'' where id = ''' || inv || ''''), 'paid cannot go back');

  -- refund rules: copy, amount bound, decision rights
  insert into public.ir_refunds (invoice_id, subject_id, amount, reason) values (inv, s, 60.00, 'late') returning id into r1;
  perform t.assert(t.rows('select 1 from public.ir_refunds where id = ''' || r1 || ''' and currency = ''USD'' and status = ''requested''') = 1, 'currency copied from the invoice');
  perform t.assert(t.denied('insert into public.ir_refunds (invoice_id, subject_id, amount, currency) values (''' || inv || ''', ''' || s || ''', 5, ''EUR'')'), 'clients cannot set refund currency');
  perform t.assert(t.denied('insert into public.ir_refunds (invoice_id, subject_id, amount) values (''' || inv || ''', ''' || s || ''', 100.01)'), 'refund larger than the invoice is rejected');
  perform t.assert(t.denied('insert into public.ir_refunds (invoice_id, subject_id, amount) values (''' || inv || ''', ''' || s || ''', 0)'), 'refund must be positive');
  perform t.assert(t.denied('update public.ir_refunds set amount = 5 where id = ''' || r1 || ''''), 'refund amount is immutable');
  insert into public.ir_refunds (invoice_id, subject_id, amount) values (inv, s, 60.00) returning id into r2;
  update public.ir_refunds set status = 'approved' where id = r1;
  perform t.assert(t.rows('select 1 from public.ir_invoices where id = ''' || inv || ''' and refunded_total = 60.00 and net = 40.00') = 1, 'refunded_total = approved refunds; net = total - refunded');
  perform t.assert(t.rows('select 1 from public.ir_refund_events where refund_id = ''' || r1 || ''' and kind = ''refund_approved'' and amount = 60.00') = 1, 'approval writes an outbox event');
  perform t.assert(t.denied('update public.ir_refunds set status = ''approved'' where id = ''' || r2 || ''''), 'second 60 would exceed the 100 paid: approval denied');
  update public.ir_refunds set status = 'rejected' where id = r2;
  perform t.assert(t.denied('update public.ir_refunds set status = ''approved'' where id = ''' || r2 || ''''), 'a decided refund cannot change');
  insert into public.ir_refunds (invoice_id, subject_id, amount) values (inv, s, 40.00) returning id into r3;
  update public.ir_refunds set status = 'approved' where id = r3;
  perform t.assert(t.rows('select 1 from public.ir_invoices where id = ''' || inv || ''' and net = 0.00') = 1, 'the full amount can be refunded, exactly');
  perform t.assert(t.denied('insert into public.ir_refunds (invoice_id, subject_id, amount) values (''' || inv || ''', ''' || s || ''', 0.01)'), 'nothing left to refund');
  perform t.assert(t.denied('update public.ir_invoices set status = ''void'' where id = ''' || inv || ''''), 'an invoice with approved refunds cannot be voided');
  perform t.assert(t.denied('delete from public.ir_invoices where id = ''' || inv || ''''), 'only draft invoices can be deleted');
  perform t.assert(t.denied('delete from public.ir_refunds'), 'refunds cannot be deleted');
  perform t.assert(t.denied('insert into public.ir_refund_events (refund_id, subject_id, kind, amount, currency) values (''' || r1 || ''', ''' || s || ''', ''refund_approved'', 1, ''USD'')'), 'clients cannot forge events');

  -- an invoice with no refunds can be voided; drafts can be deleted with their lines
  insert into public.ir_invoices (subject_id, customer_id, number) values (s, c, 'INV-2') returning id into inv2;
  insert into public.ir_invoice_lines (invoice_id, subject_id, description, quantity, unit_price) values (inv2, s, 'x', 1, 5);
  delete from public.ir_invoices where id = inv2;
  perform t.assert(t.rows('select 1 from public.ir_invoice_lines where invoice_id = ''' || inv2 || '''') = 0, 'deleting a draft removes its lines');

  -- isolation
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.ir_invoices') = 0 and t.rows('select 1 from public.ir_refunds') = 0 and t.rows('select 1 from public.ir_customers') = 0, 'other users see nothing');
  perform t.assert(t.denied('insert into public.ir_customers (subject_id, name) values (''' || s || ''', ''intruder'')'), 'cannot add customers to a foreign subject');
  perform t.assert(t.denied('insert into public.ir_refunds (invoice_id, subject_id, amount) values (''' || inv || ''', ''' || s || ''', 1)'), 'cannot refund a foreign invoice');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.ir_invoices'), 'anon denied');
end $$;
rollback;
