# builderkit_packs

Renders the twelve packs converted from the BuilderKit apps (`python3 specs1.py` for the nine job and record packs, `python3 specs2.py` for the docs of the three chat packs; the chat SQL is written by hand). The input is the apps' generated table types (branch `all-apps` of the owner's licensed BuilderKit-Pro repo); no BuilderKit source is read into a pack. Output goes to `packs/` (this repo; the packs are official and public as of 2026-10-06); review the diff and run `rapscalyon.py pack validate` and `test --pack` for every pack after any change.
