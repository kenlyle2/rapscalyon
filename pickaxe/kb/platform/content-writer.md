# Content writer (content-writer)

Keep every AI-written article per person with the topic, style and voice that produced it.

Tier: official. Version 0.1.0. AI-written content pieces (the BuilderKit content_creations table) as a child of item-tracker: topic, style, voice, word limit and the text, recorded once by the server with an optional core charge in the same transaction.

## Who it's for

Builders of an AI writing app who want the content record and credits done safely.

## What you get

- A piece per request: topic, style, voice, word limit and the finished text, owned by a workspace.
- Record a finished piece and, optionally, charge core credits in the same transaction; a replay returns the same piece.
- A way to record pieces written elsewhere without charging core credits.

## Works well with

item-tracker, subject-individual, youtube-content.

## Under the hood

A child of item-tracker: every piece is an item with a 1:1 record row. Generation happens outside the database; a service-role function records the result once.
