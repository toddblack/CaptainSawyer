# Captain Sawyer — Game Design Document

> Living document. Update as decisions are made. Mark open questions with ❓ and resolved ones with ✅.

---

## Vision

An Age of Exploration game about a small crew who built a boat big enough to leave their island.
Exploration-first, survival-informed, empire-building through **trade, diplomacy, and shared innovation**.

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
Start on home island (established, boat already built)
    → Sail out into unknown ocean (fog of war)
        → Discover island
            → Encounter: uninhabited / friendly peoples / wary peoples / resource-rich
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

### 1. Home Island ✅

- The player starts on a **well-established home island** — not primitive, but island-bound
- The community has already learned enough to build a seaworthy boat
- Home island is the anchor: save point, return destination, first settlement
- Feels lived-in from the start — buildings, community, history
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
  - Home port (community members willing to go)
  - Island peoples met along the way — someone always wants to see the world
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

### 8. Time ✅

- **Real-time, accelerated** — like most "real-time" strategy/exploration games ✅
- ❓ Exact day length in real minutes (TBD — probably 10–20 min/day to start, tunable)
- **Night:** different content — different fish, nocturnal animals, changed mood
- Food is a genuine resource — crew needs to eat, drives fishing/foraging/farming
- **Navigation harder at night** without a compass (stars help, but only if you know them)
- **Seasons:** probably not at launch — islands have enough variety to stand in for seasonal differences
  (A polar island feels like winter; a tropical one feels like summer)
- Weather systems (storms, calm seas, favorable winds) — ❓ TBD scope

### 9. Ship Progression ✅

| Tier | Name | Crew | Cargo | Unlocked by |
|---|---|---|---|---|
| 1 | Dinghy/Sloop | 1–3 | Tiny | Starting vessel (already built) |
| 2 | Coastal Trader | 5–8 | Small | Dense hardwood + iron fittings |
| 3 | Brigantine | 10–15 | Medium | More materials + knowledge |
| 4 | Galleon | 30+ | Large | Late game, full community effort |

- Each tier visually distinct — wake, bow waves, silhouette all change
- **Multiple ships** — as you establish settlements, run automated trade routes ✅
- Ships can be found/traded-for on discovered islands (different designs!) ✅
- ❓ Fleet management: how much control does the player have over other ships?
- ❓ Can non-player ships be lost? (Probably yes — stakes matter)

---

## Scale ✅

Current world: 200×200 units, 5–7 islands. Prototype scale only.

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
| Ocean + water shader | ✅ | Scales fine |
| Boat movement | ✅ | Tier 1 vessel |
| Wake + bow wave particles | ✅ | Will update per ship tier |
| Isometric camera | ✅ | Zoom range may need expanding |
| Fog of war | ✅ | Core mechanic — perfect |
| Island generation | ✅ | Needs: larger size, biome types, resource assignment |
| Discovery system | ✅ | Needs: island data (type, resources, peoples) |
| Minimap | ✅ | Needs: island type icons, settlement markers, trade routes |
| HUD | 🔧 | Current: minimap only. Needs full redesign for resources/crew/time |

---

## Open Questions ❓

- **Captain Sawyer's personal progression?** Separate from crew?
- **Fleet management depth** — how much control over automated trade ships?
- **Can non-player ships be lost?**
- **How is a community's "need" communicated to the player?**
- **Night navigation without compass** — stars as mechanic?
- **Exact roguelite carry-over rules** — what persists through death?
- **In-game day length** in real minutes?
- **Weather/storms** — scope and timing?
- **Home island threat?** Can it ever be at risk?

---

## Build Priority (Current Thinking)

1. **Ship visual** — give tier-1 boat real shape. Immediate, visible, sets the tone. 🎯
2. **Map scaling** — expand world, more islands, set the stage for everything else
3. **Day/night cycle** — sky, sun arc, lighting. Foundational visually and mechanically.
4. **Island biomes + resources** — variety on generation, resource assignment
5. **Save system** — needed before progression systems are worth building
6. **Resource system** — inventory, gathering, basics
7. **Crew data model** — named crew, roles, needs, leveling
8. **HUD redesign** — resources, crew, time of day, voyage info
9. **Technology tree** — material → invention unlocks, buildings
10. **Trade + diplomacy** — island peoples, exchange, knowledge-sharing
11. **Trade routes** — automated ships, settlement network
12. **Colony system** — settle, produce, supply chain

---

*Last updated: 2026-02-20*
*This document is the design source of truth. Consult before building any major new system.*
*Philosophy: knowledge and compassion are the currency. Diverse peoples thrive when connected.*
