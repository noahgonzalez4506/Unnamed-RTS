# Starship Kit — ships, soldiers and weapons for an FPS/RTS hybrid

Everything made so far for your space FPS/RTS game, organized so you can start building in Godot:
- boardable warships and boardable stations;
- two robotic factions with role uniforms, their weapons and their physical inventory;
- the economy, the star map and the pirates.

## What's in here

| Folder | What it is |
|---|---|
| **`godot_demo/`** | **Start here.** A ready-to-run Godot project: walk your ships and a station, open doors, breach, sabotage, fly fighters. See `godot_demo/README.md`. |
| `tools/export_glb.py` | Writes game-ready `.glb` files (with collision and markers) for every ship and station without Blender, straight into the test project. |
| `blender/ship_generator.py` | **Source of truth for ships and stations.** Builds every ship, craft, station, outpost and ground base in Blender. Change settings, re-run, re-export. |
| `blender/character_generator.py` | **Source of truth for people and gear.** Builds both factions' robot soldiers and crew (15 roles each), their weapons and inventory items. |
| `economy/economy_data.py` | **Source of truth for the economy.** Resources, fuel, Cores, recipes, every station module (power, output, states, repair costs), ship and robot costs, mining, ground bases, infection rules. Run it to write `data/economy.json`. |
| `economy/galaxy_generator.py` | Builds the mirrored star map (systems, jump lanes, resource anchors, jump points). Run it to write `data/galaxy.json`. |
| `models_obj/ships`, `stations`, `characters`, `weapons`, `items` | Everything already exported as `.obj`, so you can look at it in Godot without installing Blender. Characters come one file per faction and role (`char_F1_medic.obj` and so on). |
| `data/ship_stats.json` | Ship numbers: crew, troops, capacities, default loadouts, bunks, escape seats, compartments. |
| `data/economy.json`, `data/galaxy.json` | Economy rules and the star map, ready for Godot to load. |
| `data/weapons_and_armor.json` | Combat numbers: faction damage and armor multipliers, weapon stats, armor damage reduction, every role's uniform, weapons and starting inventory. |
| `godot/ship_helpers.gd`, `godot/character_helpers.gd` | Small Godot 4 scripts: breach, doors, shields and elevators on ships; station doors, module status lights and sabotage points; dress a character as a role, put items in sockets and calculate damage. |
| `tools/check_ships.py`, `tools/check_stations.py`, `tools/check_characters.py` | Run after changing a generator; each ends with "passed" if nothing broke. The station check also walks every station from its command module to every control room, ready locker and sabotage point. |
| `tools/simulate_economy.py` | Plays a scripted competent player for the first 120 minutes so you can see the pace your numbers produce. |
| `previews/` | Pictures of everything, including `stations_preview.png`, `station_plan.png`, `roles_F1.png`, `weapons_sheet.png` and `galaxy_map.png`. |

## The ships

| Class | Model | Size | Boarded by |
|---|---|---|---|
| XS | Fighter, Bomber, Boarding dropship (12 soldiers), Boarding pod (8), ODST-style drop pod (1), Darter cargo/crew ferry (6 or cargo), Mining ship + mining drones | 2–15 m | — (they carry the boarders) |
| SMALL | Frigate, Supply ship, Paris-inspired Drop frigate | 86–118 m, 1 deck | Airlocks (dropship dock or EVA), cargo-bay Darter |
| MEDIUM | Warship | 110 m, 1 deck | Pods via breach zones, hangar, cargo bay |
| LARGE | Warship | 154 m, 2 decks | Same |
| XL | Warship | 210 m, 3 decks | Same |

Every SMALL to XL ship has:
- **Compartments:** sealable compartments with blast doors, plus a zone box per compartment and deck for infection spread and evac.
- **Breaching:** breachable walls and locked doors that take explosive charges.
- **Supplies:** armories, ready lockers in every compartment, and medbays with medpen resupply.
- **Evac:** escape-pod bays on every deck.
- **Cargo bay:** a boardable cargo bay that fits Darters (S 1, M 2, L 3, XL 4).
- **Launchers:** boarding-pod launchers (S 3 per side, M 5, L 7, XL a 12-silo dorsal battery).
- **Interiors:** fully furnished rooms.

## The factions

| | Faction 1: heavy (ODST-like) | Faction 2: sleek (BO3-like) |
|---|---|---|
| Body | Bulky robot, 1.98 m | Slim robot, 1.88 m |
| Armor | High damage reduction (rifleman 50%) | Low damage reduction (rifleman 27.5%) |
| Weapons | Ballistic, Halo/Marathon style, magazines | Energy, Covenant/BO3/Infinite style, power cells; hit 1.3× harder |
| Colors | Olive armor, gold visor, amber lights | Graphite armor, red lights |

Damage taken = weapon damage × attacker's damage multiplier × (1 − target's damage reduction). Total damage reduction is capped at 60%. For example, a faction 2 plasma rifle hits a faction 1 rifleman for 13, and a faction 1 assault rifle hits a faction 2 rifleman for 14.5.

**Roles and uniforms:** each faction has the same 14 roles, and every role wears its own uniform.
- Combat roles in armor: rifleman, breacher, medic, heavy, grenadier, squad leader, EVA boarder, and drop trooper (in dark armor).
- Ship crew in department coveralls with no combat gear: pilot (flight suit), bridge officer (coat and cap), engineer (orange coverall, tool belt), cargo handler (yellow coverall, hi-vis harness), medical officer (white coat, medpens), scientist (teal hazmat suit, purge-emitter pack) and security (vest, SMG).
- Crew gear up at the ships' armories and ready lockers.

**Weapon classes**, one model per faction for each:

| Class | Faction 1 | Faction 2 |
|---|---|---|
| Rifle | Assault rifle | Plasma rifle |
| Battle rifle | Battle rifle | Pulse carbine |
| SMG | SMG | Energy SMG |
| Shotgun | Shotgun | Scatter gun |
| Sniper | Sniper | Beam rifle |
| Pistol | Magnum | Plasma pistol |
| Heavy | LMG | Arc cannon |

**Physical inventory:** sockets on the body hold the real items:
- Magazines or power cells: 4 chest slots and 2 belt slots.
- Grenades: 4.
- Medpens: 4.
- One slot each for a revive kit, a tool, a holster and a back weapon.
- 2 breaching charges.
- Hand grips.

Godot imports the sockets as attachments that follow the bones. A weapon's magazine or cell is a separate object, and the same model is the inventory item, so a reload can visibly pull one from your chest.

**Animation:** the skeleton uses Godot's humanoid bone names, so standard humanoid animations (such as Mixamo) can be retargeted onto both factions in Godot's import settings. Rest pose is a T-pose, and characters face +Z in Godot.

## The strategic layer: star systems, economy and stations

The game is real time. Every rate in `economy_data.py` is per minute and every time is in seconds.

**Star systems:** `galaxy.json` holds 12 star systems joined by 17 jump lanes of 2 to 3.5 light years (`previews/galaxy_map.png`), sized for games of about 2 hours.
- The map is mirrored, so both home systems have the same resources at the same distances.
- The contested middle column holds the prizes: ancient sites, rich lithium, crystals and derelict warships.
- Each system is one 7 km battle arena, with a jump point at its edge for each lane, pointing toward the neighbor.
- Only the system the player is in runs in full. The rest tick along in a light simulation.

**Fuel:** ships burn **hydrogen** flying inside a system and **tritium** to jump.
- Range on a full tank: SMALL about 3 jumps; MEDIUM, LARGE and XL about 2.
- A jump spools for 20 seconds, during which the ship is vulnerable, then takes 15 seconds per light year in transit.
- Mining ships carry a small jump drive of their own.

**Resources:**

| Raw | Refined into | Used for |
|---|---|---|
| Ore | Alloys | Hulls, armor, robot bodies, modules |
| Crystals | Circuitry | Electronics, weapons, Cores |
| Ice, Gas | Hydrogen | Sublight fuel |
| Lithium | Tritium | Jump fuel |

- **Cores** are the population: every robot crew member and soldier needs one.
  - A destroyed robot drops its core where it fell. Its own side can retrieve it for as long as it lies there (no timer): walk over it, use a revive kit on the body, or tow it.
  - If the infection reaches the core first, it is converted and lost for good.
  - Enemies can't use your cores, but they can deny them by holding the ground.
- Each system has one shared stockpile. Moving resources between systems takes a supply ship physically jumping with the cargo.

**Mining:**
- Static **mining rigs** and **gas skimmers** are built at fields and gas giants.
- **Mining ships** (`XS_MINER`, `previews/mining_preview.png`) cut with a laser and send out 4 **mining drones**, then dock at a docking ring to unload through a belly chute. They mine faster than rigs but need escorts, which makes them prime raid targets.

**Power limits what a station can do:**
- A station's grid carries at most 400 power (command core), 100 (ground core) or 80 (outpost core), however many reactors it has.
- Heavy industry is power hungry: refinery 60, core foundry 70, medium shipyard 80, large shipyard 130.
- The home station has 215 power left for industry after essentials and defenses, so it can't run everything at once. You choose what runs, or build more stations elsewhere.
- Modules that can't get power go Offline.

**Station modules:** command core, outpost core, reactor, mining rig, gas skimmer, refinery, breeder reactor, fabricator, core foundry, assembly plant, three shipyard sizes, storage and fuel depots, docking ring, barracks, defense platform, shield generator and comm relay.

Every module is a boardable building (`previews/station_plan.png`):
- **Control room:** has the console that switches the module on and off; capturing it captures the module.
- **Crew room** with a ready locker, so defenders can gear up.
- **Machine hall** with the module's own machinery (reactor core, refinery vats, assembly lines, bunks, racks, pumps).
- **Sabotage points:** junction boxes on the hall walls, 1 to 5 per module, each with a spot for an engineer and one for a charge.
- **Ways in:** two side airlocks for EVA boarders and a connector door at each end.
- **Outside:** a roof status light and the module's exterior features (turrets, radiator fins, tanks, berths, drill booms, shipyard build bays).

Stations are assembled along a spine: the command module, then hubs, with a module on each side of every hub, joined by walkable tubes. The kits that are built as complete models are:

| Kit | Modules |
|---|---|
| `STATION_HOME` | The 19-module starting station |
| `STATION_INDUSTRIAL` | Command core, 2 reactors, refinery, medium shipyard, core foundry, docking ring |
| `STATION_FORTRESS`, `STATION_FUEL_HUB` | Defensive and refueling stations |
| `OUTPOST_MINING`, `OUTPOST_SKIMMER` | Outpost core plus a mining rig or gas skimmer |
| `GROUND_MINE`, `GROUND_FORT` | Ground core plus a drill, or batteries and landing pads, dug into an asteroid |

Set `BUILD_SINGLE_MODULES = True` to also get every module on its own (`MODULE_refinery` and so on) for building your own layouts in Godot.

- Every module can be in one of these states:

| State | Cause | Fix |
|---|---|---|
| Online | Normal | — |
| Offline | Switched off, by owner or boarders holding the control room, or power short | Reboot, 15 s |
| Sabotaged | Charges or hacking | Engineers |
| Disabled | Heavy damage | Engineers plus materials |
| Destroyed | Hull gone | Rebuild at 80%; the wreck is salvageable |
| Infected | The infection | **Only scientists with purge emitters can clear it.** Then engineers repair whatever damage is underneath. |

**Ground bases:** large asteroids (5 on the current map) host small dug-in installations: a ground core, surface drills, ground gun batteries and landing pads. Their small power grid (100) forces them to specialize in defense or mining. Take them with troops: drop pods, dropships or Darters on the landing pads.

**Controlling systems:** you control a system only once you own a station core in it (command, outpost or ground core) **and** no armed pirate or enemy installation there is still online.
- In other systems you can fly, fight, mine with mining ships and salvage, but you can't build, share the stockpile or refuel.
- A supply ship can drop a core while pirates are still there. The system stays contested until their guns are destroyed, captured or switched off.

**Pirates** are hostile to everyone and defend any system they hold.
- Their strength depends on the system's resources and its distance from the homes: light near the homes (a couple of fighters) and heavy in the rich middle (frigates, a Medium, a salvaged flagship).
- The local resources decide what they can do:
  - ore: they rebuild lost ships;
  - crystals: shielded installations;
  - lithium: raiders that hit nearby outposts;
  - a large asteroid: a ground fort;
  - an ancient site: fanatics, with the infection nearby.
- They slow you down but never block you. Taking their installations by boarding keeps them intact.

**The infection** spreads compartment by compartment (2 minutes each) and across hulls.
- It converts unretrieved cores, and only scientists with purge emitters can clear it.
- Each converted robot hands over its memory of the last 20 minutes: what it saw, where and when. It gets no live tracking.
- Retrieving your cores and changing your patrols after losses keeps its picture of you stale.

**Pace (from `tools/simulate_economy.py`, a competent player expanding normally):**
- **Opening:** mining ships and a crystals outpost, then an industrial station at minute 22.
- **First Medium** at minute 36.
- **From minute 40:** about one Medium every 5 minutes, sustained to minute 120 from two medium shipyards.

A 12-system game should wrap up in about 2 hours.

## Quick start

**1. Install the tools** (both free):
- Godot 4 (the standard version is fine): https://godotengine.org/download
- Blender 4: https://www.blender.org/download

**2. Play the test level.**
1. In Godot's Project Manager, click **Import** and pick `godot_demo/project.godot`.
2. Let it import, then press **F5**.

Controls are on screen and in `godot_demo/README.md`. To view a single model, drag it from `models_obj/` or `godot_demo/models/` into Godot's FileSystem panel and double-click it.

**3. Generate in Blender (when you want to edit models by hand).** You don't need Blender to play: `tools/export_glb.py` already makes `.glb` files with collision and markers. Use Blender when you want to tweak or paint models.
1. Open Blender, go to the **Scripting** tab and click **Open**, then choose `blender/ship_generator.py`.
2. Click **Run Script**. All 14 ship classes and 8 stations appear side by side.
3. Save the `.blend` file inside your Godot project folder.
4. In the script, set `EXPORT_GLB = True` and run it again. You get one `ship_<CLASS>.glb` per ship and station next to your `.blend`, and Godot picks them up automatically.

**4. Characters, weapons and items** work the same way. Open `blender/character_generator.py`, run it, set `EXPORT_GLB = True`, save, and run again. That gives `character_F1.glb` (the whole wardrobe), one file per role, and a `weapon_*.glb` and `item_*.glb` for each weapon and item. `ROLE_PREVIEW` picks which uniform shows in Blender.

**5. Use the helpers in Godot.** Drag a `.glb` into a scene and attach `godot/ship_helpers.gd` to it:

```gdscript
$Ship_LARGE.breach("*BreachPanel_1*")              # a boarding pod hit
$Ship_LARGE.set_shields("*HangarShield*", false)    # shields down, hangar open
$Ship_LARGE.slide("*BlastDoor_C2_C3_D0*", Vector3(-1.65, 0, 0))   # seal a compartment
var spawn = $Ship_LARGE.marker("*PlayerSpawn_Deck0*")

$STATION_HOME.set_door("*M05REF_Connector_Back_Door*", true)   # open a station door
$STATION_HOME.show_module_state("M05REF", "sabotaged")         # roof light turns orange
for p in $STATION_HOME.sabotage_points("M05REF"):              # where engineers go
    print(p.global_position)
```

## Changing things

All settings are at the top of `ship_generator.py`:

| To change... | Edit |
|---|---|
| Which ships get built | `SHIP_CLASSES` |
| Faction colors (1 = grey-green with amber lights, 2 = graphite with red) | `FACTION` |
| A different random layout of rooms, armor and breach spots | `SEED` |
| Ship sizes, decks, turrets, tubes, cargo pads | `CLASSES` |
| Crew numbers per size | `STANDARD_CREW` |
| A specific ship's crew, troops, fighters, bombers, dropships, pods and Darters | `LOADOUTS` |

The script checks custom loadouts against hangar slots, tubes and cargo pads, and reports problems in `ship_stats.json`.

After any change, run `python tools/check_ships.py` and `python tools/check_stations.py` from the kit folder. They should end with "All checks passed" and "All station checks passed".

Station settings sit next to the ship ones: `BUILD_STATIONS`, `BUILD_SINGLE_MODULES`, `MODULE_SPECS` (each module's size and sabotage points) and `STATION_KITS` (which modules each station is made of). Keep them in step with `economy_data.py`; the station check tells you if they drift apart.

## Naming conventions (what Godot sees)

- **`...-col`**: Godot adds collision automatically on import (walls, floors, doors, hatches).
- **Removable on breach:** `BreachPanel_n`, `BreachWall_n`, `BreachDoor_n`, `PodTube_*_Hatch`, `DropTube_n_Hatch`, `PodSilo_n_Hatch`, `Airlock_n_OuterDoor`.
- **Moving parts:**
  - `BlastDoor_*` and `Door_*` are modeled open; slide them X −1.65 m to close.
  - `ElevatorDoor_*` slide Y +1.85 m in Blender, which is −Z in Godot.
  - `Airlock_n_OuterDoor` is closed; `Airlock_n_InnerDoor` is open.
  - `CargoBayDoor` is closed; hide or slide it to open.
  - The dropship and Darter `Ramp` rotate around their hinge.
  - `Turret_n` pivot at their base.
- **Shields:** `HangarShield_*` and `CargoBayShield` are visual only; add your own collision.
- **Markers:** empty nodes (Node3D) marking positions:
  - Spawns: `PlayerSpawn_Deck*`.
  - Seats, exits and stations: `Seat_n`, `PilotSeat`, `Bridge_PilotSeat`, `Bridge_CaptainChair`, `Reactor`, `Evac_Hangar`.
  - Boarding: `BreachZone_n_*`, `Airlock_n_DropshipDock`, `Airlock_n_EVAEntry`, `*_Muster`.
  - Explosives: `*_ChargeA` / `_ChargeB`.
  - Cargo: `CargoBay_DarterPad_n_*`, `CargoStorage_n`.
  - Getting around: `Ramp_*`, `Elevator_n_Stop_Deck*`.
  - Supplies: `ReadyLocker_*`, `Armory_n_Resupply`, `Medbay_n_MedpenResupply`.
- **Stations:** every object starts with its module code, such as `M05REF` (module 5, refinery) or `H02` (hub 2).
  - `Connector_Back/Front_Door` and `AirlockPort/AirlockStbd_Door` are modeled closed. Open them with `set_door()`.
  - Markers: `ControlRoom`, `ControlConsole`, `CrewRoom`, `ReadyLocker`, `SabotagePoint_n` (plus `_ChargeA`), `AirlockPort_EVAEntry`, `Core`, `BuildBay`, `DarterPad_n`, `MinerBerth_n`, `Garrison`, `Operations`, `SurfaceLanding`.
  - `Zone_M05REF` covers the whole module, for infection and alarms.
- **Zones:** `Zone_Cx_Dk` are boxes (their scale is the half-size) covering compartment x on deck k. Turn them into Area3Ds for infection spread, alarms and evac.

Units are meters. Deck height is 4 m, and ramps are about 30°, which Godot's CharacterBody3D can walk up by default.

## Numbers that are placeholders (decide these)

- Every economy number: rates, costs, power draws, start stock, fuel tanks, Core rules.
- Galaxy size, how often each kind of anchor appears, and pirate strength (top of `galaxy_generator.py`, and `PIRATES` in `economy_data.py`).
- Faction combat multipliers: sleek faction damage ×1.3, armor ×0.55.
- Armor damage reduction per piece (chest 22%, helmet 10%, and so on).
- All weapon stats and item stats (in `character_generator.py`).

- Standard crew per size: SMALL 15, MEDIUM 30, LARGE 60, XL 100.
- Default troops fill every carried craft. For example, a SMALL frigate with 6 pods carries 48 troops.
- XL cargo bay holds 4 Darters (you set S 1, M 2, L 3).
- The drop frigate carries 12 drop pods.
- Hangar slots (M 4, L 6, XL 8) with fighter = 1 slot, bomber = 2, dropship = 2.
- Bunks and escape-pod seats are deliberately below full crew, so evacuations force choices.

## Honest limits

- The `.obj` files have no collision or markers. Use the Blender `.glb` export for real gameplay.
- I couldn't run Blender or Godot while building this. The geometry was tested in plain Python (see the `tools/check_*.py` scripts), and the Blender and Godot code follow their standard APIs, but expect a small fix or two the first time you run them.
- Everything is grey-box quality, meant for gameplay first and nicer art later. The two factions' armor silhouettes are a first pass, and the sleek faction could be pushed further.
