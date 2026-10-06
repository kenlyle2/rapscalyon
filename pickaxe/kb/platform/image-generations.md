# Image generations (image-generations)

Text-to-image jobs with the prompt, settings and results kept per person, charged by the database or by the platform that made them.

Tier: official. Version 0.1.0. Text-to-image generation jobs (the BuilderKit image_generations table; also the base for the Ghibli-style variant) as a child of item-tracker: prompt, settings and result keys per job, charged up front and refunded once on failure, or recorded from an outside generator.

## Who it's for

Builders of an AI image app (any text-to-image model) who want the job record, credits and result storage done safely.

## What you get

- A generation per prompt: prompt, negative prompt, model, guidance, steps and number of outputs, owned by a workspace.
- Credits charged before the job and refunded exactly once if it fails; a replayed model callback changes nothing.
- A way to record images made elsewhere (for example by a Pickaxe agent) without charging core credits.
- Result images are private storage keys, never links that expire.

## Works well with

item-tracker, subject-individual, image-transforms.

## Under the hood

A child of item-tracker: every generation is an item with a 1:1 job row. Clients can read their jobs but cannot write them.
