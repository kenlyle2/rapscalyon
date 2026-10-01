# real-estate-listings
Listings and photos scoped to a subject. Install with `subject-business` (agency) or `subject-individual` (solo agent);
add `team` so colleagues see the same listings. Photos are stored as paths; the file bytes live in your storage bucket.
Metered operations (`rel.generate_description`, `rel.enhance_photo`) are registered at price 0; set real prices in
`operation_pricing`, and charge server-side with `charge_credits(user, cost, idempotency_key, operation)` before calling a model.
