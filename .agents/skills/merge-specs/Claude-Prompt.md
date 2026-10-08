# Claude prompt: merge overlapping docs into one spec

Paste-in form of the `merge-specs` skill (see `SKILL.md` in this folder) for any Claude chat that doesn't have the skill installed. Replace the bracketed parts.

```
Read all the files in [folder / links / attached files]. Read each in full; if any
file can't be read, tell me which and ask for an export instead of guessing.

Treat the most complete and current one as the spine and fold the rest into it,
mapping their terms onto its vocabulary. Pick one canonical term where the sources
use several.

List every conflict (stack, scope, order, numbers, naming, ranking logic) as
[DECIDE] with a recommended default, and ask me to rule on them together. Do not
silently resolve any. When I decide, rewrite the text as "DECIDED — ...", remove
the tag, and prune the dead alternatives.

Put the product material first and the implementation guidance after a divider line:
========== IMPLEMENTATION NOTES (Builder and worker only; Interviewer stops reading
above this line) ==========
Everything above the divider must read as a client would say it: no pack names, table
names, vendors or stack advice. Add a short "Decisions" list above the divider, each
with who decided and when, and a one-line reading guide at the top saying which side
[the downstream agent, e.g. the Interviewer] uses.

Merge [outside analysis, if any] by adopting ideas, not text: rewrite into the
spec's vocabulary, let the spec win where they conflict, record the differences in
a short table, and fix any flaws you find in it.

Finish with a consistency pass over the whole file: every field used anywhere is
defined in the data model; enums and labels match; no section still describes a
rejected option; numbers and weights add up with stated defaults; cross-references
resolve; no [DECIDE] left unless intentionally open. Fix what you find.

Save the file and give me the path. Then summarize what was merged, how each
conflict closed, the calls you made that I should veto, the fixes from the
consistency pass, and anything you could not read.
```
