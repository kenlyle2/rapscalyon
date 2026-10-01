# subject-business
For apps whose customers are people (shops, clinics, agencies). A *subject* of kind `business` is one
profile the account manages; this pack adds `biz_details` and the `biz_max_subjects` plan limit (default 1).
Replace `biz_details` columns with your own via a *domain pack* that has its own `<prefix>_` side table keyed on `subject_id`.
Security notes: see SECURITY.md.
