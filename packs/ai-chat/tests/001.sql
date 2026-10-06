-- Suite for ai-chat 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; c uuid; c2 uuid; n integer;
begin
  a := t.make_user('cht-a@example.test'); b := t.make_user('cht-b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  perform t.assert(t.denied('select public.cht_start(''' || s || ''', ''' || a || ''', ''deepseek'', ''r1'', ''x'')'), 'users cannot start chats directly');
  perform t.assert(t.denied('insert into public.cht_chats (item_id, subject_id, requested_by, provider) values (gen_random_uuid(), ''' || s || ''', ''' || a || ''', ''x'')'), 'clients cannot insert chats');
  perform t.as_service();
  c := public.cht_start(s, a, 'deepseek', 'r1', 'Trip ideas', 'conv-1');
  perform t.assert(c = public.cht_start(s, a, 'deepseek', 'r1', 'Trip ideas', 'conv-1'), 'a replayed start returns the same chat');
  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || c || ''' and kind = ''chat'' and title = ''Trip ideas''') = 1, 'start creates the base item');
  perform t.assert(public.cht_append(c, 'user', 'Where should I go?', 'm-1') = 1, 'first message is position 1');
  perform t.assert(public.cht_append(c, 'assistant', 'Try Lisbon.', 'm-2') = 2, 'second message is position 2');
  perform t.assert(public.cht_append(c, 'user', 'Where should I go?', 'm-1') = 1, 'a replayed message returns its position');
  perform t.assert((select message_count = 2 from public.cht_chats where item_id = c), 'message count tracks appends');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || c || '''') = 0, 'no credits touched by default');
  perform public.cht_append(c, 'assistant', 'Or Porto.', 'm-3', 1);
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''cht:' || c || ':3'' and amount > 0') = 1, 'a positive cost is charged in the same transaction');
  perform public.cht_append(c, 'assistant', 'Or Porto.', 'm-3', 1);
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''cht:' || c || ':3''') = 1, 'a replay never charges twice');
  perform t.assert(t.denied('select public.cht_append(''' || c || ''', ''assistant'', ''x'', ''m-9'', 1000000000)'), 'an unaffordable cost is refused');
  perform t.assert(t.rows('select 1 from public.cht_messages where item_id = ''' || c || ''' and external_ref = ''m-9''') = 0, 'a refused charge stores no message');
  perform t.assert(t.denied('select public.cht_append(''' || c || ''', ''robot'', ''x'')'), 'unknown roles are refused');
  perform t.assert(t.denied('select public.cht_append(''' || c || ''', ''user'', '''')'), 'empty messages are refused');
  perform t.assert(t.denied('select public.cht_start(''' || s || ''', ''' || b || ''', ''deepseek'', ''r1'', ''x'')'), 'starting for a user without subject access is refused');
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.cht_messages where item_id = ''' || c || '''') = 3, 'the owner reads the messages');
  perform t.assert(t.denied('update public.cht_messages set content = ''edited'' where item_id = ''' || c || ''''), 'clients cannot edit messages');
  perform t.assert(t.denied('delete from public.cht_messages where item_id = ''' || c || ''''), 'clients cannot delete messages');
  perform t.assert(t.denied('select public.cht_append(''' || c || ''', ''user'', ''x'')'), 'users cannot append');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.cht_chats') = 0 and t.rows('select 1 from public.cht_messages') = 0, 'other users see nothing');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.cht_messages'), 'anon denied');
end $$;
rollback;
