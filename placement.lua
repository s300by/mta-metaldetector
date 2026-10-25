--[[
    metaldetector - interactive attachment editor (client side).

    Adjusts the offset, rotation and bone of the detector in the player's hand
    so you don't have to restart the resource for every tweak.

    Start:  /mdedit   (admins only, the detector has to be out)

    Controls:
      Arrows             move X/Y (left/right, forward/back)
      Page Up / Page Dn  height Z
      Q / E              yaw   (RZ)
      R / F              pitch (RX)
      U / J             roll  (RY)   (T/G is unusable - T opens the chat)
      Mouse wheel        switch bone (shoulder / elbow / wrist / hand)
      Shift / Alt        faster / slower
      Enter              confirm and print the values  |  Backspace  cancel

    Enter only prints the values into the chat (and keeps them until the
    resource restarts). Write them into Config.Attach in config.lua to keep them.
]]--

local sx, sy = guiGetScreenSize()

local MOVE = 0.20    -- m/s
local ROT  = 45      -- deg/s
local FAST = 3.0
local SLOW = 0.25

-- Right arm bones you can cycle through with the mouse wheel.
local BONES = {
    { id = 22, name = "shoulder" },
    { id = 23, name = "elbow" },
    { id = 24, name = "wrist" },
    { id = 25, name = "hand" },
}

local edit = nil

local function isTyping()
    return (isChatBoxInputActive and isChatBoxInputActive())
        or (isConsoleActive and isConsoleActive())
end

local function boneIndexOf(id)
    for i, b in ipairs(BONES) do
        if b.id == id then return i end
    end
    return 2 -- default = elbow
end

local function boneName(id)
    for _, b in ipairs(BONES) do
        if b.id == id then return b.name end
    end
    return "?"
end

local function apply()
    if not edit then return end
    mdSetAttach(edit.bone, edit.pos, edit.rot)
end

local function stopEdit()
    if not edit then return end
    removeEventHandler("onClientRender", root, edit.render)
    for _, b in ipairs(edit.binds) do unbindKey(b[1], b[2], b[3]) end
    toggleAllControls(true, true, false)
    showCursor(false)
    edit = nil
end

local function saveEdit()
    if not edit or isTyping() then return end
    local p, r = edit.pos, edit.rot
    local line = ("%d %.3f %.3f %.3f %d %d %d"):format(
        edit.bone, p[1], p[2], p[3],
        math.floor(r[1] + 0.5), math.floor(r[2] + 0.5), math.floor(r[3] + 0.5))

    outputChatBox("#FFAE40[Detector] #ffffffValues: #FFAE40" .. line, 255, 255, 255, true)
    outputChatBox("#FFAE40[Detector] #ffffffWrite them into Config.Attach in config.lua, otherwise they are lost on restart.",
        255, 255, 255, true)
    Notify("Attachment confirmed, values are in the chat.", true)
    stopEdit()
end

local function cancelEdit()
    if not edit or isTyping() then return end
    mdSetAttach(edit.origBone, edit.origPos, edit.origRot)
    Notify("Cancelled - attachment restored.", false)
    stopEdit()
end

-- ── HUD ──────────────────────────────────────────────────────────────────────
local function hintLine(x, y, hints)
    local cx = x
    for _, h in ipairs(hints) do
        dxDrawText(h[1], cx, y, cx, y, tocolor(255, 210, 90, 255), 1.0, "default-bold")
        cx = cx + dxGetTextWidth(h[1], 1.0, "default-bold") + 6
        dxDrawText(h[2], cx, y, cx, y, tocolor(230, 230, 230, 235), 1.0, "default")
        cx = cx + dxGetTextWidth(h[2], 1.0, "default") + 18
    end
end

local function renderHUD()
    if not edit then return end
    local p, r = edit.pos, edit.rot
    local bw, bh = 580, 132
    local bx, by = (sx - bw) / 2, sy - bh - 40
    dxDrawRectangle(bx, by, bw, bh, tocolor(0, 0, 0, 170))
    dxDrawRectangle(bx, by, bw, 30, tocolor(30, 120, 60, 220))
    dxDrawText("DETECTOR ATTACHMENT", bx, by + 6, bx + bw, by + 6,
        tocolor(255, 255, 255, 255), 1.1, "default-bold", "center")

    local readout = ("X %.3f   Y %.3f   Z %.3f     RX %d   RY %d   RZ %d     Bone %d (%s)"):format(
        p[1], p[2], p[3],
        math.floor(r[1] + 0.5), math.floor(r[2] + 0.5), math.floor(r[3] + 0.5),
        edit.bone, boneName(edit.bone))
    dxDrawText(readout, bx + 16, by + 40, bx + bw, by + 40, tocolor(150, 230, 170, 255), 1.05, "default-bold")

    hintLine(bx + 16, by + 66,  { {"Arrows","move X/Y"}, {"PgUp/PgDn","height Z"}, {"Wheel","bone"} })
    hintLine(bx + 16, by + 88,  { {"Q/E","yaw RZ"}, {"R/F","pitch RX"}, {"U/J","roll RY"}, {"Shift/Alt","faster/slower"} })
    hintLine(bx + 16, by + 110, { {"Enter","confirm"}, {"Backspace","cancel"} })
end

-- ── Render loop ──────────────────────────────────────────────────────────────
local function editRender()
    if not edit then return end

    -- Detector gone (put away / died)? Stop.
    if not isElement(mdGetDetector()) then
        Notify("The detector is no longer in hand - editing stopped.", false)
        stopEdit()
        return
    end

    local dt = (edit.lastTick and (getTickCount() - edit.lastTick) / 1000) or (1 / 60)
    edit.lastTick = getTickCount()
    if dt > 0.1 then dt = 0.1 end

    if not isTyping() then
        local mul = 1.0
        if getKeyState("lshift") or getKeyState("rshift") then mul = FAST
        elseif getKeyState("lalt") or getKeyState("ralt") then mul = SLOW end
        local dm, dr = MOVE * mul * dt, ROT * mul * dt
        local p, r = edit.pos, edit.rot

        if getKeyState("arrow_l") then p[1] = p[1] - dm end
        if getKeyState("arrow_r") then p[1] = p[1] + dm end
        if getKeyState("arrow_u") then p[2] = p[2] + dm end
        if getKeyState("arrow_d") then p[2] = p[2] - dm end
        if getKeyState("pgup")    then p[3] = p[3] + dm end
        if getKeyState("pgdn")    then p[3] = p[3] - dm end
        if getKeyState("q") then r[3] = r[3] - dr end
        if getKeyState("e") then r[3] = r[3] + dr end
        if getKeyState("r") then r[1] = r[1] - dr end
        if getKeyState("f") then r[1] = r[1] + dr end
        -- U/J instead of T/G - T opens the chat
        if getKeyState("u") then r[2] = r[2] - dr end
        if getKeyState("j") then r[2] = r[2] + dr end

        apply()
    end
    renderHUD()
end

local function cycleBone(delta)
    if not edit then return end
    local i = boneIndexOf(edit.bone) + delta
    if i < 1 then i = #BONES elseif i > #BONES then i = 1 end
    edit.bone = BONES[i].id
    apply()
end

-- ── Start ────────────────────────────────────────────────────────────────────
addCommandHandler("mdedit", function()
    if not mdIsAdmin() then return end

    if edit then
        stopEdit()
        return
    end

    if not isElement(mdGetDetector()) then
        Notify("Take the detector out first.", false)
        return
    end

    local bone, pos, rot = mdGetAttach()

    edit = {
        bone = bone,
        pos  = { pos[1], pos[2], pos[3] },
        rot  = { rot[1], rot[2], rot[3] },
        origBone = bone,
        origPos  = { pos[1], pos[2], pos[3] },
        origRot  = { rot[1], rot[2], rot[3] },
        lastTick = getTickCount(),
        binds = {},
        render = editRender,
    }

    local function bind(key, state, fn)
        edit.binds[#edit.binds + 1] = { key, state, fn }
        bindKey(key, state, fn)
    end
    bind("enter",     "down", saveEdit)
    bind("num_enter", "down", saveEdit)
    bind("backspace", "down", cancelEdit)
    bind("mouse_wheel_up",   "down", function() cycleBone( 1) end)
    bind("mouse_wheel_down", "down", function() cycleBone(-1) end)

    addEventHandler("onClientRender", root, editRender)
    -- Kill the GTA controls: Enter would get you into a car, Shift would jump...
    toggleAllControls(false, true, false)
    showCursor(false)
    Notify("Adjust the attachment and confirm with Enter. (Backspace = cancel)", true)
end)

addEventHandler("onClientResourceStop", resourceRoot, stopEdit)
