--[[
    metaldetector - configuration (shared by client and server).

    Nothing in here is secret, so the file is loaded on both sides: the client
    needs the models, ranges and texts, the server needs the spots and loot.
]]--

Config = {}

-- ─── Item / activation ───────────────────────────────────────────────────────

-- Standalone the detector is taken out with a command. If you wire an
-- inventory up in integration.lua, set UseCommand = false and trigger the
-- server event "metaldetector:toggle" from your item instead.
Config.UseCommand = true
Config.Command    = "detector"

-- Require the player to actually own an item before the detector can be taken
-- out. Only works when Integration.countItem() in integration.lua is wired to
-- a real inventory - with the standalone default it would block everyone.
Config.RequireItem = false
Config.ItemName    = "metal_detector"   -- item key passed to the integration

-- ACL right needed for the attachment editor (/mdattach, /mdedit).
Config.AdminRight = "command.kick"

-- ─── Digging ─────────────────────────────────────────────────────────────────

Config.DigRange    = 3.0                  -- max distance from the spot when digging
Config.RespawnTime = (1000 * 60) * 120    -- how long until a dug spot comes back (2 h)
Config.DigDuration = 5000                 -- length of the digging animation (ms)

-- Key used to dig (works without a cursor). If a cursor happens to be showing,
-- the on-screen dig icon can be clicked instead.
Config.DigKey = "e"

-- ─── Spots ───────────────────────────────────────────────────────────────────

-- Places where the detector finds something. hasTreasure = false → the player
-- digs an empty hole.
-- Keep spots a few metres apart, otherwise the detector flickers between them.
Config.DigSpots = {
    -- Las Venturas - near the airport
    {346.33, 1925.26, 17.64, hasTreasure = true},
    {345.10, 1923.14, 17.64, hasTreasure = true},
    {347.10, 1927.14, 17.64, hasTreasure = true},

    -- Los Santos - Rodeo beach
    {472.86, -1544.69, 10.27, hasTreasure = true},
    {463.68, -1591.25, 12.95, hasTreasure = true},
}

-- ─── Loot ────────────────────────────────────────────────────────────────────

-- Chance (%) that a spot yields cash instead of an item, and the range.
Config.CashChance = 18
Config.CashMin    = 150
Config.CashMax    = 900

-- Loot tiers. One tier is picked at random, then one entry from it by weight
-- (the higher the weight, the more common the find).
--   item   = key handed to Integration.giveItem() (your inventory item name)
--   label  = what the player is told they found
--   value  = fallback payout when no inventory is connected (see integration.lua)
--   weight = relative chance inside the tier
Config.Loot = {
    { -- common scrap
        { item = "car_scrap",   label = "Scrap metal",   value = 20,  weight = 300 },
        { item = "car_iron",    label = "Rusty iron",    value = 25,  weight = 250 },
        { item = "car_copper",  label = "Copper wire",   value = 40,  weight = 200 },
        { item = "screwdriver", label = "Screwdriver",   value = 30,  weight = 120 },
        { item = "lighter",     label = "Lighter",       value = 10,  weight = 100 },
    },
    { -- tools and odds and ends
        { item = "battery",     label = "Car battery",   value = 60,  weight = 250 },
        { item = "toolbox",     label = "Toolbox",       value = 120, weight = 150 },
        { item = "binoculars",  label = "Binoculars",    value = 90,  weight = 120 },
        { item = "wallet",      label = "Old wallet",    value = 70,  weight = 200 },
        { item = "cigarette",   label = "Pack of cigarettes", value = 15, weight = 200 },
    },
    { -- valuables
        { item = "watch",       label = "Wristwatch",    value = 250,  weight = 100 },
        { item = "gold_chain",  label = "Gold chain",    value = 400,  weight = 80 },
        { item = "goldbar",     label = "Gold bar",      value = 1500, weight = 25 },
        { item = "crucifix",    label = "Silver crucifix", value = 300, weight = 60 },
        { item = "lockpick",    label = "Lockpick",      value = 150,  weight = 90 },
    },
}

-- ─── Models ──────────────────────────────────────────────────────────────────

Config.DetectorModel = 3697   -- replaced by files/detector.wardis + detector.txd
Config.FindModel     = 3694   -- replaced by files/turas1.wardis + turas1.txd
Config.SpotModel     = 2969   -- invisible marker object placed at every spot
Config.HoleModel     = 3694   -- the hole left behind after digging

-- ─── Detector in hand ────────────────────────────────────────────────────────

-- Where the detector sits in the player's hand. Bone 23 = right elbow; the
-- client also forces bones 22/23/24 every frame so the arm holds the detector
-- in front of the body.
-- Tune it in-game with /mdedit or /mdattach, then write the result back here.
Config.Attach = {
    bone = 23,
    pos  = { 0.061, -0.098, 0.537 },
    rot  = { 180, 0, -158 },
}

-- ─── Signal / HUD ────────────────────────────────────────────────────────────

Config.SignalRange = 3.0     -- from this distance the signal bar starts to show
Config.BeepRange   = 4.5     -- from this distance the detector starts beeping
Config.DigIconRange = 2.0    -- how close you must be for the dig prompt
Config.SoundEnabled = true

-- ─── Texts ───────────────────────────────────────────────────────────────────

Config.Texts = {
    noItem        = "You don't have a metal detector.",
    inVehicle     = "You can't use it inside a vehicle.",
    takenOut      = "You took out the metal detector.",
    putAway       = "You put the metal detector away.",
    emptyHole     = "The hole is empty, nothing here.",
    foundCash     = "You dug up $%d.",
    foundItem     = "You dug up: %s",
    inventoryFull = "The find didn't fit in your inventory.",
    battery       = "Battery OK",
    noSignal      = "No signal",
    signal        = "Signal %d/8",
    digHint       = "Press %s to dig",
}
