--[[
    metaldetector - minimal bone attachment (client side).

    Replaces the external pAttach resource. Only what this resource needs:
    keep one object glued to a ped's bone with a position and rotation offset.

    How it works: every frame the bone's world position is read with
    getPedBonePosition() and the offset is applied in the ped's local space
    (X = right, Y = forward, Z = up). The object's rotation is the ped's
    rotation plus the offset - which is correct here because the client forces
    the arm into a fixed pose while the detector is out, so the hand never
    moves relative to the body.

    The render handler is attached lazily on the first attach() and removed
    again when nothing is attached. That also guarantees it runs AFTER the bone
    rotations are applied in client.lua (handlers fire in registration order).
]]--

BoneAttach = {}

local attached = {}        -- [element] = { ped, bone, pos = {x,y,z}, rot = {rx,ry,rz} }
local handlerActive = false

local function update()
    for el, a in pairs(attached) do
        if not isElement(el) or not isElement(a.ped) then
            attached[el] = nil
        elseif isElementStreamedIn(a.ped) then
            local bx, by, bz = getPedBonePosition(a.ped, a.bone)
            if bx then
                local _, _, pedRz = getElementRotation(a.ped)
                local rad = math.rad(pedRz)
                local cos, sin = math.cos(rad), math.sin(rad)

                -- offset from ped space into world space
                local ox, oy, oz = a.pos[1], a.pos[2], a.pos[3]
                setElementPosition(el,
                    bx + ox * cos - oy * sin,
                    by + ox * sin + oy * cos,
                    bz + oz, false)
                setElementRotation(el, a.rot[1], a.rot[2], pedRz + a.rot[3])
            end
        end
    end

    if not next(attached) and handlerActive then
        removeEventHandler("onClientPedsProcessed", root, update)
        handlerActive = false
    end
end

function BoneAttach.attach(el, ped, bone, x, y, z, rx, ry, rz)
    if not isElement(el) or not isElement(ped) then return false end

    attached[el] = {
        ped  = ped,
        bone = tonumber(bone) or 23,
        pos  = { tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0 },
        rot  = { tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0 },
    }

    if not handlerActive then
        addEventHandler("onClientPedsProcessed", root, update)
        handlerActive = true
    end
    return true
end

function BoneAttach.detach(el)
    attached[el] = nil
    return true
end

function BoneAttach.isAttached(el)
    return attached[el] ~= nil
end

function BoneAttach.setPositionOffset(el, x, y, z)
    local a = attached[el]
    if not a then return false end
    a.pos = { tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0 }
    return true
end

function BoneAttach.setRotationOffset(el, rx, ry, rz)
    local a = attached[el]
    if not a then return false end
    a.rot = { tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0 }
    return true
end

function BoneAttach.setBone(el, bone)
    local a = attached[el]
    if not a then return false end
    a.bone = tonumber(bone) or a.bone
    return true
end
