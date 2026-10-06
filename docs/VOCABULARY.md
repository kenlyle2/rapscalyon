# Vocabulary: core words and product words (DRAFT 2026-10-05)

Core uses three structural words. Customers never need them: each product says them in its own language, in its screens, its Pickaxe agents and its interview questions. The table names stay the same everywhere.

| Core word | Table | What it is | Interior design app says | Other products might say |
|---|---|---|---|---|
| Account | `auth.users` + `public.profiles` | One person's login, plan and credits | Account | Account |
| Subject | `public.subjects` (kind `individual` or `business`; `subject_members` for sharing) | Whose data this is. An account owns one or many; others can be added as members | **Space**: a home, a property or a business | Workspace, Business, Client, Household |
| Item | `public.it_items` (item-tracker) and its child packs | A thing tracked inside a subject, with a history | **Design** (item kind `interior_design`) | Job, Listing, Post, Invoice |

Every row a pack stores belongs to a subject, and row-level security checks access through the subject. That is the whole security model, so these tables are not renamed.

## Why we do not rename `subjects` and `it_items`

- Every pack, policy, function, foreign key and test refers to them by name. A rename would break every installed database and every pack's rollback.
- The names are internal. People see the product words above, never table names.
- Different products need different words for the same structure (Space, Workspace, Client). One rename could not fit them all.

If a product ever needs the words in the database (for example to show them in an admin screen), add a small label setting per product, not a rename. Not built.

## Interior design: how the words map

- Account = the person who signs in (WordPress, Pickaxe).
- Space = a home or a business the designs belong to. A person with a beach house and a city flat has two Spaces. The first one is created automatically the first time they save a design ("My designs"); more are created when the person names one ("Beach house"). The free plan allows one individual Space (`ind_max_subjects`); higher plans raise it.
- Design = one saved redesign: the prompt, room, style, the reference photo and the images.
- **Project** (a renovation grouping several designs, for example "Kitchen remodel") is not modelled for the end-user version. The professional pack `interior-design-bid-process` has projects, specs and bids for designers. Whether end users need a lightweight Project is an open owner decision.

## In the Pickaxe flow

- Say "Space" (or "home") to the user, never "subject" or "item".
- Ask which Space only when the person has more than one; otherwise save to the default without asking.
- The `space` input of the save action is the Space's name. A name that does not exist yet creates a new Space (subject to the plan limit).
