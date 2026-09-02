# Auto All (Fixed)

Fork of Auto All by Robson Foster, Workshop 3792445930. Started as a fix fork
whose fixes went upstream. Now its own line: a full audit pass with every
finding fixed, plus features the original does not have (Auto Cook fills the
pot from nearby water, Auto Exercise runs as an Auto All task). Fixes found
here are still offered upstream.

Layout is the Workshop item layout, so `Contents/mods/AutoAllFixed/42/` is the
mod. `workshop.txt` carries the item id. `AUDIT-*.md` are code audits.

Release: commit, then `./deploy.sh`, then upload from the in-game Workshop
screen. The folder under `~/Zomboid/Workshop/` is a build output, never edit
it directly.
