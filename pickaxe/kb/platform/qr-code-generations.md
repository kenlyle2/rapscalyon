# QR code generations (qr-code-generations)

Artistic QR codes made from a prompt and a link, kept per person and charged by the database or by the platform that made them.

Tier: official. Version 0.1.0. AI QR-code generation jobs (the BuilderKit qr_code_generations table) as a child of item-tracker: prompt, target URL and an image key, charged up front or recorded from an outside generator.

## Who it's for

Builders of an AI QR-code app who want the job record, credits and image storage done safely.

## What you get

- A QR code per request: prompt, target link and the finished image, owned by a workspace.
- Credits charged before the job and refunded exactly once on failure; replays change nothing.
- A way to record codes made elsewhere without charging core credits.
- The image is a private storage key, never an expiring link.

## Works well with

item-tracker, subject-individual, image-generations.

## Under the hood

A child of item-tracker: every QR code is an item with a 1:1 job row. Clients can read their jobs but cannot write them.
