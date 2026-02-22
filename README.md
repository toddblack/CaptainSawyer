# Captain Sawyer

A retro-style 3D isometric seafaring adventure game where you explore islands, discover civilizations, and trade goods.

## Current Features (v0.1 - Basic Foundation)

- ✅ Isometric camera view
- ✅ Basic ocean environment (200x200 units)
- ✅ Simple boat with hull, mast, and sail
- ✅ Boat movement controls (arrow keys)

## Controls

- **Up Arrow** - Move forward
- **Down Arrow** - Move backward
- **Left Arrow** - Turn left
- **Right Arrow** - Turn right

## How to Run

1. Open Godot 4.x
2. Click "Import"
3. Navigate to this folder and select `project.godot`
4. Click "Import & Edit"
5. Press F5 to run the game

## Project Structure

```
CaptainSawyer/
├── scenes/
│   └── main.tscn          # Main game scene
├── scripts/
│   └── boat.gd            # Boat movement controller
├── assets/
│   ├── models/            # 3D models (future)
│   └── materials/         # Materials and textures (future)
├── project.godot          # Godot project file
└── README.md
```

## Next Steps

- [ ] Add multiple islands to discover
- [ ] Implement fog of war / discovery mechanic
- [ ] Add island collision detection
- [ ] Create civilization markers
- [ ] Build basic trading system
- [ ] Improve boat model and animations
- [ ] Add water shader with waves
- [ ] Implement camera following boat
- [ ] Add UI for resources and discovered locations

## Roadmap

### Phase 1: Core Navigation ✅
- Basic ocean and boat movement

### Phase 2: Exploration (In Progress)
- Island generation
- Discovery mechanics
- Minimap

### Phase 3: Civilization & Trading
- Settlement placement
- Resource system
- Trading interface

### Phase 4: Polish
- Improved graphics
- Sound effects and music
- Save/load system
