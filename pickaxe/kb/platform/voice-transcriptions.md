# Voice transcriptions (voice-transcriptions)

Audio in, transcript and summary out, kept per person and charged by the database or by the platform that did the work.

Tier: official. Version 0.1.1. Voice-to-text jobs (the BuilderKit voice_transcriptions table) as a child of item-tracker: the audio key, transcript and summary, charged up front or recorded from an outside service.

## Who it's for

Builders of a voice-to-text or meeting-notes app who want the job record, credits and transcript storage done safely.

## What you get

- A transcription per audio file: the audio key, the transcript and an optional summary, owned by a workspace.
- Credits charged before the job and refunded exactly once on failure; replays change nothing.
- A way to record transcripts made elsewhere without charging core credits.
- Audio is a private storage key, never an expiring link.

## Works well with

item-tracker, subject-individual, youtube-content.

## Under the hood

A child of item-tracker: every transcription is an item with a 1:1 job row. Clients can read their jobs but cannot write them.
