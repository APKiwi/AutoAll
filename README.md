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
the published page rather than as notes. `preview.png` is the listing image.

`AUDIT-*.md` are code audits. `PATCHNOTES-*.md` are per-release notes.

Release: commit, then `./deploy.sh`, then upload from the in-game Workshop
screen. The folder under `~/Zomboid/Workshop/` is a build output, never edit
it directly.

The mod ships as a Steam Workshop item, so testing a change means running the
staged copy as a local mod. Unsubscribe from the Workshop item first, or the
game sees mod id `AutoAll` twice.
