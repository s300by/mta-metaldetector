--[[
    metaldetector - client side.

    Draws the detector HUD (zone, battery, signal strength), beeps when the
    player gets close to a spot, and runs the two-stage dig: first the digging
    animation, then picking the find up.

    The loot roll itself is NOT here - the client only tells the server "I dug
    at this spot" and the server decides what comes out (see server.lua).
]]--

local screenX, screenY = guiGetScreenSize()

-- ─── Encrypted model files ───────────────────────────────────────────────────
-- The .wardis files are TEA-encrypted DFF models: the first 661 bytes are
-- encrypted, the rest is plain. This reads them back into a normal DFF.

local LOCK_KEY    = "KrisztianBalazs2022"
local LOCK_LENGTH = 655 + 6

local function loadLockedFile(path, key)
    local file = fileOpen(path)
    if not file then
        outputDebugString("[metaldetector] cannot open " .. path, 1)
        return nil
    end

    local size       = fileGetSize(file)
    local firstPart  = fileRead(file, LOCK_LENGTH)
    fileSetPos(file, LOCK_LENGTH)
    local secondPart = fileRead(file, size - LOCK_LENGTH)
    fileClose(file)

    return decodeString("tea", firstPart, { key = key }) .. secondPart
end

local detectorTxd = engineLoadTXD("files/detector.txd", true)
engineImportTXD(detectorTxd, Config.DetectorModel)
local detectorDff = engineLoadDFF(loadLockedFile("files/detector.wardis", LOCK_KEY), Config.DetectorModel)
engineReplaceModel(detectorDff, Config.DetectorModel)

local findTxd = engineLoadTXD("files/turas1.txd", true)
engineImportTXD(findTxd, Config.FindModel)
local findDff = engineLoadDFF(loadLockedFile("files/turas1.wardis", LOCK_KEY), Config.FindModel)
engineReplaceModel(findDff, Config.FindModel)

-- ─── State ───────────────────────────────────────────────────────────────────

local font = dxCreateFont("files/pda.ttf", 10)

local detectors = {}        -- [player] = detector object in their hand
local dug       = {}        -- [spot]   = true, hole already dug, ready to loot
local digging   = nil       -- { spot, startedAt, object }
local inAnim    = false     -- digging animation is playing

local closestSpot, closestDist = nil, math.huge

local beepTick    = 0
local beepPlayed  = false
local isAdmin     = false

-- ─── Admin flag (for the attachment editor) ──────────────────────────────────

addEvent("metaldetector:adminState", true)
addEventHandler("metaldetector:adminState", root, function(state)
    isAdmin = state and true or false
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("metaldetector:requestAdminState", localPlayer)
end)

-- Used by placement.lua.
function mdIsAdmin()
    return isAdmin
end

-- ─── Controls ────────────────────────────────────────────────────────────────

local function toggleControls(enabled)
    toggleControl("enter_exit", enabled)
    toggleControl("enter_passenger", enabled)
    toggleControl("fire", enabled)
    toggleControl("jump", enabled)
    toggleControl("sprint", enabled)
    toggleControl("vehicle_fire", enabled)
end

-- ─── Digging ─────────────────────────────────────────────────────────────────

local function distanceTo(x, y, z)
    local px, py, pz = getElementPosition(localPlayer)
    return getDistanceBetweenPoints3D(x, y, z, px, py, pz)
end

local function stopDigging(finished)
    if not digging then return end

    if isElement(digging.object) then destroyElement(digging.object) end
    if isElement(detectors[localPlayer]) then
        setElementAlpha(detectors[localPlayer], 255)
    end

    setPedAnimation(localPlayer)
    inAnim = false

    if finished then
        dug[digging.spot] = true
        -- The visible hole is created by the server so everyone sees it.
        triggerServerEvent("metaldetector:hole", localPlayer, digging.spot)
    end

    digging = nil
end

local function startDigging(spot)
    local x, y, z = getElementPosition(spot)

    if isElement(detectors[localPlayer]) then
        setElementAlpha(detectors[localPlayer], 0)
    end

    setPedAnimation(localPlayer, "bomber", "bom_plant")
    inAnim = true

    if Config.SoundEnabled then
        local sound = playSound("files/shoveldig.mp3")
        if sound then setSoundVolume(sound, 0.5) end
    end

    local object = createObject(Config.FindModel, x, y, z + 0.7)
    setElementCollisionsEnabled(object, false)
    setObjectScale(object, 0.01)

    digging = { spot = spot, startedAt = getTickCount(), object = object }
end

-- Dig / pick up the find at the spot the player is standing on.
local function attemptDig()
    if digging then return end
    if not getElementData(localPlayer, "md:inHand") then return end
    if not isElement(closestSpot) or closestDist > Config.DigIconRange then return end
    if not getElementData(closestSpot, "md:available") then return end

    if dug[closestSpot] then
        -- Hole is open - take whatever is in it. The server rolls the loot.
        triggerServerEvent("metaldetector:dig", localPlayer, closestSpot)
        dug[closestSpot] = nil
    else
        startDigging(closestSpot)
    end
end

-- Grows the mound while the player digs and finishes the dig when time is up.
local function updateDigging()
    local progress = (getTickCount() - digging.startedAt) / Config.DigDuration

    if isElement(digging.object) then
        setObjectScale(digging.object, 0.5 * math.min(1, progress))
    end

    if not isElement(digging.spot) then
        return stopDigging(false)
    end

    local x, y, z = getElementPosition(digging.spot)
    if distanceTo(x, y, z) > Config.DigRange then
        return stopDigging(false)     -- walked away mid-dig
    end

    if progress >= 1 then
        stopDigging(true)
    end
end

-- ─── Signal + HUD ────────────────────────────────────────────────────────────

local SIGNAL_STEPS = 8

-- 8 bars right on top of the spot, 1 bar at Config.SignalRange.
local function signalLevel(dist)
    if dist >= Config.SignalRange then return 0 end
    local step = Config.SignalRange / SIGNAL_STEPS
    local level = SIGNAL_STEPS - math.floor(dist / step)
    return math.max(1, math.min(SIGNAL_STEPS, level))
end

local function findClosestSpot()
    local best, bestDist = nil, math.huge

    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do
        if getElementData(obj, "md:spot") and getElementData(obj, "md:available") then
            local x, y, z = getElementPosition(obj)
            local dist = distanceTo(x, y, z)
            if dist < bestDist then
                best, bestDist = obj, dist
            end
        end
    end

    return best, bestDist
end

local function drawDigPrompt()
    if not isElement(closestSpot) or closestDist > Config.DigIconRange then return end
    if inAnim then return end

    local x, y, z = getElementPosition(closestSpot)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.5)
    if not sx then return end

    local size = 42
    dxDrawRectangle(sx - size / 2, sy - size / 2, size, size, tocolor(0, 0, 0, 180))
    dxDrawImage(sx - (size - 12) / 2, sy - (size - 12) / 2, size - 12, size - 12,
        "files/dig.png", 0, 0, 0, tocolor(255, 255, 255, 220))

    local hint = Config.Texts.digHint:format(Config.DigKey:upper())
    dxDrawText(hint, sx, sy + size / 2 + 4, sx, sy + size / 2 + 4,
        tocolor(255, 255, 255, 230), 1.0, "default-bold", "center", "top")
end

local function playBeep(dist)
    if inAnim or not Config.SoundEnabled then return end

    -- The closer the spot, the shorter the gap between beeps.
    local interval = 200 + (dist / Config.BeepRange) * 1000
    if getTickCount() - beepTick < interval then return end

    beepTick = getTickCount()
    playSound(dist < Config.SignalRange and "files/beep2.mp3" or "files/beep.mp3")
end

local function render()
    if not getElementData(localPlayer, "md:inHand") then return end

    toggleControls(false)

    closestSpot, closestDist = findClosestSpot()

    if digging then updateDigging() end

    -- Panel background
    dxDrawImage(screenX / 2 - 390 / 2, screenY - 250 - 50, 390, 250, "files/bg.png")

    local zone = getZoneName(getElementPosition(localPlayer))
    dxDrawText(zone, screenX / 2 - 1100, screenY - 195 - 50, 1125, 50,
        tocolor(0, 0, 0, 255), 0.9, font, "right")
    dxDrawText(Config.Texts.battery, screenX / 2 - 165, screenY - 195 - 50, 390, 250,
        tocolor(0, 0, 0, 255), 0.9, font)

    local hasTreasure = isElement(closestSpot) and getElementData(closestSpot, "md:treasure")
    local level = hasTreasure and signalLevel(closestDist) or 0

    local signalText = Config.Texts.noSignal
    if level > 0 then
        signalText = Config.Texts.signal:format(level)
        -- Above Config.SignalRange there is no image to draw, so skip it -
        -- dxDrawImage with a nil path would spam the debug log every frame.
        dxDrawImage(screenX / 2 - 390 / 2, screenY - 250 - 50, 390, 250,
            "files/" .. level .. ".png")
    end

    dxDrawText(signalText, screenX / 2 - 50, screenY - 225 - 50, 200, 100,
        tocolor(0, 0, 0, 255), 1.25, font)

    if hasTreasure and closestDist < Config.BeepRange then
        playBeep(closestDist)
    end

    drawDigPrompt()
end

-- Clicking the on-screen icon works too, for setups that show a cursor.
addEventHandler("onClientClick", root, function(button, state)
    if button ~= "left" or state ~= "down" then return end
    if not isCursorShowing() then return end
    attemptDig()
end)

-- ─── Arm pose ────────────────────────────────────────────────────────────────
-- Twists the spine and locks the right arm so the player sweeps the detector in
-- front of the body, following where the camera looks.

local lastViewRotZ = 0
local viewRotInterpolation = false

addEventHandler("onClientPedsProcessed", root, function()
    if not getElementData(localPlayer, "md:inHand") or inAnim then return end

    local cameraX, cameraY, _, lookAtX, lookAtY = getCameraMatrix()

    local pedRotZ = select(3, getElementRotation(localPlayer))
    local camRotZ = math.deg(math.atan2(lookAtX - cameraX, lookAtY - cameraY))
    local viewRot = pedRotZ + camRotZ

    if viewRot < -180 then
        viewRot = viewRot + 360
    elseif viewRot > 180 then
        viewRot = viewRot - 360
    end

    viewRot = math.max(-45, math.min(45, viewRot))

    if viewRot ~= lastViewRotZ then
        if not viewRotInterpolation then
            viewRotInterpolation = { getTickCount(), lastViewRotZ }
        end

        local elapsedFraction = (getTickCount() - viewRotInterpolation[1]) / 500
        viewRotInterpolation[3] = interpolateBetween(
            viewRotInterpolation[2], 0, 0, viewRot, 0, 0, elapsedFraction, "Linear")

        if elapsedFraction >= 1 then
            lastViewRotZ = viewRot
            viewRotInterpolation = false
        end
    end

    viewRot = viewRotInterpolation and viewRotInterpolation[3] or viewRot

    local pelvisRotZ, pelvisRotX, pelvisRotY = getElementBoneRotation(localPlayer, 2)
    local spineRotZ, spineRotX, spineRotY = getElementBoneRotation(localPlayer, 3)

    setElementBoneRotation(localPlayer, 2, pelvisRotZ - viewRot / 2, pelvisRotX + 5, pelvisRotY)
    setElementBoneRotation(localPlayer, 3, spineRotZ - viewRot, spineRotX + 5, spineRotY)

    setElementBoneRotation(localPlayer, 22, 0, -100, -45)
    setElementBoneRotation(localPlayer, 23, 0, 0, 0)
    setElementBoneRotation(localPlayer, 24, 180, 0, 0)

    updateElementRpHAnim(localPlayer)
end)

-- ─── Detector in hand ────────────────────────────────────────────────────────

local attach = {
    bone = Config.Attach.bone,
    pos  = { Config.Attach.pos[1], Config.Attach.pos[2], Config.Attach.pos[3] },
    rot  = { Config.Attach.rot[1], Config.Attach.rot[2], Config.Attach.rot[3] },
}

local function showDetector(state, player)
    if state then
        if isElement(detectors[player]) then return end

        local object = createObject(Config.DetectorModel, getElementPosition(player))
        setElementAlpha(object, 255)
        setElementCollisionsEnabled(object, false)
        detectors[player] = object

        BoneAttach.attach(object, player, attach.bone,
            attach.pos[1], attach.pos[2], attach.pos[3],
            attach.rot[1], attach.rot[2], attach.rot[3])

        if player == localPlayer then
            addEventHandler("onClientRender", root, render)
            bindKey(Config.DigKey, "down", attemptDig)
            inAnim = false
            toggleControls(false)
        end
    else
        if isElement(detectors[player]) then
            BoneAttach.detach(detectors[player])
            destroyElement(detectors[player])
        end
        detectors[player] = nil

        if player == localPlayer then
            stopDigging(false)
            removeEventHandler("onClientRender", root, render)
            unbindKey(Config.DigKey, "down", attemptDig)
            toggleControls(true)
            closestSpot, closestDist = nil, math.huge
        end
    end
end

addEventHandler("onClientElementDataChange", root, function(key, _, newValue)
    if key ~= "md:inHand" then return end
    if getElementType(source) ~= "player" then return end
    if not isElementStreamedIn(source) and source ~= localPlayer then return end

    showDetector(newValue and true or false, source)
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" and getElementData(source, "md:inHand") then
        showDetector(true, source)
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "player" and getElementData(source, "md:inHand") then
        showDetector(false, source)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopDigging(false)
    for player in pairs(detectors) do
        showDetector(false, player)
    end
    toggleControls(true)
end)

-- ─── Attachment access for placement.lua ─────────────────────────────────────

function mdGetDetector()
    return detectors[localPlayer]
end

function mdGetAttach()
    return attach.bone,
        { attach.pos[1], attach.pos[2], attach.pos[3] },
        { attach.rot[1], attach.rot[2], attach.rot[3] }
end

function mdSetAttach(bone, pos, rot)
    if bone then attach.bone = bone end
    if pos then attach.pos = { pos[1], pos[2], pos[3] } end
    if rot then attach.rot = { rot[1], rot[2], rot[3] } end

    local det = detectors[localPlayer]
    if not isElement(det) then return false end

    BoneAttach.setBone(det, attach.bone)
    BoneAttach.setPositionOffset(det, attach.pos[1], attach.pos[2], attach.pos[3])
    BoneAttach.setRotationOffset(det, attach.rot[1], attach.rot[2], attach.rot[3])
    return true
end

-- ─── Attachment tuning ───────────────────────────────────────────────────────
-- The right offsets can only be found in-engine, hence this helper.
--   /mdattach                                      show the current values
--   /mdattach <bone> <x> <y> <z> <rx> <ry> <rz>     set them
-- Changes last until the resource restarts - write the result into
-- Config.Attach in config.lua once you are happy with it. /mdedit (see
-- placement.lua) does the same thing interactively.

addCommandHandler("mdattach", function(_, bone, ox, oy, oz, rx, ry, rz)
    if not isAdmin then return end

    if not bone then
        outputChatBox("#FFAE40[Detector] #ffffffCurrent: bone " .. attach.bone ..
            ", pos " .. table.concat(attach.pos, " ") ..
            ", rot " .. table.concat(attach.rot, " "), 255, 255, 255, true)
        outputChatBox("#FFAE40[Detector] #ffffffUsage: /mdattach <bone> <x> <y> <z> <rx> <ry> <rz>",
            255, 255, 255, true)
        return
    end

    mdSetAttach(
        tonumber(bone) or attach.bone,
        { tonumber(ox) or 0, tonumber(oy) or 0, tonumber(oz) or 0 },
        { tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0 })

    outputChatBox("#FFAE40[Detector] #ffffffSet: bone " .. attach.bone ..
        ", pos " .. table.concat(attach.pos, " ") ..
        ", rot " .. table.concat(attach.rot, " "), 255, 255, 255, true)
end)
