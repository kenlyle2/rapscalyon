# subject-individual
For apps whose customers are people (job seekers, creators, patients). A *subject* of kind `individual` is one
profile the account manages; this pack adds `ind_details` and the `ind_max_subjects` plan limit (default 1).
Replace `ind_details` columns with your own via a *domain pack* that has its own `<prefix>_` side table keyed on `subject_id`.
Security notes: see SECURITY.md.
