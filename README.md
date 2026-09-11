# Auto All

Source for the Project Zomboid mod [Auto All](https://steamcommunity.com/sharedfiles/filedetails/?id=3777237134)
by Robson Foster, Workshop item 3777237134, mod id `AutoAll`.

This repo began as the source for a fix fork, Auto All (Fixed), Workshop item
3792445930. The fixes went upstream, the fork went further, and with
maintainer access granted the whole line has been ported back onto the
original. The fork is retired and this repo is now the original's source.

Layout is the Workshop item layout, so `Contents/mods/AutoAll/42/` is the mod.
`workshop.txt` carries the item id, title, description and tags, and the
in-game uploader overwrites the live listing with them, so treat that file as
the published page rather than as notes. `preview.png` is the listing image,
and it is uploaded too, so it has to be the real one rather than a placeholder.

Three limits the uploader will not tell you about. It fails with
`failed to update workshop item, result=8`, which is Steam's
`k_EResultInvalidParam`, and names none of them:

- **Description: 8000 BYTES max, not characters.** This description is full of
  emoji and CJK, which cost three to four bytes each, so the byte count runs
  about 160 ahead of the character count. Measure with
  `len(text.encode('utf-8'))`. The uploader also appends a
  `Workshop ID:` / `Mod ID:` footer, about 42 characters, on every run, so
  keep the description under roughly 7900. Three copies of that footer had
  accumulated on the live listing before this repo took the description over.
  Running `./deploy.sh` before each upload overwrites the staged
  `workshop.txt` from here, which is what stops it accumulating again.
- **Title: 128 bytes max.**
- **Tags must match `media/WorkshopTags.txt` exactly**, and the submit screen
  silently drops any it cannot match rather than failing. The spelling is
  `QoL`, not the `QOL` the Steam web API reports. After a failed submit,
  check `git diff` on the staged `workshop.txt`: the screen writes the form
  back over it, so a dropped tag shows up there.

`AUDIT-*.md` are code audits. Release notes are not kept here: they are
written straight into the Workshop change log, which is the only copy.

Release: commit, then `./deploy.sh`, then upload from the in-game Workshop
screen. The folder under `~/Zomboid/Workshop/` is a build output, never edit
it directly.

The mod ships as a Steam Workshop item, so testing a change means running the
staged copy as a local mod. Unsubscribe from the Workshop item first, or the
game sees mod id `AutoAll` twice.

Run the automated Lua regression checks with `sh tests/run.sh`. These use
game API stubs, so worn clothing visuals and multiplayer behavior still need
an in-game check.
The repair sync integration test also loads the installed vanilla Lua action
when available. Set `PZ_JAVA_DIR` to the game's `Java` directory on other
machines. Its Java mutation and network endpoints remain stubbed.

The worn-clothing repair sync fix requires Auto All in the host/server's
enabled mod list. It sends the server's repaired garment state after a full
repair, including repairs started from the normal clothing menu. The
automations still work with a client-only installation, but that installation
cannot correct the server's missing update. Restart the host/server after
updating the mod.
