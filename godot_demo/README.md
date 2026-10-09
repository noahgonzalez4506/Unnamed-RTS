# Starship Kit: demo match

This is a playable skirmish in one star system. Command your fleet from above, or play as a soldier on the ground. You can:

- fly your warships;
- board enemy ships in pods or shuttles and fight room by room through their doors;
- drop into any of your soldiers or crew at any time.

## Run it

1. **Install Godot 4.5 or newer.** Use the standard edition (not .NET) from https://godotengine.org/download. It's a single program with no installer: unzip it and run it.
2. **Unzip `starship_demo.zip`** anywhere you like.
3. **Import the project.** Open Godot. In the Project Manager, click **Import**, browse to the unzipped `godot_demo` folder, select `project.godot`, then click **Import & Edit**.
4. **Wait for the first import.** It takes about a minute while Godot processes the 3D models. Errors in the Output panel during this import are harmless.
5. **Press F5** (or the ▶ button at the top right) to play. You start at the main menu.

**Making your own .exe.** The project already includes Windows and Linux export presets.
1. Godot needs its export templates first, once per Godot version. Go to **Editor → Manage Export Templates → Download and Install**. It's about 1.3 GB, and the version must match your editor exactly.
2. Go to **Project → Export**, select **Windows Desktop**, and click **Export Project**. Turn off **Export With Debug** for a release build.
3. Pick a folder **outside** the project folder, for example your Desktop.

If the Export button is greyed out or shows red text, the templates are missing or are for a different Godot version. Do step 1 again from the same Godot you are using.

## Main menu

- **CAMPAIGN**: see below.
- **SKIRMISH VS AI**: pick your side (Vanguard or Ascendancy), whether to start as **Commander** or **Soldier**, and the rival AI's difficulty.
  - As a soldier, an AI commander runs your side and you fight on the ground.
- **MULTIPLAYER**:
  - One player clicks **HOST**. The other players type the host's IP address and click **JOIN**.
  - Everyone picks a side and a role in the lobby, then the host clicks **START MATCH**.
  - The game uses port **24680** (UDP). To play over the internet, forward that port on the host's router.
- **SETTINGS**: mouse sensitivity, field of view, fullscreen, the frame-rate counter and V-Sync.

## Campaign (single player)

**Main menu → CAMPAIGN → NEW CAMPAIGN** (name your company), or **CONTINUE** a save.

You run your own company. It flies Vanguard ships and kit, but it isn't the Vanguard.

**Your start:** a small frigate, two mining craft and a starter station (reactor, refinery, fabricator, docking ring), in Vanguard space at the west edge of the galaxy.

**The galaxy:** six systems joined by jump lanes, each with 1–3 planets scaled to fit the system.
- **Planet types:** barren, ice, desert, volcanic, jungle, ocean, gas giant and **infected**.
- **Vanguard space (west):** Vanguard Navy stations and patrols, plus **Union Merchant Guild** trade stations.
- **Ascendancy space (east):** Ascendancy patrols and fortresses, plus **Concord Free Traders**.
- **Free space (middle):** mining claims and pirate dens.
- **The infected world:** it sends up spore pods and **hive ships** at anyone who comes close. Derelicts drift nearby.

**Mining:** your miners cut ore from the nearest asteroid field and bring it home. The refinery turns ore into alloys. Miners run from raiders.

**Standing:** every side has a standing with you.
- Pirates and the infection are always hostile.
- Everyone else starts neutral or friendly. They turn hostile if your standing drops below -25.
- Shooting their ships lowers it. **Ctrl + right-click** on a neutral ship deliberately opens fire.
- Finishing jobs and killing pirates raises it.
- The Navy and the Ascendancy are at war with each other.

| Key | What it does |
|---|---|
| **O** | Galaxy map: who holds what, planets, stations and your jobs. Pick a neighbouring system and press **JUMP**: your selected ships (or the whole fleet here) fly to the gate and go through. |
| **P** | Station services, at the station nearest your selected ship (within 900 m). **Trade**: eight goods, cheap where they're made and dear where they're needed. **Jobs**: deliveries, bounties, salvage and pirate clearance. **Services**: repairs, resupply, hiring boarders; at your own station, move cargo into the stores. |
| **Menu bar** (top left) | SHIPS · UNITS (I) · STATION (G) · RESEARCH (Y) · MAP (O) · SERVICES (P). A command card with buttons for the selected units appears along the bottom. |
| **Dropship** | (the old drop frigate) No boarding pods: 16 ODST drop pods for surface bases, and two crewed belly 120 mm guns that lob shells at surface bases in range. The shells land in a wide circle, so you can't aim precisely. **NAPALM ON/OFF** on the command card: burning rounds that hit the infected two to three times as hard. |
| **Tritium** | Every jump burns it (10 per small ship, 25 medium, 50 large, 90 XL). Reactors make it from fuel; mining claims and Navy stations sell it. |
| **I / G** | Build menus at your station in this system. **Ships**: frigate, supply ship, drop frigate, and (with shipyard segments) medium and large. **Craft & troops**: mining craft, boarding squads. **Station segments**: refinery, reactor, barracks, shipyard, storage, defense gun, CIWS, habitat. Pick one and click beside the station: segments snap to a 36 m grid next to the station or another segment (hold Shift to place several). |
| **Soldiers → another ship** | Select soldiers, then right-click a friendly ship or station: they fly over in a Darter (soldiers into its troop berths). Right-click an enemy ship: they muster at the pod bay or hangar and board it. |
| **F5** | Save (the game also autosaves every 3 minutes and on every jump) |

Ships you capture join your fleet.

## The match

Every match is a new, procedurally generated star system. The seed sets the system's name, where the home stations, pirates and derelict sit, 2–4 asteroid fields (ships slow down inside them), the sun, sky and planet, and which interior layout each warship gets.

| Side | What they have | Hull design |
|---|---|---|
| **Vanguard (F1)** | The *Vanguard Bastion* fortress station, the Large warship *UNV Resolute* and the frigate *UNV Lance* | Naval: slab hull, hammerhead bow, command tower, white bands |
| **Ascendancy (F2)** | *Ascendancy Spire*, *ASC Verdict* and *ASC Shard* | Sleek: needle blade bow, spine and fins, swept wings, twin nacelles, crimson trim |
| **Pirates** | *Pirate Haven* (an asteroid fort), a frigate and sometimes a Medium raider that boards weakened ships. Hostile to everyone. | Scrap: rust, an off-center tower, welded-on containers, a ram, mismatched engines |
| **The infection** | The derelict *Calypso*. It fires spore pods, converts the dead and learns what they saw. | Wreck: plating blown off, tower sheared, overgrown |

## Ship interiors

Each warship has three procedurally generated layouts; the match picks one. The ramps, the elevator, the breach rooms and the room plan all move. Rooms:

- **Armories:** racks, armor stands and ammo crates. This is the only place to gear up or resupply (E at the rack or the counter), and it draws on the ship's supplies.
- **Troop berthing:** 12 bunks per section, sometimes a two-section hall. The berths cap how many boarders a ship carries.
- **Crew quarters:** two-berth cabins.
- **Other rooms:** mess hall with galley, medbay, workshop, storeroom, comms, systems and escape-pod bays.
- **Off-shift crew** go to the mess and their cabins.

## Logistics

- **Stations:** they make new robots (the station's *reserve*) and supplies, paid for in alloys and cores.
- **Ships use them up:**
  - Every pod or shuttle takes boarders from the berths.
  - Armories spend supplies on gear-ups and reloads, and engineers spend them on repairs.
  - Dead crew leave posts empty.
- **Getting them back:**
  - A ship within 800 m of its home station is topped up directly.
  - A ship out in the field that runs low gets a supply shuttle with replacement crew, boarders and 80 supplies. Enemy point defense can shoot it down.
  - Press **U** with ships selected to send them home to resupply.
- **Fleet list:** each of your ships shows boarders / berths and its supplies %.

**Win** by capturing or destroying the enemy station's command core. You **lose** if they do that to yours.

## Commander (RTS view)

| Input | What it does |
|---|---|
| WASD, middle-drag, wheel, Q/E | Pan, rotate, zoom, turn |
| Left click / drag | Select (double-click selects everyone of that role nearby) |
| Right click | Move or attack. Ships fly or attack; soldiers move along their deck. |
| X, Up/Down arrows | Cutaway interior view, and which deck to show |
| B | Order a boarding op. Anyone on that ship gets **30 s** to reach the pod bay before launch. |
| L | Scramble fighters |
| T | Train a squad at a station barracks |
| Y | Research |
| H, K | Selected soldiers hold; sabotage the nearest enemy module |
| U | Selected ships go home and resupply |
| Tab | Take direct control of the selected soldier or crew member |
| J | Deploy yourself as a soldier, in any class, at any friendly ship or station |
| 1–4, F1 | Jump to your ships or station; help |

## On foot (first person)

| Input | What it does |
|---|---|
| WASD, mouse, Shift, C | Move, look, sprint, crouch (crouch while sprinting to slide) |
| Space | Jump. Press it again in the air for an exo boost jump. |
| V | Exo dash |
| Left / right mouse | Fire / aim down sights |
| R, G, Q | Reload, grenade (Shift+G: EMP), revive pen (on yourself) |
| B | Grenadier: rifle → 40 mm launcher → breaching round → rifle (skips any that are empty) |
| E | Use: revive (pen or the medic's revive gun), drag a downed friend / lay them on a medbay bed, elevator, ready locker or armory, sabotage, take the helm, launch a fighter, **join a boarding party** at the pod bay or hangar, **kick in a door** or **set a breaching charge** |
| 1–9, 0 | When you lead a squad: **1** follow, **2** hold, **3** move or stack on the door you're aiming at, **4** breach & clear that room, **5** suppress the aim point, **6** regroup on me, **7** formation (wedge / file / line), **8** fireteam B to the aim point (again to rejoin), **9** weapons free / tight, **0** frag out at the aim point |
| T | Requisition reinforcements (300 alloys + 4 cores, 90 s cooldown). On a friendly vessel a squad of six comes up to you. Aboard the enemy, a friendly ship fires a pod in near you. |
| Tab | Back to command (not in soldier mode) |

**Squad Leader** class: you deploy with a fireteam of five AI soldiers who move in formation and use bounding overwatch under fire.

## At a ship's helm

Walk to the bridge pilot seat and press **E**.

| Input | What it does |
|---|---|
| W/S, A/D, mouse | Throttle, turn, aim the turrets |
| Left mouse | Fire every turret that can bear |
| T | Lock the target you're aiming at (red brackets). Press T again to clear the lock. |
| M | Missile salvo at the locked target (the racks restock slowly) |
| B / N | Boarding op on the locked target: pods / shuttle (30 s muster) |
| 1 / 2 / 3 / 4 | Fleet orders: attack my lock / form on me / hold / board my lock |
| L | Scramble fighters |
| E | Leave the helm |

**Fighters:** press E at a parked fighter in the hangar to launch. Mouse steers, A/D rolls, W/S sets throttle, Shift boosts, left mouse fires the guns. Press E within 450 m of your carrier to land.

## Esc menu
- **Esc** (with nothing else open) pauses the game.
- The menu has resume, settings and save (campaign), then back to the main menu or quit. Both of those save the campaign first.
- Settings: mouse sensitivity, field of view, volume, graphics (low/medium/high), fog of war, fullscreen, v-sync and frame-rate display.

## Fog of war and radar (F7 toggles)
- You see what your ships, stations, fighters, craft, troops, vehicles and outposts can see.
  - Ship sensors: small 2.4 km, medium 3 km, large 3.8 km. Stations: 4.2 km.
  - On a world: ships 700 m, troops 110 m, vehicles 260 m, outposts 380 m.
- Radar (twice sensor range, ships and stations only) shows contacts as grey "?" blips on the minimap and **UNKNOWN CONTACT** markers.
- Beyond radar, nothing shows. Stations and ground bases stay on the map once found.

## Station core ship
- Build a **Station core ship** (SHIPS menu: 1400 alloys, 300 circuitry).
- Fly it out and press **DEPLOY STATION** (needs 1.4 km clear of other stations and away from planets). It becomes a new station of yours.

## Boarding: charges, wrecked rooms, retreat
- On an enemy ship, **E** at its medbay or armory sets a demolition charge (10 s). The charge blinks and beeps.
- Defenders defuse it with **E**, or any crewman standing on it for 3 s.
- A wrecked medbay heals nobody and a wrecked armory rearms nobody, until engineers repair it.
- AI breachers set charges too.
- Ships carry 2 fewer boarding pods.
- A losing boarding party falls back: once there are 3 or fewer boarders and defenders outnumber them 2 to 1, the boarders run for their breach points and get out to their nearest ship.

## Abandon ship
- At 200 hull the crew are ordered to the escape pods (the pod bay muster points, or the hangar).
- At 0 hull a ship doesn't blow up at once: the reactor goes critical and she has **30 seconds**.
- The escape pods launch **7 seconds before** she blows, with whoever reached them. Anyone still aboard dies with the ship.
- Soldiers who escape join the nearest friendly ship's berths.
- If the infection is overrunning a ship (1.5× as many infected as crew, or only 2 crew left), the crew abandon her too. The pods go after 25 s; if nobody is left aboard, the ship is lost to the infection.
- **T** reinforcements and station squads now cost 1 core per soldier and show what you're short of.

## Outposts (N), crew (C), vehicles
- **OUTPOST (N)** on a world lists the landing zone and every base location there.
  - **FOUND OUTPOST** at an open or cleared one: a command post costs 600 alloys and 150 circuitry.
  - Then place structures within 150 m of the post. R rotates the ghost, Shift keeps placing.
- Structures:
  - **Barracks**: trains 4 troops every 90 s (40 alloys + 4 cores each time, up to 24 troops).
  - **Supply depot**: rearms troops, refills med pens and repairs vehicles.
  - **Gun emplacement**: a heavy gun that fires on its own.
  - **Sandbag wall**: cover.
  - **Ore extractor**: +1.2 ore/s.
  - **Motor pool**: fast vehicle repair.
- Outposts stay on the world. Lose the command post and the outpost falls.
- **CREW (C)** lists who is aboard each ship here. **+** hires a specialist (150 cr): engineer, scientist, medic, medical officer, security, pilot or cargo handler. **−** sends one ashore. The crew you set stays with the ship.
- **Vehicles:**
  - New vehicles park in your station's vehicle depot.
  - In orbit, select a supply ship or dropship within 2.5 km of the station and press **LOAD VEHICLES** (or **UNLOAD VEHICLES**).
  - On a world, select vehicles and right-click a landed supply ship or dropship: they drive up the ramp and load.
  - Only supply ships (12) and dropships (8) carry vehicles.

## Zones (Z)
- **ZONES (Z)** lists every system and landing zone where you have ships, stations, troops or vehicles. Click one to go there and command it.
- Troops and vehicles you leave on a world stay where they are, so you can come back to them. Everywhere else waits as you left it.

## Ground installations and ODST
- **Outlaw camps** are built straight onto the terrain:
  - A ring of containers, sandbags and scrap barricades, with three gates covered by gun nests.
  - Watchtowers, tents, fuel tanks and a stripped wreck in the yard.
  - A two-storey command house with firing windows. That house is the core: destroy it and the camp falls (+600 cr, +250 alloys).
- **Infected hives** are built the same way:
  - Ground stained with creep and glowing veins, and low fleshy ridges to take cover behind.
  - **Spore towers** poison anything within 75 m. **Egg clusters** hatch infected while enemies are near.
  - The **hive heart** under its cage of ribs is the core.
- How each side attacks them:
  - Tanks, IFVs, artillery and ship guns all hit these structures. Small arms barely scratch them.
  - Right-click one with ships to engage it.
  - With infantry selected, a right-click on one sends them to walk there.
- **ODST DROP**: right-click the ground with a dropship selected. It flies over the spot and fires its pods straight down. The troopers form up where they land.

## The infection and the outlaws
- **Hives** have a domed warren you can fight inside, with three openings. The dome peels away in the cutaway (X).
  - The hive heart sits in the middle. Brood sacs on the walls birth replacement infected whenever the swarm is thin.
  - The swarm walks the hive's perimeter.
  - Every few minutes the hive sends an attack wave (8–16) at the nearest outlaw camp, colony, outpost, or your landing zone.
- **Gravemind:** a hive builds up biomass over time. If its world has an abandoned city and the biomass gets high enough, a GRAVEMIND grows in the city.
  - It lashes out at anything close.
  - Every few minutes it births an infected spreader ship.
  - Spreaders travel the jump lanes and can seed new hives on other worlds. Meet one in space and you can kill it.
- **Outlaw camps** run 1–3 MRAP convoys depending on how lawless the region is. Each convoy has a walking escort of 8.
  - One convoy patrols around the camp; the rest roam the zone.
  - The convoys wait for their escort to catch up.

## Driving vehicles (on a world)
- **E** beside one of your vehicles, or select it and press **Tab** (or DRIVE on the command card).
- **W/S** drive, **A/D** steer, **Shift** boost. The mouse swings the camera and the turret follows it.
- **LMB** fires the main gun, **RMB** the second weapon. **E** gets out; **Tab** goes back to command.

## Ground cargo (supply ship, landed)
- **UNLOAD CARGO** puts 6 crates down the front ramp (150 alloys), making a forward depot.
  - Munitions crates rearm troops nearby; medical crates refill med pens; the alloys crate patches up vehicles.
  - The crates are cover, and they stay on that world.
- Salvage in cities is *secured* when your troops or vehicles reach it.
- **LOAD CARGO** hauls up the front ramp the depot crates within 160 m and secured salvage within 650 m.
- A landed dropship's security detail walks a perimeter about 110 m out.

## Wounds and the medbay

- **Going down:** a soldier who takes a fatal hit usually goes down rather than dying, and bleeds out in about 25 seconds.
- **Revive pens:** every combat soldier carries **4**, and medics carry **8**. A pen revives a downed friend in 3 seconds (E when you stand over them). The AI keeps its last pen for a friend rather than using it on itself.
- **Revive gun:** medics also carry one, with **8 shots** and a range of **14 m**. Aim at a downed friend and press E. AI medics use it from cover in the middle of a firefight.
- **The medbay:** when nobody nearby has a pen, a friend **drags or carries** the downed to the nearest free medbay bed. Bleeding slows while they're moved and stops on the bed. Treatment there takes 4 seconds, returns them at full health and costs the ship 3 supplies. You can do the same: E on a downed friend with no pens to drag them, then E beside a bed.
- **Restocking:** armories and resupply top pens back up to 4 (8 for medics) and reload the revive gun.

## Doors and boarding

- **Doors:**
  - **Room doors** open for their own crew. Boarders **kick them in** (about 3 kicks), shoot them down, frag them or blow them.
  - **Blast doors** between compartments can't be kicked. Shoot them down or use a breaching charge.
  - **Security doors** (bridge, hangar, cargo bay, reactor, armory, comms) open only to a **breaching charge**. They have a yellow-and-black frame. Once a charge is set, stand clear for 3 seconds.
- **Boarding:**
  - Pods and shuttles carry anyone who joined at the bay, plus troops to fill the remaining seats. You ride along in a chase camera and come out fighting.
  - Boarding craft put the target on **red alert**: the lights pulse red, the crew arms up, and you get a red screen edge while aboard.
  - Point defense can shoot pods, shuttles and missiles down, along with anyone riding in them.

## Good to know

- **Performance:** aim for 60 fps on a mid-range PC. With 150+ characters fighting, physics is the main cost. The frame counter is in the top bar.
- **Balance:** this is a first pass. Ship numbers are at the top of `scripts/ship.gd`, door strength is in `scripts/vessel.gd` (`DOOR_HP`), and weapons are in `data/weapons_and_armor.json`.

## Automatic checks (optional)

Run these from this folder with the Godot command line:

```
godot --headless --path . --fixed-fps 30 res://match.tscn -- --selftest   # fast-forwarded battle report
godot --headless --path . res://match.tscn -- --opstest                   # boarding ops, missiles, shuttle, squad, requisition
godot --headless --path . res://match.tscn -- --breachtest                # pods fly nose-first; boarders don't clump
godot --headless --path . res://match.tscn -- --squadtest                 # every squad command
godot --headless --path . res://match.tscn -- --logtest                   # supply runs, docking, empty armories
godot --headless --path . res://match.tscn -- --camptest                  # campaign: miners, trade, jobs, map, jump, save/load
godot --headless --path . res://match.tscn -- --medtest                   # pens, revive gun, carrying the downed to a medbay bed
godot --headless --path . res://match.tscn -- --odsttest                  # drop frigate pods land on surface bases only
GODOT=godot sh tests/run_net_test.sh                                      # host + client multiplayer check
```
