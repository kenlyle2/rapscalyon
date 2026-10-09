# Music generations (music-generations)

Text-to-music jobs with genre, mood and length kept per person, charged by the database or by the platform that made them.

Tier: official. Version 0.1.1. Text-to-music generation jobs (the BuilderKit music_generations table) as a child of item-tracker: prompt, genre, mood, duration and an audio key, charged up front or recorded from an outside generator.

## Who it's for

Builders of an AI music app who want the job record, credits and track storage done safely.

## What you get

- A track per prompt: prompt, genre, mood, duration and the finished audio, owned by a workspace.
- Credits charged before the job and refunded exactly once on failure; replays change nothing.
- A way to record tracks made elsewhere without charging core credits.
- Audio is a private storage key, never an expiring link.

## Works well with

item-tracker, subject-individual, text-to-speech.

## Under the hood

A child of item-tracker: every track is an item with a 1:1 job row. Clients can read their jobs but cannot write them.
