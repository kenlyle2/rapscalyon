# Image transforms
> Upscale, enhance or restyle an image and keep the input, the result and the cost per person.

## Who it's for
Builders of an image-enhancer, upscaler or style-transfer app (including Ghibli-style) who want job tracking and credits done safely.

## What you get
- A job per image: transform type, the input image and the finished result, owned by a workspace.
- Credits charged before the job and refunded exactly once on failure; replays change nothing.
- A way to record transforms made elsewhere without charging core credits.
- Input and output are private storage keys, never inline images or expiring links.

## Works well with
item-tracker, subject-individual, image-generations.

## Under the hood
A child of item-tracker: every transform is an item with a 1:1 job row. Clients can read their jobs but cannot write them.
