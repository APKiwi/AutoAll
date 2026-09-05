The fix fork is retired and everything in it now ships as Auto All itself.

Auto All (Fixed), Workshop 3792445930, existed because fixes could be
published there the day they were found. With maintainer access on the
original that reason is gone. This release is the fork's whole line landing on
Workshop 3777237134, mod id AutoAll, and the fork stops being updated.

Subscribers of the original get everything below. Subscribers of the fork get
nothing new here, they have had all of it since 2 September.

What arrives from the fork
- The audit pass. 86 findings across every module, all fixed. The detail is in
  AUDIT-2026-09-02.md and the player-facing summary in PATCHNOTES-2026-09-02.md.
  The ones people notice: stalls and false stops, honest stop messages, the
  corpse container chain, mechanics keeping hold of a part put on the ground,
  medicine refusing to dress a bullet wound without the tool, cook preferring
  skip-rotten over the skill slider, and clean re-dressing on every stop.
- Auto Cook fills an empty pot. Soup, stew and the hot drinks are offered on an
  empty pot or mug when a sink, barrel or well is within four tiles. The
  character walks over, fills it with the game's own action, then cooks. Clean
  water beats tainted, the sweep will not reach through a wall, and the setup
  window lists the real ingredient rows for a dish the pot has to be filled for.
- Auto Cook only sweeps what you could actually reach. Two tiles, never through
  a wall or a locked crate.
- Auto Exercise is a real Auto All job. ESC, stop-on-zombie and stop-on-damage
  apply to it, starting another job ends it cleanly, borrowed items go back, and
  game speed is latched rather than forced.

Already in the original, unchanged here
- The six items from the 2026-09-06 patch: the recipe magazine loop, the
  dismantle favourite, the splint, ignoring bystander NPCs, the VHS book gate
  and reading between sets. The fork took those from here on the day and they
  are carried through untouched, except that the splint now runs through the
  fork's plan and queue split and its dead needsWork line is gone.

Replaced
- The original's own pot filling, by the fork's. Same option key, so the
  tickbox keeps its setting. The fork's version handles a part filled pot,
  refuses a water bottle lying on the floor, prefers clean water and can show
  ingredient rows before it starts.

Nothing in this release changes a save. It is still 100% client side and still
safe to add to or remove from an existing game.
