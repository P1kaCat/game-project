# Isometric RPG — character & graphics prototype

Graphical foundation for an isometric pixel-art RPG (PC + mobile, multiplayer
later). This milestone contains **only** the isometric test ground and the
first playable character — no combat, inventory, quests or networking yet.

![Gameplay](docs/images/gameplay.gif)

Every sprite and tile here was generated with the real **PixelLab API v2**
(see [PixelLab pipeline](#pixellab-pipeline)). Nothing is a placeholder.

## Run it

Requires **Godot 4.7** (GL Compatibility renderer, so it also runs on mobile/web).

```sh
godot --path .            # opens the movement test scene (scenes/main.tscn)
```

| Action | Keys |
|---|---|
| Move (8 directions) | **WASD** on QWERTY = **ZQSD** on AZERTY (physical key positions), arrow keys, left stick |
| Run | **Shift** / gamepad A |

Idle, walk and run animations switch automatically, and the character faces
whichever direction it moves.

### Automated check

```sh
xvfb-run godot --path . --rendering-driver opengl3 -- --autotest [--shots=/abs/dir] [--frames]
```

This holds real input actions for each of the 8 directions, plus run and idle.
For each step it checks the playing animation, the ground speed (diagonals
normalised), screen direction (diagonals follow the 2:1 tile edges), and that
the player stays on the map. It prints `SUMMARY PASS` and exits with code 0
when everything passes.

## Specifications

| | |
|---|---|
| Projection | true 2:1 isometric, diamond cells **64 × 32 px** |
| Tile texture | 64 × 64 px: the top face is an exact 64 × 32 diamond centred at (32, 38), with ~10 px of earth side below |
| Character body | **31 × 47 px** (south view), 8 directions |
| Animation frame canvas | **68 × 68 px** for every frame of every animation, so nothing shifts |
| Foot pivot | **(34, 57)** in frame pixels, placed on the ground position (tile centre) |
| Rendering | 480 × 270 viewport, integer upscaling, nearest-neighbour filtering, 2D transforms snapped to pixels |

**Movement model.** Input and velocity live in an undistorted "ground" plane.
`Iso.ground_to_screen()` halves the vertical component (the 2:1 camera). This
keeps diagonal speed normalised in ground space, and moving diagonally
travels exactly along the tile edges, slope (2, 1). Speeds (walk 50 px/s,
run 90 px/s) were calibrated against the stride measured in the generated
frames, so the feet don't slide.

| Animation | Frames / direction | Frame duration | Engine |
|---|---|---|---|
| idle | 4 | 200 ms | PixelLab `pixminimax`, custom breathing action |
| walk | 8 | 100 ms | PixelLab `v3`, template action `walking` |
| run  | 8 | 75 ms  | PixelLab `v3`, template action `running` |

![Rotations](docs/images/player_rotations_preview.png)
![Walk](docs/images/player_walk_preview.png)

## Asset layout

```
assets/
  characters/player/
    rotations/<dir>.png                 base 8-direction sprites (padded to 68x68)
    idle/<dir>/frame_NN.png             4 frames
    walk/<dir>/frame_NN.png             8 frames
    run/<dir>/frame_NN.png              8 frames
    spritesheets/player_{idle,walk,run,rotations}.png
    player_animations.json              metadata (read by the game)
  tiles/terrain/
    grass.png grass_flowers.png dirt.png cobblestone.png
    terrain_atlas.png  terrain.json
```

`<dir>` is one of `n ne e se s sw w nw`. Sprite-sheet **rows follow that order**
(N, NE, E, SE, S, SW, W, NW), columns are frames left to right, with no
spacing or padding. `player_animations.json` describes the frame size, pivot,
direction order and, per animation, its sheet, frame count, frame duration and
loop flag. `DirectionalSprite` builds its `SpriteFrames` from this file, so
adding an animation is just a sheet plus a JSON entry.

## Code structure

```
scenes/main.tscn            test world (terrain + y-sorted entities + player)
scenes/player.tscn          CharacterBody2D + DirectionalSprite + Camera2D
scripts/core/iso.gd         2:1 projection helpers, tile size
scripts/core/direction8.gd  vector <-> 8-direction codes
scripts/player/player.gd    input, movement, idle/walk/run selection, stay-on-ground
scripts/player/directional_sprite.gd   metadata-driven 8-dir AnimatedSprite2D
scripts/world/iso_terrain.gd           TileMapLayer + TileSet from the PixelLab atlas
scripts/world/test_world.gd            builds the 16x16 test map, spawns the player
scripts/debug/autotest.gd              scripted verification / screenshots
```

## PixelLab pipeline

`tools/pixellab/pixellab_client.py` is a dependency-free client. It uses only
documented endpoints from <https://api.pixellab.ai/v2/openapi.json>.
Set `PIXELLAB_API_KEY` in your environment; the key is sent as a Bearer token
and never written anywhere. `tools/pixellab/state.json` records the character
id, animation group ids and requests, so references are reused and never
regenerated.

```sh
python3 tools/pixellab/pixellab_client.py balance
python3 tools/pixellab/pixellab_client.py create-character --size 48 --description "..."
python3 tools/pixellab/pixellab_client.py animate --key walk --mode v3 --template-action walking --wait
python3 tools/pixellab/pixellab_client.py zip --out /tmp/player.zip      # GET /characters/{id}/zip
python3 tools/pixellab/export_assets.py <unzipped dir> <tiles dir> .     # -> assets/
```

What was generated, and its cost (Tier 1 subscription generations):

| Step | Endpoint | Cost |
|---|---|---|
| Base character v1 (64 px canvas, rejected: figure ~62 px tall, too large) | `POST /create-character-v3` | 2 |
| **Base character v2**: south sprite + 8 v3 rotations, 48 px canvas | `POST /create-character-v3` | 2 |
| idle × 8 directions | `POST /characters/animations` (pixminimax) | 8 |
| walk south test (pixminimax, rejected: 4 px lateral drift) | `POST /characters/animations` | 1 |
| walk × 8 (v3 `walking`) | `POST /characters/animations` | 8 |
| run × 8 (v3 `running`) | `POST /characters/animations` | 8 |
| 4 terrain tiles (thin tile, 64 × 64) | `POST /create-isometric-tile` | 4 |
| **Total** | | **33** |

All directions were derived from one reference: `create-character-v3` draws a
single south-facing sprite and rotates it into the other 7 views, and each
animation starts from that character's own rotation for its direction. No
mirroring was needed.

### Known limitations

- Animation canvases are 68 × 68 because PixelLab enlarges the canvas for
  motion. The character itself keeps its 31 × 47 proportions; trim the canvas
  later if memory matters.
- The run cycle's foot baseline varies by ±2 px (airborne frames). That's
  intentional motion, not drift.
- Grass tiles have slight edge shading, so a faint grid stays visible on large
  grass areas. Good enough for a movement test; a proper Wang/terrain-transition
  set is future work.
