--[[
    Author: [SW]Exile
    Description: recorder is a script to assist in creating, editing and recording hydra stunts in-game
]]

--[[
    A recording is an object which contains its various metadata and frames of a target element.
]]
local Recording = {}
Recording.__index = Recording

setmetatable(Recording, {
    __call = function (class, ...)
        return class.new(...)
    end
})

--
-- Constructors
--

--- Create a new recording object
-- @param {string} filename name of file
-- @param {element} target of recording
-- @param {number} fps of recording
-- @return recording instance
function Recording.new(target, fps)
    assert(isElement(target), "Expected target to be element")

    local self = setmetatable({}, Recording)

    -- recording metadata
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

--- Safely destroy recording
-- undo MTA state and keep the garbage collector happy
function Recording:destroy()
    assert(isElement(self.target))

    if self.targetFrozen then
        self:setTargetFrozen(false)
    end

    if isTimer(self.tiemr) then
        killTimer(self.timer)
    end
end

--- Load a recording object with preset target
function Recording.load(recording, target)
    assert(recording and isElement(target))

    local self = setmetatable({}, Recording)

    self.filename = recording.filename
    self.fps = recording.fps
    self.target = target
    self.targetFrozen = true
    self.timer = target
    self.frames = recording.frames
    self.frameIndex = recording.frameIndex

    self:setFrameIndex(1)
    self:setTargetFrozen(true)

    return self
end

--- Return a recording object containing only scalar values, i.e., number, boolean or string
function Recording:toScalar()
    return {
        filename = self.filename,
        fps = self.fps,
        target = { model = getElementModel(self.target), type = getElementType(self.target) },
        frames = self.frames,
        frameIndex = self.frameIndex
    }
end

--
-- Target
--

function Recording:getTarget()
    return self.target
end

--- Freeze target
-- @todo Create a separate Recorder class and keep Recording as data structure
function Recording:setTargetFrozen(targetFrozen)
    assert(type(targetFrozen) == "boolean")
    setElementFrozen(self.target, targetFrozen)
    setVehicleDamageProof(self.target, targetFrozen)
    self.targetFrozen = targetFrozen
end

--
-- Frames
--

--- Captures next frame of the target
-- A frame is a 9-tuple containing 
-- position {x, y, z}
-- velocity {vx, vy, vz}
-- euler rotation angles {rx, ry, rz}
-- @todo aircraft wheel up + component positions & rotations (for various doors, panels etc)
function Recording:addTargetFrame()
    local matrix = getElementMatrix(self.target)

    local left, forward, up, position = unpack(matrix)

    local lx, ly, lz, lw = unpack(left)
    local fx, fy, fz, fw = unpack(forward)
    local ux, uy, uz, uw = unpack(up)
    local px, py, pz, pw = unpack(position)
    local vx, vy, vz = getElementVelocity(self.target)

    local nextFrameIndex = self.frameIndex + 1
    if nextFrameIndex < #self.frames then
        for i = nextFrameIndex + 1, #self.frames do
            table.remove(self.frames, i)
        end
    end

    self.frames[nextFrameIndex] = { lx, ly, lz, lw, fx, fy, fz, fw, ux, uy, uz, uw, px, py, pz, pw, vx, vy, vz }
    self.frameIndex = nextFrameIndex
end

function Recording:getFrames()
    return self.frames
end

function Recording:setFrameIndex(newFrameIndex)
    assert(type(newFrameIndex) == "number" and newFrameIndex > 0)

    if newFrameIndex <= #self.frames then
        self.frameIndex = newFrameIndex
        local lx, ly, lz, lw, fx, fy, fz, fw, ux, uy, uz, uw, px, py, pz, pw, vx, vy, vz = unpack(self:getFrame(self.frameIndex))
        setElementMatrix(self.target, { { lx, ly, lz, lw }, { fx, fy, fz, fw }, { ux, uy, uz, uw }, { px, py, pz, pw } })
        setElementVelocity(self.target, vx, vy, vz)
    end
end

function Recording:getFrameIndex()
    return self.frameIndex
end

function Recording:getTotalFrames()
    return #self.frames
end

function Recording:getFrame(index)
    assert(type(index) == "number" and (index > 0 or index < #self.frames))
    return self.frames[index]
end

function Recording:getFrameRate()
    return self.fps
end

--
-- Main controls
--

function Recording:start()
    if not self.timer then
        self.timer = function ()
            self:addTargetFrame()
        end

        addEventHandler("onClientRender", root, self.timer)

        self:setTargetFrozen(false)

        if #self.frames > 0 then
            local x, y, z, rx, ry, rz, vx, vy, vz = unpack(self:getFrame(self.frameIndex))
            setElementPosition(self.target, x, y, z)
            setElementRotation(self.target, rx, ry, rz)
            setElementVelocity(self.target, vx, vy, vz)
        end
    end
end

function Recording:stop()
    removeEventHandler("onClientRender", root, self.timer)

    self.timer = nil

    self:setTargetFrozen(true)
end

--[[
    A player is an object that plays recordings
]]
local Player = {}
Player.__index = Player

setmetatable(Player, {
    __call = function (class, ...)
        return class.new(...)
    end
})

function Player.new(recording, looped)
    local self = setmetatable({}, Player)

    self.recording = recording

    self.looped = looped

    self.playing = false

    self.timer = nil

    self.frameIndex = 1

    self.lastUpdateTick = 0

    self.updateHandler = function (dt) self:update(dt) end

    return self
end

function Player:destroy()
    if self.playing then
        removeEventHandler("onClientPreRender", root, self.updateHandler)
    end
    self.updateHandler = nil
end

function Player:isPlaying()
    return self.playing
end

function Player:update(dt)
    self.frameIndex = self.frameIndex + 1
    if self.looped and self.frameIndex > self.recording:getTotalFrames() then
        self.frameIndex = 1
    end
    self.lastUpdateTick = now
    self.recording:setFrameIndex(self.frameIndex)
end

function Player:play()
    if not self:isPlaying() then
        addEventHandler("onClientPreRender", root, self.updateHandler)

        self.recording:setTargetFrozen(false)

        self.playing = true
    end
end

function Player:pause()
    if self:isPlaying() then
        self.recording:setTargetFrozen(true)

        removeEventHandler("onClientPreRender", root, self.updateHandler)

        self.playing = false
    end
end

--
-- Client Controller
--

local player = nil
local recording = nil
local FPS = getFPSLimit()

addCommandHandler("recording", function (cmd, command, arg1)
    local now = getTickCount()
    local vehicle = getPedOccupiedVehicle(localPlayer)

    if command == "clear" then
        if player then 
            player:destroy() 
            player = nil
        end

        if recording then
            recording:destroy()
            recording = nil
        end
        return outputChatBox("* Succesfully cleared recording", 255, 255, 0)
    end

    if not vehicle then
        return outputChatBox("* You must be inside vehicle", 255, 0, 0)
    end

    if command == "load" then
        if recording then
            return outputChatBox("* You must clear recording first", 255, 0, 0)
        end

        local filename = arg1

        if not filename then
            return outputChatBox("* missing filename", 255, 0, 0)
        end

        local fh = fileOpen(filename)
        if fh then
            local record = fromJSON(fileRead(fh, fileGetSize(fh)))
            fileClose(fh)
            recording = Recording.load(record, vehicle)
            outputChatBox("* Loaded recording " .. filename .. " " .. tostring(recording:getTotalFrames()) .. " frames", 0, 255, 0)
        end
    elseif command == "start" then
        if not recording then
            recording = Recording.new(vehicle, FPS)
            outputChatBox("* Initialized recording", 255, 255, 0)
        end

        recording:start()

        outputChatBox("* Started recording", 0, 255, 0)
    elseif recording and command == "stop" then
        recording:stop()
        outputChatBox("* Stopped recording", 0, 255, 0)
    elseif recording and command == "save" then
        local filename = (arg1 or tostring(getTickCount())) .. ".json"
        local fh = fileExists(filename) and fileOpen(filename) or fileCreate(filename)
        if fh then
            iprint(fileWrite(fh, toJSON(recording:toScalar())))
            fileFlush(fh)
            fileClose(fh)
            outputChatBox("* Saved recording to file '" .. filename .. "'", 0, 255, 0)
        end
    elseif recording and command == "seek" then
        local frameIndex = arg1 == "end" and recording:getTotalFrames() or tonumber(arg1)
        recording:setFrameIndex((frameIndex and frameIndex > 0) and frameIndex or 1)
        outputChatBox("* Set frame index to " .. tostring(recording:getFrameIndex()), 0, 255, 0)
    elseif recording and command == "play" then
        if player then
            player:destroy()
        end

        player = Player.new(recording, true)
        player:play()
    end
end)

addEventHandler("onClientRender", root, function ()
    if not recording then
        return
    end

    local frames = recording:getFrames()

    for i = 1, #frames - 1 do
        local _, _, _, _, _, _, _, _, _, _, _, _, x1, y1, z1 = unpack(frames[i])
        local _, _, _, _, _, _, _, _, _, _, _, _, x2, y2, z2 = unpack(frames[i+1])
        dxDrawLine3D(x1, y1, z1, x2, y2, z2)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function ()
    if recording then
        recording:destroy()
    end
end)
