# Real-estate listings (real-estate-listings)

Property listings with photos, pricing and status, ready for an agency or an individual agent.

Tier: official. Version 0.1.0. Property listings with photos and a publish workflow; AI description generation is a metered operation.

## Who it's for

Agents, brokers and property managers who need to list and track properties without building a CRM first.

## What you get

- Listings with type, price in minor units, currency, beds, baths, area and structured address.
- Draft, active, pending, sold and withdrawn lifecycle.
- Photo records tied to private storage paths, shared automatically with your team.

## Works well with

subject-business, team, social-posts, turnstile.

## Under the hood

Prices are integers, not floats. Photos live in the private core `media` bucket under the subject's folder, so access rules match the listing's.
