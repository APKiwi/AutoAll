# Auto All (Fixed)

Fix fork of Auto All by Robson Foster, Workshop 3792445930. Tracks the original
file for file; fixes ship here the day they are found, then go upstream.

Layout is the Workshop item layout, so `Contents/mods/AutoAllFixed/42/` is the
mod. `workshop.txt` carries the item id. `AUDIT-*.md` are code audits.

Release: commit, then `./deploy.sh`, then upload from the in-game Workshop
screen. The folder under `~/Zomboid/Workshop/` is a build output, never edit
it directly.
