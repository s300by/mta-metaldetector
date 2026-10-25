# metaldetector

Treasure hunting for **MTA:SA**. The player takes out a metal detector, sweeps
it over the ground, and a HUD shows the signal strength while the detector beeps
faster the closer a buried find is. Dig the spot up, pick the find out of the
hole, and the spot respawns a couple of hours later.

Standalone resource: no inventory, database, notification or bone-attach
resource is required. If you *do* have those, there is one small file to plug
them into — see [Integration](#integration).

## Features

- Signal HUD with zone name, battery and an 8-step signal bar
- Beep rate that scales with the distance to the find
- Custom detector model held in the player's hand, visible to everyone nearby
- Two-stage digging: dig the hole, then pick up what is inside
- Server-side loot rolls (the client can't fish the loot table out or fake a find)
- Weighted loot tiers plus a chance of cash
- Spots respawn on a timer; a visible hole is left behind in the meantime
- In-game editor for the hand attachment (`/mdedit`)

## Installation

1. Copy the `metaldetector` folder into your server's `resources/` directory.
2. `start metaldetector`
3. In-game: `/detector` takes the detector out, `/detector` again puts it away.
4. Walk to one of the spots in `Config.DigSpots` (the defaults are near the
   Las Venturas airport and on Rodeo beach in Los Santos) and press **E** when
   the dig icon appears.

## Controls

| Input | Action |
|---|---|
| `/detector` | take the detector out / put it away |
| **E** | dig, and after the hole is open, pick the find up |
| Mouse | sweep the detector — the arm follows the camera |

While the detector is out, firing, jumping, sprinting and entering vehicles are
blocked. Putting it away (or dying) restores everything.

## Configuration

Everything is in `config.lua`:

| Group | Settings |
|---|---|
| Activation | `UseCommand`, `Command`, `RequireItem`, `ItemName`, `AdminRight` |
| Digging | `DigRange`, `DigDuration`, `RespawnTime`, `DigKey` |
| Spots | `DigSpots` — `{x, y, z, hasTreasure = true/false}` |
| Loot | `CashChance`, `CashMin`, `CashMax`, `Loot` (weighted tiers) |
| Models | `DetectorModel`, `FindModel`, `SpotModel`, `HoleModel` |
| Hand | `Attach` — bone, position and rotation offset |
| HUD | `SignalRange`, `BeepRange`, `DigIconRange`, `SoundEnabled` |
| Texts | `Texts` — every string the player ever sees |

### Adding spots

```lua
Config.DigSpots = {
    {346.33, 1925.26, 17.64, hasTreasure = true},
    {120.50,  -10.25,  3.11, hasTreasure = false},   -- always an empty hole
}
```

Keep spots a few metres apart. Two spots close together make the detector
flicker between them, because it always locks onto the nearest one.

### Loot

A tier is picked at random, then one entry from that tier by weight:

```lua
{ item = "goldbar", label = "Gold bar", value = 1500, weight = 25 },
```

- `item` — the key handed to your inventory
- `label` — what the player is told they found
- `value` — the payout used when no inventory is connected
- `weight` — relative chance within the tier (higher = more common)

## Integration

`integration.lua` is the only file you need to edit to connect the resource to
your own systems. Four functions, all with working standalone defaults:

| Function | Default behaviour |
|---|---|
| `Integration.countItem(plr, item)` | returns 1 — everyone "owns" a detector |
| `Integration.giveItem(plr, item, entry)` | returns false → the find is paid out as `entry.value` in cash |
| `Integration.giveCash(plr, amount)` | `givePlayerMoney` |
| `Integration.notify(plr, text, ok)` | chatbox + the built-in popup from `notify.lua` |

Example with an inventory resource:

```lua
function Integration.countItem(plr, item)
    return tonumber(exports["my-inventory"]:countPlayerItem(plr, item)) or 0
end

function Integration.giveItem(plr, item, entry)
    return exports["my-inventory"]:addPlayerItem(plr, item) ~= false
end
```

Then set `Config.RequireItem = true` so the detector can only be taken out by a
player who actually owns one, set `Config.UseCommand = false`, and trigger the
server event from your item's use handler:

```lua
triggerServerEvent("metaldetector:toggle", plr)
```

## Admin

`/mdedit` and `/mdattach` adjust how the detector sits in the player's hand.
Both require the ACL right in `Config.AdminRight` (`command.kick` by default) —
the client asks the server for the permission, so a normal player cannot use
them even by triggering the command manually.

`/mdedit` opens an interactive editor (arrows move, Q/E/R/F/U/J rotate, mouse
wheel switches bone, Enter confirms). It prints the final numbers into the
chat; copy them into `Config.Attach` to make them permanent.

## How it works

The server creates one invisible marker object per spot and tags it with element
data (`md:spot`, `md:available`, `md:treasure`). The client only looks at
streamed-in objects of this resource, picks the nearest available one and draws
the signal from the distance to it.

Digging is two-staged. Stage one runs entirely on the client: the animation
plays, a mound of dirt grows, and when it finishes the client asks the server to
place the permanent hole so everyone sees it. Stage two is the pick-up: the
client sends nothing but "I dug at this spot", and the server verifies the
player holds a detector, is within `DigRange` and that the spot is still
untouched — then claims the spot and rolls the loot. **No loot table ever
reaches the client**, which is the main difference from the original version of
this script where the roll happened client-side and any item could be requested
by triggering one event.

`boneattach.lua` is a ~70-line replacement for the pAttach resource: it reads
the bone's world position every frame and applies the configured offset in the
ped's local space. That is accurate here because the client locks the right arm
into a fixed pose while the detector is out.

## Files

```
metaldetector/
├─ meta.xml
├─ config.lua        -- all settings, spots, loot tables, texts
├─ integration.lua   -- server: inventory / money / notification hooks
├─ server.lua        -- spots, dig validation, loot rolls, respawn
├─ notify.lua        -- client: built-in notification popup
├─ boneattach.lua    -- client: minimal bone attachment (replaces pAttach)
├─ client.lua        -- client: HUD, signal, beeping, digging, arm pose
├─ placement.lua     -- client: /mdedit attachment editor
└─ files/            -- models, textures, sounds, font
```

## Credits and assets

The script is based on a metal detector resource by **DoBijs**; the version here
has been rewritten (server-side loot, standalone integration layer, no external
dependencies).

The binary assets in `files/` — `detector.wardis`, `turas1.wardis`, the `.txd`
textures, `pda.ttf` and the `.mp3` sounds — come from that original release and
are **not covered by this repository's license**. The `.wardis` files are
TEA-encrypted DFF models that `client.lua` decrypts at load time. If you plan to
publish or redistribute this resource, check that you are allowed to ship those
files, or replace them with your own models, textures, font and sounds; the code
works with any `DetectorModel`/`FindModel` you point it at.

`files/` also still contains leftovers from the original package that this
version never loads (`shader.fx`, `mta-helper.fx`, `tex/`, `serverFiles/`,
`turas.*`, `bg2.png`, `hole_texture.png`). They are not listed in `meta.xml`, so
clients never download them, and they can be deleted.
