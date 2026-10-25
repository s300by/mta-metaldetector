--[[
    metaldetector - integration layer (server side).

    This is the ONLY file you need to touch to plug the resource into your own
    inventory, money or notification system. Out of the box everything works
    without any other resource:

      * countItem  - pretends the player owns a detector
      * giveItem   - no inventory, so a find is paid out in cash (entry.value)
      * giveCash   - native givePlayerMoney
      * notify     - chatbox + the client-side popup in notify.lua

    Replace the bodies with calls into your own scripts and the rest of the
    resource stays untouched.
]]--

Integration = {}

-- How many pieces of `item` the player owns.
-- Only consulted when Config.RequireItem is true.
function Integration.countItem(plr, item)
    -- Example with an inventory resource:
    --   return tonumber(exports["my-inventory"]:countPlayerItem(plr, item)) or 0
    return 1
end

-- Hand an item to the player.
-- Return true  → the item was added, the player is told what they found.
-- Return false → no inventory handled it; the resource pays out entry.value
--                in cash instead, so a find is never silently lost.
function Integration.giveItem(plr, item, entry)
    -- Example with an inventory resource:
    --   return exports["my-inventory"]:addPlayerItem(plr, item) ~= false
    return false
end

-- Give money to the player.
function Integration.giveCash(plr, amount)
    -- Example with an economy resource:
    --   return exports["my-inventory"]:givePlayerCash(plr, amount)
    givePlayerMoney(plr, amount)
    return true
end

-- Tell the player something. `ok` is true for good news, false for a refusal.
function Integration.notify(plr, text, ok)
    if not isElement(plr) then return end
    outputChatBox((ok and "#64c864" or "#c86464") .. "[Detector] #ffffff" .. text,
        plr, 255, 255, 255, true)
    triggerClientEvent(plr, "metaldetector:notify", plr, text, ok and true or false)
end
