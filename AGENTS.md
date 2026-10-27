# Auto All contributor instructions

Read [README.md](README.md) for the source layout, deployment boundary, and regression commands.
`CLAUDE.md` imports this file so every harness receives the same Workshop rules.

Keep root instructions within 16 KiB combined. Check edits with
`sh scripts/check-agent-instructions.sh --tree` and put detailed reference material in linked docs.

## Steam Workshop change notes

When drafting change notes for this mod:

- Match the established style at https://steamcommunity.com/sharedfiles/filedetails/changelog/3777237134.
- Return a paste-ready plain-text block with matching `ENGLISH` and `PORTUGUES (BR)` sections.
- Use `NEW` and `FIXES`, with `NOVIDADES` and `CORRECOES`, only when those sections are needed.
- Keep the notes short and terse. Cover player-visible behavior only, with one compact paragraph per change.
- Include defaults or important exceptions when they affect how the feature behaves.
- Credit the reporter by Steam display name when known.
- Keep the Brazilian Portuguese text ASCII-only to match the existing Workshop entries.
- Do not add an introduction, summary, testing details, implementation details, or filler unless the user asks.
- Never commit the notes. They go straight to the Workshop change log, which is the only copy. `PATCHNOTES-*.md` is gitignored.

## Programs, docs and scratch

- Docs describe the system as it is today. Update them in the same commit as the behaviour they describe,
  with each reason or gotcha next to the behaviour it explains. Delete superseded text, git history is the
  archive. Never name a doc by date.
- A long-running program, meaning work that spans more than one landing, has one tracker at
  `docs/programs/<name>.md` in the shape [docs/programs/README.md](docs/programs/README.md) sets. Update it
  in the same commit as each milestone. When the program is done, move every decision still in force into
  the docs and delete the tracker.
- Specs, plans, subagent ledgers and brainstorm output under `docs/superpowers/` and `.superpowers/` are
  local scratch. They are never committed, and no tracked file names a file inside them, whatever a skill
  says. `scripts/check-scratch.sh` enforces this.
- A branch is not done until the docs describe its behaviour and every ruling, reason or gotcha from its
  plan that still applies is in a doc or in the program's decisions in force.
- A merge that reports a modify/delete conflict on a scratch file: copy the file aside, `git rm --cached`
  it, then put the copy back.
