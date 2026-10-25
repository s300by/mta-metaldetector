--[[
    metaldetector - server side.

    The server owns everything that matters: which spots exist, whether a spot
    is still untouched, and what comes out of it. The client only ever sends an
    intent ("I dug here") - the loot roll happens here, so the loot table can't
    be fished out of or faked by a client.

    Everything that touches another system (inventory, money, notifications)
    goes through integration.lua.
]]--

local spotObjects = {}     -- [object] = true, the spots this resource created
local holes       = {}     -- [object] = hole object currently sitting on the spot

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function notify(plr, text, ok)
    if not isElement(plr) then return end
    local okCall = pcall(Integration.notify, plr, text, ok)
    if not okCall then
        outputChatBox("[Detector] " .. text, plr, 255, 255, 255)
    end
end

local function hasDetectorItem(plr)
    if not Config.RequireItem then return true end
    local ok, count = pcall(Integration.countItem, plr, Config.ItemName)
    return ok and (tonumber(count) or 0) > 0
end

local function isAdmin(plr)
    return isElement(plr) and hasObjectPermissionTo(plr, Config.AdminRight or "command.kick", false)
end

-- Make a spot findable again (also used after the respawn timer).
local function armSpot(obj, hasTreasure)
    if not isElement(obj) then return end
    setElementData(obj, "md:spot", true)
    setElementData(obj, "md:available", true)
    setElementData(obj, "md:digTick", 0)
    setElementData(obj, "md:digging", false)
    if hasTreasure ~= nil then
        setElementData(obj, "md:treasure", hasTreasure)
    end
    setElementAlpha(obj, 0)
end

local function isValidSpot(obj)
    return isElement(obj) and spotObjects[obj] == true
end

-- ─── Spot setup ──────────────────────────────────────────────────────────────

addEventHandler("onResourceStart", resourceRoot, function()
    for _, spot in ipairs(Config.DigSpots) do
        local obj = createObject(Config.SpotModel, spot[1], spot[2], spot[3] - 1.2)
        armSpot(obj, spot.hasTreasure and true or false)
        spotObjects[obj] = true
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    -- Clear the flag on anyone holding a detector so no stale element data is
    -- left behind on the players.
    for _, plr in ipairs(getElementsByType("player")) do
        if getElementData(plr, "md:inHand") then
            setElementData(plr, "md:inHand", false)
        end
    end
end)

-- ─── Taking the detector out / putting it away ───────────────────────────────

local function toggleDetector(plr)
    if not isElement(plr) or getElementType(plr) ~= "player" then return end

    if not hasDetectorItem(plr) then
        return notify(plr, Config.Texts.noItem, false)
    end

    if getPedOccupiedVehicle(plr) then
        return notify(plr, Config.Texts.inVehicle, false)
    end

    if getElementData(plr, "md:inHand") then
        setElementData(plr, "md:inHand", false)
        notify(plr, Config.Texts.putAway, true)
    else
        setElementData(plr, "md:inHand", true)
        notify(plr, Config.Texts.takenOut, true)
    end
end

-- Triggered by the command below, or by your inventory when the item is used.
addEvent("metaldetector:toggle", true)
addEventHandler("metaldetector:toggle", root, function()
    toggleDetector(client or source)
end)

if Config.UseCommand then
    addCommandHandler(Config.Command, function(plr)
        toggleDetector(plr)
    end)
end

-- Death or disconnect takes the detector out of the player's hand.
local function dropDetector()
    if isElement(source) and getElementData(source, "md:inHand") then
        setElementData(source, "md:inHand", false)
    end
end
addEventHandler("onPlayerWasted", root, dropDetector)
addEventHandler("onPlayerQuit", root, dropDetector)

-- ─── Loot ────────────────────────────────────────────────────────────────────

local function rollLoot()
    local tier = Config.Loot[math.random(1, #Config.Loot)]
    if type(tier) ~= "table" or #tier == 0 then return nil end

    local total = 0
    for _, entry in ipairs(tier) do total = total + (entry.weight or 0) end
    if total <= 0 then return nil end

    local roll, acc = math.random(total), 0
    for _, entry in ipairs(tier) do
        acc = acc + (entry.weight or 0)
        if roll <= acc then return entry end
    end
    return nil
end

local function payOut(plr, entry)
    -- First offer the find to the inventory. If nothing handles it (the
    -- standalone default), fall back to paying out its value so a dug-up find
    -- is never silently lost.
    local ok, added = pcall(Integration.giveItem, plr, entry.item, entry)
    if ok and added then
        return notify(plr, Config.Texts.foundItem:format(entry.label or entry.item), true)
    end

    local value = tonumber(entry.value) or 0
    if value > 0 then
        pcall(Integration.giveCash, plr, value)
        return notify(plr, Config.Texts.foundItem:format(
            (entry.label or entry.item) .. " ($" .. value .. ")"), true)
    end

    notify(plr, Config.Texts.inventoryFull, false)
end

addEvent("metaldetector:dig", true)
addEventHandler("metaldetector:dig", root, function(spot)
    local plr = client or source
    if not isElement(plr) or getElementType(plr) ~= "player" then return end
    if not isValidSpot(spot) then return end

    -- The player has to be holding a detector and standing next to the hole.
    -- The client checks this too, but the event can be triggered directly.
    if not getElementData(plr, "md:inHand") then return end
    if not getElementData(spot, "md:available") then return end

    local px, py, pz = getElementPosition(plr)
    local bx, by, bz = getElementPosition(spot)
    if getDistanceBetweenPoints3D(px, py, pz, bx, by, bz) > Config.DigRange then return end

    -- Claim the spot right away so two players can't loot the same hole.
    setElementData(spot, "md:available", false)

    if not getElementData(spot, "md:treasure") then
        return notify(plr, Config.Texts.emptyHole, false)
    end

    if math.random(100) <= Config.CashChance then
        local amount = math.random(Config.CashMin, Config.CashMax)
        local ok = pcall(Integration.giveCash, plr, amount)
        if ok then
            return notify(plr, Config.Texts.foundCash:format(amount), true)
        end
    end

    local entry = rollLoot()
    if not entry then
        return notify(plr, Config.Texts.emptyHole, false)
    end

    payOut(plr, entry)
end)

-- ─── Leftover hole + respawn ─────────────────────────────────────────────────

addEvent("metaldetector:hole", true)
addEventHandler("metaldetector:hole", root, function(spot)
    local plr = client or source
    if not isElement(plr) or getElementType(plr) ~= "player" then return end
    if not isValidSpot(spot) then return end
    if holes[spot] then return end     -- a hole is already there

    local x, y, z = getElementPosition(spot)
    local hole = createObject(Config.HoleModel, x, y, z + 0.7)
    setElementCollisionsEnabled(hole, false)
    setObjectScale(hole, 0.5)
    holes[spot] = hole

    setTimer(function(spot, hole)
        if isElement(hole) then destroyElement(hole) end
        holes[spot] = nil
        armSpot(spot)
    end, Config.RespawnTime, 1, spot, hole)
end)

-- ─── Admin state for the attachment editor ───────────────────────────────────
-- The client cannot read the ACL, so it asks the server once and caches the
-- answer. /mdedit and /mdattach are useless to a normal player anyway.

local function sendAdminState(plr)
    if not isElement(plr) then return end
    triggerClientEvent(plr, "metaldetector:adminState", plr, isAdmin(plr))
end

addEvent("metaldetector:requestAdminState", true)
addEventHandler("metaldetector:requestAdminState", root, function()
    sendAdminState(client or source)
end)

addEventHandler("onPlayerLogin", root, function()
    setTimer(sendAdminState, 500, 1, source)
end)
