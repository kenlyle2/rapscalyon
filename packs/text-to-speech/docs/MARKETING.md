# Text to speech
> Turn text into spoken audio and keep each clip per person, recorded safely whether the app or an outside platform made it.

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
