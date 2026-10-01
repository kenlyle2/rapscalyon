# Team access (team)

Invite colleagues to a workspace by email. They see what the workspace sees, nothing else.

Tier: official. Version 0.1.0. Share a subject with other users: invite by email, accept by token, remove members. Writes core subject_members through audited functions.

## Who it's for

Any app where one account needs to share work with staff, partners or clients.

## What you get

- Invite by email with admin, member or viewer roles; invitations expire after 7 days.
- One accept link; removing a member revokes access to every installed pack at once.
- Owner-only management, with every change going through audited server functions.

## Works well with

subject-business, real-estate-listings, item-tracker, social-posts.

## Under the hood

Invite tokens are bearer credentials only the owner can read. Members never gain table-level write access to membership data.
