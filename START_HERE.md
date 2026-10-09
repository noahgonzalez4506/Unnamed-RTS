# Starship Kit: start here

## What's in this zip
- `godot_demo/`: the game (a Godot 4.5.1 project). Open `godot_demo/project.godot` in Godot 4.5.1.
- `blender/`, `tools/`, `models_obj/`, `data/`, `economy/`, `godot/`: the asset generators and source data the game's models were built from.
- `HANDOFF_LATEST.md`: where development stopped, what's left, and how each remaining feature should be designed.
- `README.md`: the kit overview. `godot_demo/README.md` covers the game's controls and features.

## Run it
1. Install Godot 4.5.1 (standard build, not .NET).
2. Open `godot_demo/project.godot` and press F5. The first import takes a few minutes.
3. Windows build: Project → Export → "Windows Desktop". Export templates must be installed.

## Keep developing with Claude
Start a new session, attach or point it at this folder, and say:
"Read HANDOFF_LATEST.md and continue from 'Start here' and 'Still to do'. Compile-check with
`godot --headless --path godot_demo res://tests/compile.tscn` (expects COMPILE DONE and exit code 0), then export a Windows build."
