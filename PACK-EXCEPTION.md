# Pack Interface Exception to the AGPL-3.0-or-later

**Status: drafted by the maintainer, not yet reviewed by counsel.**

This is an additional permission under section 7 of the GNU Affero General Public License, version 3, granted by the copyright holder of RapScalYon core, the app base code and the official packs in this repository (together, "the Program"). It applies to the Program in addition to the licence in `LICENSE`.

## Permission

A **pack** is a directory containing a `pack.toml` that the Program's installer (`tools/rapscalyon.py pack add`) accepts. A pack that

1. contains no file, and no part of a file, copied from the Program, and
2. interacts with the Program only through the interfaces the Program documents for packs, namely the `pack.toml` format and the installer, and the tables, columns, functions, views and routes of core and of other packs that are documented in this repository or in a pack's `docs/`,

is an independent work and not a work based on the Program. It may be licensed on any terms its author chooses, including proprietary terms, and installing it into a database or application that also runs the Program does not, by itself, require it to be offered under the AGPL.

## What this does not change

- **Modifications to the Program stay AGPL.** Changing a file of core, the app base code or an official pack, or copying one into a pack, creates a work based on the Program that remains under `LICENSE`, including the section 13 duty to offer the corresponding source of the modified version to its network users.
- **The Program itself.** Anyone who runs the Program, modified or not, keeps every right and duty the AGPL gives or imposes for the Program's own code.
- **Official and verified packs** must still be AGPL (`CONTRIBUTING.md`).

## Removal

As section 7 allows, a recipient may remove this additional permission from a copy or part of the Program they convey. The permission then does not apply to that copy or part.
