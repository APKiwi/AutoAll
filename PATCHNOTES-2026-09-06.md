Upstream sync. Auto All published a patch on 2026-09-06 and this takes the
six things in it that this fork did not already have. Everything below is
Robson Foster's work unless it says otherwise.

Bug fixes
- Auto Read no longer offers the same recipe magazine for ever. The old test
  compared how many recipes are known against how many the magazine teaches,
  and a recipe the character cannot learn never joins the known list, so the
  count never caught up. It now asks the game whether the book has been read,
  which is what the game itself records.
- Auto Dismantle skips a favourite instead of losing the whole round to it.
  One favourited watch used to stop the batch with "something went wrong",
  because vanilla refuses to consume a protected item and the round was
  abandoned rather than the item. New tickbox, on by default, matching the
  one Auto Rip has always had.

New options
- Auto Medicine splints a fracture before dressing it, using a splint, or a
  plank and a ripped sheet. Vanilla's own rules: never the head or the torso,
  never a stitched or already splinted part. On by default.
- Safety no longer stops for an NPC that is not hunting you. Every NPC mod
  builds its characters as zombies, so a companion walking past counted as
  the horde arriving. A real zombie, and an NPC that has you as its target,
  still stop the job. On by default.
- Auto VHS can be told to watch only tapes whose skill book you have read. A
  tape's XP is multiplied by the book's bonus and its lines are spent either
  way, so watching one early throws most of it away. Off by default. Skills
  with no book in the game are always watched.
- Auto Exercise can read a book from your own bag between sets and put it
  down the moment endurance is back. Off by default. It uses Auto Read's
  judgement of what is worth reading, so it follows the switches you have
  already set. Resting on furniture keeps the vanilla rest action running and
  no book is opened during those rests.

Also
- The water source for Auto Cook is now confirmed with the game's own fill
  test, so a source that holds water but would not pour into this particular
  pot is not offered.
- The new messages are translated into all sixteen languages, taken from
  upstream. The audit messages this fork added on 2026-09-02 are still
  English only.

Not taken
- Upstream's own version of filling a pot from a water source. This fork
  shipped that feature on 2026-09-02 and the version here does more: a wall
  test on the sweep, water bottles on the floor left alone, clean water
  preferred over tainted, and the setup window listing real ingredient rows
  for a dish the pot has to be filled for first.

Departures from upstream's patch
- Upstream's splint check sits behind an isInjured() gate that its own new
  line cannot pass, and the comment explaining it says a fracture does not
  answer HasInjury(). It does: BodyPart.HasInjury() ORs getFractureTime() > 0
  in with the bites and the cuts. The dead line is left out here and the gate
  is HSplint's own, verbatim.
- The splint runs through this fork's plan/queue split rather than queueing
  the action inline, so a plan can now carry the two items vanilla's
  plank-and-sheet variant needs.
