# Text to speech (text-to-speech)

Turn text into spoken audio and keep each clip per person, recorded safely whether the app or an outside platform made it.

Tier: official. Version 0.1.0. Text-to-speech clips (the BuilderKit text_to_speech table) as a child of item-tracker: title, text, model, voice and an audio key, recorded once by the server with an optional core charge in the same transaction.

## Who it's for

Builders of a text-to-speech app who want the clip record, credits and audio storage done safely.

## What you get

- A clip per request: title, text, model, voice and the audio, owned by a workspace.
- Record a finished clip and, optionally, charge core credits in the same transaction; a replay returns the same clip.
- A way to record clips made elsewhere without charging core credits.
- Audio is a private storage key, never an expiring link.

## Works well with

item-tracker, subject-individual, music-generations.

## Under the hood

A child of item-tracker: every clip is an item with a 1:1 record row. Generation happens outside the database; a service-role function records the result once.
