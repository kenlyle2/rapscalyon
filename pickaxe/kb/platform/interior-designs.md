# Interior designs (interior-designs)

AI room redesigns, owned by the person who made them, saved safely and charged either by the database or by the outside platform that made them.

Tier: official. Version 0.2.0. AI room redesigns as a child of item-tracker: prompt, room type, theme and a reference photo become either a generation job charged up front in core credits and refunded once on failure, or a design recorded from an outside generator such as a Pickaxe agent, whose own credits are then the only ledger and which charges no core credits. Written from the BKIDA schema and behaviour, with no BuilderKit code.

## Who it's for

Builders of an interior-design app, or any room-makeover product, who want the generation record, credits and result storage done safely instead of rebuilt from a boilerplate.

## What you get

- A design per room: prompt, room type, theme, reference photo and the finished images, owned by the person's Space (a home or a business).
- Two ways to pay: the app's own generator can charge core credits before generation and refund exactly once on failure; or, when an outside platform such as Pickaxe makes the image, that platform's credits are the only ledger and the app charges nothing.
- A way to record designs made outside the app, for example by a Pickaxe agent, never charging core credits for them.
- Image locations are stored as private storage keys, never as links that expire.

## Works well with

item-tracker, subject-individual, interior-design-bid-process.

## In your customers' words

Customers see Spaces (a home or a business) and Designs; the technical terms never reach them.

## Under the hood

A child of item-tracker: every design is an item of kind interior_design with a 1:1 row for the generation job. Clients can read their designs but cannot write the job; only the server-side functions move it forward.
