--[[
    metaldetector - built-in notification popup (client side).

    Replaces the external notification resource. A short stack of boxes in the
    top right corner, each fading out on its own. Nothing else in the resource
    depends on how this looks, so restyle it freely.
]]--

local sx, sy = guiGetScreenSize()

local LIFETIME = 4000      -- how long a message stays on screen (ms)
local FADE     = 400       -- fade in / fade out length (ms)
local WIDTH    = 300
local HEIGHT   = 56
local MARGIN   = 14
local TITLE    = "Metal detector"

local queue = {}           -- newest last
local rendering = false

local function render()
    local now = getTickCount()
    local y = MARGIN

    for i = #queue, 1, -1 do
        local n = queue[i]
        local age = now - n.at

        if age > LIFETIME then
            table.remove(queue, i)
        else
            local alpha = 1
            if age < FADE then
                alpha = age / FADE
            elseif age > LIFETIME - FADE then
                alpha = (LIFETIME - age) / FADE
            end

            local x = sx - WIDTH - MARGIN
            local a = math.floor(alpha * 255)
            local r, g, b = 80, 200, 120
            if not n.ok then r, g, b = 200, 70, 70 end

            dxDrawRectangle(x, y, WIDTH, HEIGHT, tocolor(0, 0, 0, math.floor(alpha * 190)))
            dxDrawRectangle(x, y, 4, HEIGHT, tocolor(r, g, b, a))
            dxDrawText(TITLE, x + 14, y + 8, x + WIDTH - 10, y + 8,
                tocolor(r, g, b, a), 1.0, "default-bold")
            dxDrawText(n.text, x + 14, y + 26, x + WIDTH - 10, y + HEIGHT - 6,
                tocolor(255, 255, 255, a), 1.0, "default", "left", "top", true, true)

            y = y + HEIGHT + 8
        end
    end

    if #queue == 0 then
        removeEventHandler("onClientRender", root, render)
        rendering = false
    end
end

-- Show a message. Used locally and by the server through the event below.
function Notify(text, ok)
    if type(text) ~= "string" or text == "" then return end

    queue[#queue + 1] = { text = text, ok = ok and true or false, at = getTickCount() }
    while #queue > 4 do table.remove(queue, 1) end

    if not rendering then
        addEventHandler("onClientRender", root, render)
        rendering = true
    end
end

addEvent("metaldetector:notify", true)
addEventHandler("metaldetector:notify", root, function(text, ok)
    Notify(text, ok)
end)
