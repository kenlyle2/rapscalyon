# social-posts
Drafts and a schedule. The app's publisher (a cron route) calls `sp_claim_due_posts()` with the service role, posts through each
connector, then marks the row `published` or `failed`. Platform tokens belong in `user_credentials` (service-only), never in this pack's tables.
