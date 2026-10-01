# Social post scheduler
> Draft, schedule and track posts for any workspace. Bring your own publishing connectors.

## Who it's for
Small businesses and creators who want a queue of posts that publishes itself.

## What you get
- Draft and scheduled states, scheduled-time validation, retry of failed posts.
- A safe claim function so two workers never publish the same post.
- Credit-priced AI operations for generating text and images.

## Works well with
subject-business, team, real-estate-listings, loops-email.

## Under the hood
Users cannot mark a post published; only the publisher (service role) moves posts through publishing states. Connector tokens belong in core `user_credentials`, never in this pack.
