-- x, y, z, rx, ry, rz, isWheelup, components

function getElementFrame(vehicle)
    local x, y, z = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    local vx, vy, vz = getElementVelocity(vehicle)

    return { x, y, z, rx, ry, rz, vx, vy, vz }
end

--[[
    A recording is a list of frames of an element `target`, such as a hydra, hunter, etc.
    It's primary usecase is to assist creating, editing and recording hydra stunts in-game.

    ## Usage
    A recording instance is made via constructor, then recording must be started manually by calling method `start`,
    stopped by calling method `stop`, rewind, etc.
]]
local Recording = {}
Recording.__index = Recording

setmetatable(Recording, {
    __call = function (class, ...)
        return class.new(...)
    end
})

--- Create a new recording object
-- @param {string} filename name of file
-- @param {element} target of recording
-- @param {number} fps of recording
-- @return recording instance
function Recording.new(filename, target, fps)
    assert(isElement(target), "Expected target to be element")

    local self = setmetatable({}, Recording)

    -- recording metadata
    self.filename = filename or tostring(getTickCount()) .. '.json'
    self.fps = fps or 30

    -- target state
    self.target = target
    self.targetFrozen = false

    -- timer regularly captures frames
    self.timer = nil

    -- frame container
    self.frames = {}

    -- current frame index
    self.frameIndex = 0

    return self
end

function Recording:destroy()
    assert(isElement(self.target))
    if self.targetFrozen then
        self:setTargetFrozen(false)
    end
end

function Recording.load(filename)
    local fh = fileOpen(filename)

    if not fh then
        return nil
    end

    local contents = fileRead(fh, fileGetSize(fh))
    local record = fromJSON(contents)

    local self = setmetatable({}, Recording)

    self.filename = record.filename
    self.fps = record.fps

    self.target = createVehicle(record.target.model, 0, 0, 0)

    self.targetFrozen = false
    self.timer = nil
    self.frames = record.frames
    self.frameIndex = record.frameIndex

    self:setFrameIndex(1)
    self:setTargetFrozen(true)

    return self
end

--- Encode recording object into json
function Recording:save()
    local fh = fileCreate(self.filename)

    if fh then
        iprint(fileWrite(fh, toJSON({
            filename = self.filename,
            fps = self.fps,
            target = { model = getElementModel(self.target), type = getElementType(self.target) },
            frames = self.frames,
            frameIndex = self.frameIndex
        })))

        fileFlush(fh)
        fileClose(fh)
    end
end

-- Target

function Recording:setTargetFrozen(targetFrozen)
    assert(type(targetFrozen) == "boolean")
    setElementFrozen(self.target, targetFrozen)
    setVehicleDamageProof(self.target, targetFrozen)
    self.targetFrozen = targetFrozen
end

-- Frames

function Recording:getFrames()
    return self.frames
end

function Recording:setFrameIndex(newFrameIndex)
    assert(type(newFrameIndex) == "number" and newFrameIndex > 0)

    if newFrameIndex <= #self.frames then
        self.frameIndex = newFrameIndex
        local x, y, z, rx, ry, rz, vx, vy, vz = unpack(self.frames[self.frameIndex])
        setElementPosition(self.target, x, y, z)
        setElementRotation(self.target, rx, ry, rz)
        setElementVelocity(self.target, vx, vy, vz)
    end
end

function Recording:getFrameIndex()
    return self.frameIndex
end

function Recording:getTotalFrames()
    return #self.frames
end

--

function Recording:start()
    if not isTimer(self.timer) then
        self.timer = setTimer(function ()
            local nextFrameIndex = self.frameIndex + 1

            if nextFrameIndex < #self.frames then
                for i = nextFrameIndex + 1, #self.frames do
                    table.remove(self.frames, i)
                end
            end

            self.frames[nextFrameIndex] = getElementFrame(self.target)
            self.frameIndex = nextFrameIndex
        end, 1000 / self.fps, 0)

        self:setTargetFrozen(false)

        if #self.frames > 0 then
            local x, y, z, rx, ry, rz, vx, vy, vz = unpack(self.frames[self.frameIndex])
            setElementPosition(self.target, x, y, z)
            setElementRotation(self.target, rx, ry, rz)
            setElementVelocity(self.target, vx, vy, vz)
        end
    end
end

function Recording:stop()
    if isTimer(self.timer) then
        killTimer(self.timer)
    end

    self.timer = nil

    self:setTargetFrozen(true)
end

------------------
------------------

local recording = nil

addCommandHandler("recording", function (cmd, command, arg1)
    local now = getTickCount()
    local vehicle = getPedOccupiedVehicle(localPlayer)

    if recording and command == "clear" then
        recording:destroy()
        recording = nil
        return outputChatBox("* Cleared recording")
    end

    if command == "load" then
        if recording then
            return outputChatBox("* Please /recording clear first", 255, 0, 0)
        end

        local filename = arg1

        if not filename then
            return outputChatBox("* missing filename", 255, 0, 0)
        end

        recording = Recording.load(filename)
        return outputChatBox("* Loaded recording " .. filename, 0, 255, 0)
    end

    if not vehicle then
        return outputChatBox("* Must be inside vehicle")
    end

    if command == "start" then
        if not recording then
            recording = Recording.new(arg1, vehicle, 30)
            outputChatBox("* Initialized recording", 0, 255, 0)
        end

        setTimer(function () recording:start() end, 1000, 1)
        outputChatBox("* Started recording", 0, 255, 0)
    elseif recording and command == "stop" then
        recording:stop()
        outputChatBox("* Stopped recording")
    elseif recording and command == "save" then
        recording:save()
        outputChatBox("* Saved recording")
    
    elseif recording and command == "seek" then
        local frameIndex = tonumber(arg1)
        recording:setFrameIndex((frameIndex and frameIndex > 0) and frameIndex or 1)
    end
end)

addEventHandler("onClientRender", root, function ()
    if not recording then
        return
    end

    local frames = recording:getFrames()

    for i = 1, #frames - 1 do
        local x1, y1, z1 = unpack(frames[i])
        local x2, y2, z2 = unpack(frames[i+1])
        dxDrawLine3D(x1, y1, z1, x2, y2, z2)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function ()
    if recording then
        recording:destroy()
    end
end)
