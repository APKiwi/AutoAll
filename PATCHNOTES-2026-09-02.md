Audit pass. 86 findings fixed across every module. The short version.

Core
- Stall counter counts consecutive stalls, not cumulative. One slow craft no longer adds up to a false stop.
- Client batch only grows once a round filled and the server confirmed it. Stops the batch outrunning the server.
- Health-floor stop only fires when stop-on-damage is on. It was ending jobs you had told it not to end.
- Pausing no longer reads as you picking a speed. Fast forward comes back after unpause.
- Advanced options closes and refreshes properly. Panel shows the effective module state.

Cook
- Skip rotten always beats the skill slider.
- Sweeps only what you could walk to and open. Two tiles, never through a wall or a locked crate. It was pulling food through walls.
- Seasonings no longer count as a pleasant option. One of each unnamed spice.
- Disorganized cooks skip the return phase instead of failing it. Honest message when the recipe cannot be resolved.

Dismantle, Open, Sterilize
- Items in transit count as in transit, not gone. First round is no longer thrown away.
- Worn bags no longer counted twice. Nearby electronics was doubled.
- Empty rounds re-plan instead of spinning. Corpse containers handled. Stops say why.

Rip, Clean
- Corpse check walks the whole container chain. An item in a bag on a corpse was read as worn.
- Craft batch bounded by carry weight. Prefetch no longer double spends it.
- Returns only what the job produced. Missing tool reported as missing tool.
- Clean re-dresses on every stop and verifies it landed. Soap counted from the fetch, not read back too early.

Medicine, Reload
- Never dresses a bullet or burn wound without the tool. Never uses a dirty bandage. Says so.
- Each step runs a tick after its fetch, so the item is actually there.
- Supply ranking fixed for burns, dirty bandages and empty bottles.
- Reload holds the refill until the queue is empty on a client or in a vehicle. AmmoBag draws capped.

Mechanics
- A part put on the ground stays ours. Refits the part this job took off, not the best one in the bag.
- Stays at the corner while our part is on the ground there. No more zig-zag.
- Drops before the retry pin. Blocked parts given up on cleanly, unreachable count resets on reach.
- Counts parts done, not actions. Names parts left on the ground. Puts the car down on a safety stop.

Tailoring, Read, VHS
- One fabric instance per patch. Unpicks only our own. No worse-material fallback, says no match instead.
- Corpse garments left out of the holed sweep.
- Read tracks by full type so a second copy is not queued. A stuck book is skipped, not the job.
- VHS credits a tape only when it ran to the end. Each tape gets its own retry budget.

Exercise (MuscleManager)
- Runs as an Auto All task. ESC, stop-on-zombie and stop-on-damage apply, and starting another job ends it cleanly.
- Game speed is latched, not forced every tick. Change it yourself and the mod backs off.
- Every borrowed item returned on stop. One painkiller per session, never on top of an active one.
- Eats from your bag first, spoiling food first. Rests only on a seat in the same room. An open injury stops the session.
- AUTO box unticks with a reason when the job stops.
