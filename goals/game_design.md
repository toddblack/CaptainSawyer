# Captain Sawyer — Game Design Document

> Living document. Update as decisions are made. Mark open questions with ❓ and resolved ones with ✅.

---

## Vision

**Premise ✅ (canonical — see `goals/storyline.md`):** a deep-space crew crash-lands on an alien
ocean world. Captain Sawyer washes ashore with two crewmates; the other ten are scattered across
the sea in abort capsules. No charts, no comms, no idea if anyone else lives here.

Exploration-first, survival-informed. Find your crew, salvage the capsules, learn the alien
materials, build better boats, push the map outward — and, maybe, meet whoever else is out there
through **trade, diplomacy, and shared innovation**.

The world advances because *you* brought ideas back from far-off places — and gave ideas away too.
You don't invent the compass — you find lodestone on a distant island, figure out what it does, and show it to every people you meet along the way.

**Design philosophy:** Trade and compassion over conquest. Diverse peoples thrive when connected.
The goal is a world where different communities all move forward together — not a zero-sum empire.
Conflict exists (communities can falter, resources can run short) but it's never the primary mechanic.

**Tone:** Playful and warm at the start. Gets richer and more complex as the world opens up.
Not grimdark. Not a war game. A world worth exploring and worth caring about.

---

## Core Loop

```
Start on the crash-site island (Sawyer + Biologist + Surgeon, a small first boat)
    → Sail out into unknown ocean (fog of war)
        → Discover island
            → Encounter: resources / a capsule & stranded crewmate / wreckage & tech /
              (much later) signs of — and contact with — inhabitants
                → Diplomacy: share knowledge, offer materials, earn trust
                OR Gather: collect materials from terrain/biome
                    → Bring back to home island (or any settlement)
                        → Materials + knowledge unlock new inventions
                            → Inventions: better navigation, larger ship, new buildings
                                → Larger ship → explore further → discover more
                                → Trade routes form between connected islands (automated)
                                    → (Loop expands in scale)
```

---

## Pillars

### 1. Home Island (crash site) ✅

- The player starts on the island where Sawyer's capsule came down ("Sawyer's Rest")
- It begins as a survival camp — shelter, capsule salvage, a first improvised boat — and grows
  into the crew's base as rescued specialists (engineers, agriculturalist…) join
- Home island is the anchor: save point, return destination, first settlement
- Sawyer's own capsule lies sunk in the shallows — recoverable later (diving tech)
- Progression radiates outward from here
- ❓ Can home island be lost/threatened? (Probably not early game — it's the safety anchor)

### 2. Progression & Death ✅ (mostly)

- **Roguelite, not roguelike** — death doesn't erase everything
- The question the game asks: *How far can you innovate? How far can you reach?*
- On death: lose current ship + crew, but discoveries/maps/relationships persist
  (Like: the home island remembers what you found, even if the captain didn't make it back)
- ❓ Exact death/carry-over rules — decide when we build the save system
- World state (islands, trade routes, settlements) persists across runs within a world
- **Each new world** = different procedural seed, fresh exploration
- **Save system** needed: player returns to their world with full state intact

### 3. Exploration ✅

- Fog of war hides the world — already built ✅
- **No compass at start** — navigate by feel, landmarks, stars
- Islands appear on minimap when discovered — already built ✅
- Discovery toast notification — already built ✅
- **Diplomacy through discovery:** showing peoples what you've found is itself a gift
  (Show a compass to a people who've never seen one — that changes their world)
- ❓ Navigation mechanics at night without compass (harder? stars?)
- World scale: needs to feel **global** to be compelling ✅

### 4. Islands ✅

- Procedurally generated — already built ✅, needs major scaling
- **Much larger islands** — room for terrain variety, settlements, biomes
- **Multiple biomes per island** — plains + mountains + volcano, jungle + coast, etc.
- **Island types:**
  - Uninhabited — resources only, colonisable
  - Inhabited (friendly) — trade, cultural exchange, possible alliance
  - Inhabited (wary/neutral) — earn trust through offering useful things
  - Resource-specific — defined by biomes (volcanic → lodestone/iron, jungle → hardwood/spices)
- **Diplomacy mechanic:** Each community has needs you might be able to fill
  (Something on an island yet to be explored? Now you have a reason to go there for them)
- ❓ How is a community's "need" conveyed to the player? (Quest-like? Gesture? Trade offer?)

### 5. Technology Progression — Discovery-Gated ✅

Technology unlocks when you bring the right **material** back + have the knowledge to use it.
Logic must feel real. Invention is a consequence of encounter, not a menu choice.

| Material | Found on... | Unlocks |
|---|---|---|
| Lodestone | Volcanic islands | Compass (navigation) |
| Dense hardwood | Jungle islands | Larger hull / ship tier 2 |
| Iron ore | Rocky/mountain islands | Metal tools, anchors, fittings |
| Flax / cotton | Temperate islands | Better sails → faster speed |
| Spices / preserved food | Tropical islands | Longer voyages (crew fed further) |
| Clay / stone | Most islands | Colony buildings |
| Copper | Deep volcanic | Cannons — late game, optional path |
| ❓ More to be invented as biomes are designed |

- New materials → new **buildings** to process them (workshops, labs, forges)
- Buildings enable further production chains
- Each invention changes what's *possible* — not just what's unlocked on a menu
- Knowledge is shared freely across peoples — it's not hoarded, it spreads
- *(And yes, eventually: space. But let's get the ocean right first.)*

### 6. Crew ✅

- Named crew members — not anonymous numbers
- **Crew can die** — voyages have real stakes (expand rules later)
- **New crew sources:**
  - The 10 scattered crewmates — found at capsule sites, some injured (see `storyline.md`)
  - Possibly, much later, inhabitants met along the way — ❓ depends on the inhabitants reveal
- **Crew level up on their own** through experience (voyages, discoveries, tasks)
- Skills build naturally — a sailor who navigates a lot gets better at navigation
- **Roles scale with ship size:**
  - Tier 1 boat: Captain (player) + 1–2 crew
  - Larger ships: dedicated Navigator, Cook, Carpenter, Bosun, Surgeon (late)
- As crew grows, tasks get **delegated** — captain focuses on decisions, not every rope
- **Cook/Chef unlocks** on larger ships — directly affects morale and voyage range
- ❓ Captain Sawyer: does the player character have personal progression too?
- **Could trade for boats** on discovered islands — other peoples may have built differently ✅

### 7. Resources & Trade ✅

- **Barter-based — no currency** ✅
  (One island would laugh at your colorful paper. Knowledge and materials rule.)
- Trade = exchanging things that are scarce to one and plentiful to another
- **Knowledge itself is tradeable** — share an invention with a people, earn deep trust
- Shared innovation lifts all peoples together — that's the philosophy
- **Trade routes** form between connected islands — automated once established
  (A ship runs the route, must be built up and maintained)
- **Colony founding:** uninhabited or consenting islands
  - Need crew to staff, materials to build
  - Produces resources over time, joins the trade network
- ❓ Can trade routes be disrupted? (Storms, mishaps — probably yes, not by war)

#### Voyage Resources (implemented) ✅

| Resource | Starting amount | Max | Drain rate |
|---|---|---|---|
| Food | 20 | 20 | 1 unit / crew / in-game day |
| Water | 20 | 20 | 1 unit / crew / in-game day |

- Dinghy starts with 2 crew → 2 units/day → 10-day range → ~300 real minutes before empty (30-min days)
- Drain is real-time and continuous (not turn-based); paced to feel slow, not anxious
- **Morale** is computed (not stored): `min(food_pct, water_pct)` — wires into crew behaviour later
- Replenishment: fishing, foraging, island resources — TBD mechanics
- `VoyageResources` autoload owns food/water/crew_count; `WorldClock` autoload owns time_of_day

### 8. Time ✅

- **Real-time, accelerated** — like most "real-time" strategy/exploration games ✅
- **Day length: 30 real minutes** ✅ — `WorldClock.DAY_LENGTH_SECONDS = 1800.0` (tunable constant; the only copy — VoyageResources reads it)
  - Was 15 min; 30 chosen 2026-09-28 — suits multi-day voyages without night coming too often
  - Future feature: time-scale multiplier (slow/normal/fast) — architecture is ready for it
- **Night:** different content — different fish, nocturnal animals, changed mood
- Food is a genuine resource — crew needs to eat, drives fishing/foraging/farming
- **Navigation harder at night** without a compass (stars help, but only if you know them)
- **Seasons:** probably not at launch — islands have enough variety to stand in for seasonal differences
  (A polar island feels like winter; a tropical one feels like summer)
- Weather systems (storms, calm seas, favorable winds) — ❓ TBD scope

### 9. Ship Progression ✅

| Tier | Name | Crew | Cargo | Max Speed | Turn Speed | Reverse | Unlocked by |
|---|---|---|---|---|---|---|---|
| 1 | Dinghy | 1–3 | Tiny | 7 | 2.5 | 2.0 | Starting vessel |
| 2 | Sloop | 5–8 | Small | 10 | 2.0 | 3.0 | Hardwood + iron |
| 3 | Brigantine | 10–15 | Medium | 13 | 1.5 | 3.5 | More materials + knowledge |
| 4 | Galleon | 30+ | Large | 11 | 0.8 | 2.0 | Late game, community effort |

Speed notes:
- Brigantine is the fastest — two masts, built for ocean crossings
- Galleon trades top speed for cargo and crew capacity; very slow to turn
- Reverse always slower than forward — no ship reverses well under sail
- When wind is added: all speeds become wind-modified (later feature)

- Each tier visually distinct — wake, bow waves, silhouette all change
- **Multiple ships** — as you establish settlements, run automated trade routes ✅
- Ships can be found/traded-for on discovered islands (different designs!) ✅
- ❓ Fleet management: how much control does the player have over other ships?
- ❓ Can non-player ships be lost? (Probably yes — stakes matter)

**Ship models** (Claude Design, `assets/models/ships/`): all four tiers exist as low-poly GLBs,
each with sails set and sails furled. Each tier is a `resources/ships/<tier>.tres` (stats from the
table above + model + `hull_length`). In-game hull lengths (first guess ❓): dinghy 2.6,
sloop 5, brigantine 8, galleon 11 units — at true scale the galleon would be ~36. Collision,
wake and bow spray fit themselves to the hull. Pick the ship with `Boat.ship`; Tab cycles
ships while testing. Sail colour is a setting (`BoatVisual.sail_color`), not baked
into the models — dyed sails could be a cosmetic / faction marker later.

**Sails (interim rule):** set the moment the boat gets under way; furl after ~5 s sitting still
(`Boat.furl_after_seconds`). ❓ Long-term this probably becomes player control — e.g.
**set/furl sails, drop anchor, dock/beach** — which ties into resting, landing parties and
night stops. Everything goes through one switch (`BoatVisual.set_sails()`), so changing the
rule never touches the model code.

---

## Scale ✅

Current world: 1000×1000 units (starting zone), home island + 6–10 islands of radius 30–220,
spaced so coastlines never overlap. Seeded: `IslandSpawner.world_seed` reproduces a world exactly.

**Target feel:** Global. The ocean should feel vast and consequential.
- World size: 2000×2000 minimum, possibly larger
- Islands: dozens, from tiny resource rocks to large inhabited landmasses
- Island size: current procedural islands are tiny — inhabited ones need room for settlements + terrain variety
- **Chunk loading** likely needed at full scale — defer until we hit performance walls
- Fog of war already designed to scale — ✅

---

## What's Already Built ✅

| System | Status | Notes |
|---|---|---|
| Ocean + water shader | ✅ | Depth-based shallows + shore foam that follows real coastlines |
| Boat movement | ✅ | Tier 1 vessel; touch steering (single finger), keyboard for desktop |
| Wake + bow wave particles | ✅ | Will update per ship tier |
| Isometric camera | ✅ | Follows boat's physics-interpolated position (no jitter) |
| Fog of war | ✅ | World-space via depth buffer; minimap shares its texture |
| Island generation | ✅ | Fractal coastlines, biome zones, rivers, atoll lagoons, threaded build |
| Island biomes + resources | ✅ | 6 zone types, type-driven resources, resource icons in toast |
| Discovery system | ✅ | Needs: peoples / inhabitant hints |
| Minimap | ✅ | Needs: island type icons, settlement markers, trade routes |
| Day/night + seasons | ✅ | WorldClock + world_lighting.gd |
| HUD | 🔧 | Arc, Food/Water, cargo slots (empty). Needs: crew panel, voyage log |

---

## Platform ✅

- **Primary:** Android mobile (Pixel device)
- **Secondary:** Desktop (PC) — don't rule out
- **Publishing:** Google Play Store (Android primary); itch.io likely for desktop (low barrier, indie-friendly); Steam possible later ($100 fee, more setup)
- Godot 4 exports to both natively — mobile renderer already in use ✅ (great early call)

**Implications for design & build:**

| Area | Impact |
|---|---|
| Controls | Arrow keys won't work — needs touch input. Virtual joystick? Tap-to-move? Swipe-to-steer? ❓ |
| UI | All touch targets need to be finger-sized (min ~48dp). HUD redesign must account for this. |
| Screen ratio | Pixel phones are typically 20:9. Isometric layout needs to feel good on tall narrow screens. |
| Performance | Mobile GPU budget is real. Keep draw calls low. Particle counts conservative. |
| Camera zoom | Pinch-to-zoom likely replaces scroll wheel |
| Saves | Mobile expects auto-save / background save — no "save before quit" |

**Control scheme: Swipe-to-steer ✅** — press and drag, boat follows finger.

Two implementation options (decide before coding):
- **A — Floating joystick:** drag direction + distance from touch origin = heading + speed. No world-space projection needed.
- **B — World follow:** touch projects onto world XZ plane; boat turns toward and sails to that world point, updates as finger moves. No UI overlay. Feels like guiding the boat through the water. ← *recommended*

Both keep keyboard controls active for desktop testing.
Pinch-to-zoom replaces scroll wheel. ✅

---

## Open Questions ❓

- ~~Touch control scheme~~ ✅ Option B (world-follow) implemented in boat.gd
- **Captain Sawyer's personal progression?** Separate from crew?
- **Fleet management depth** — how much control over automated trade ships?
- **Can non-player ships be lost?**
- **How is a community's "need" communicated to the player?**
- **Night navigation without compass** — stars as mechanic?
- **Exact roguelite carry-over rules** — what persists through death?
- **Other sections still assume native peoples from the start** (Islands types, Trade, Diplomacy) —
  revisit against the stranded-crew premise: when/how do inhabitants enter the story?
- **Weather/storms** — scope and timing?
- **Home island threat?** Can it ever be at risk?
- **Sail / anchor / dock controls** — does the player set and furl sails, drop anchor, beach the
  boat? (Interim: sails auto-furl after ~5 s at rest — see §9.)
- **Ship tier sizes in the world** — the models are true-scale metres (dinghy 4 m → galleon 34 m);
  how big should each tier look next to islands?

---

## Build Priority (Current Thinking)

1. ~~Ship visual~~ ✅
2. ~~Map scaling~~ ✅
3. ~~Day/night cycle~~ ✅
4. ~~Island biomes + resources~~ ✅ (natural coastlines pass: 2026-09-28)
5. **Save system** — needed before progression systems are worth building 🎯
   (world = `world_seed`; also persist fog texture, discovered islands, clock, resources)
6. **Resource system** — inventory, gathering, basics
7. **Crew data model** — named crew, roles, needs, leveling
8. **HUD redesign** — resources, crew, time of day, voyage info
9. **Technology tree** — material → invention unlocks, buildings
10. **Trade + diplomacy** — island peoples, exchange, knowledge-sharing
11. **Trade routes** — automated ships, settlement network
12. **Colony system** — settle, produce, supply chain

---

*Last updated: 2026-09-28*
*This document is the design source of truth. Consult before building any major new system.*
*Philosophy: knowledge and compassion are the currency. Diverse peoples thrive when connected.*
