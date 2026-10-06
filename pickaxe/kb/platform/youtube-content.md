# YouTube content (youtube-content)

Turn a video's transcript into summaries and social content, kept per person with the source link.

Tier: official. Version 0.1.0. Video-to-content records (the BuilderKit youtube_content_generator table) as a child of item-tracker: link, title, language, transcript, summary and generated content, recorded once by the server with an optional core charge in the same transaction.

## Who it's for

Builders of a video-to-content app who want the record and credits done safely.

## What you get

- A piece per video: link, title, language, transcript, summary and generated content, owned by a workspace.
- Record a finished piece and, optionally, charge core credits in the same transaction; a replay returns the same piece.
- A way to record pieces made elsewhere without charging core credits.

## Works well with

item-tracker, subject-individual, chat-with-youtube.

## Under the hood

A child of item-tracker: every piece is an item with a 1:1 record row. Transcription and generation happen outside the database; a service-role function records the result once.
