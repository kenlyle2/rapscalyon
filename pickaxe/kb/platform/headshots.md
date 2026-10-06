# Headshots (headshots)

Train a personal model from a person's photos and generate professional headshots from it, with every step tracked and charged safely.

Tier: official. Version 0.1.0. AI headshots as two children of item-tracker (BuilderKit headshot_models and headshot_generations): train a personal model from uploaded photos, then generate headshots from a finished model of the same workspace, charged up front or recorded from an outside generator.

## Who it's for

Builders of an AI headshot app who want model training and generation records, credits and photo storage done safely.

## What you get

- A personal model per person: name, type, the training photos and its status, with an expiry when the provider deletes it.
- A headshot per prompt, generated from a finished model of the same workspace only.
- Credits charged before training and before each generation, refunded exactly once on failure; replays change nothing.
- Photos and results are private storage keys, never inline images or expiring links.

## Works well with

item-tracker, subject-individual, image-generations.

## Under the hood

Two children of item-tracker: models (kind headshot_model) and headshots (kind headshot). A headshot references a succeeded model of the same workspace through a composite key. Clients can read but cannot write.
