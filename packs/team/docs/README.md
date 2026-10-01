# team
Core already stores membership (`subject_members`) and every pack's policies honour it through `has_subject_access`.
This pack is the *workflow*: invite by email -> token -> accept -> remove. Without it, subjects are single-owner.
The app emails the token returned by `team_invite` (e.g. via the Loops integration pack) and calls `team_accept` after sign-in.
