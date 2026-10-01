# posthog-analytics

Before sending any PostHog event or enabling session replay for a signed-in user, server code calls
`ph_may_track(profile, 'analytics' | 'replay')`. Users edit `ph_consent` from the Privacy page.
Defaults: analytics on, replay off. `NEXT_PUBLIC_POSTHOG_KEY` / `NEXT_PUBLIC_POSTHOG_HOST` stay in the app environment.
