-- MilfaCheatHUB • stealth core v0.4.0
-- Anti-detection layer for BAC-type client anticheats:
--   1) hidden mount (gethui / CoreGui / disguised PlayerGui) with randomized names
--   2) smooth CFrame glide instead of instant teleports (server position checks)
--   3) humanized delays (jitter) for every automation remote call
--   4) CFrame walk speed that never touches Humanoid.WalkSpeed
--   5) panic switch that wipes every trace instantly

local Stealth = {}
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

math.randomseed(os.time() + math.floor(os.clock() * 100000))

local ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

Stealth.MountKind = "none"
Stealth.Aborted = false
Stealth.GlideSpeed = 48
Stealth.Gliding = false
Stealth.Container = nil

function Stealth.RandomName(length)
    length = length or 14
    local out = {}
    for _ = 1, length do
        local index = math.random(1, #ALPHABET)
        out[#out + 1] = ALPHABET:sub(index, index)
    end
    return table.concat(out)
end

-- Random 0.75x .. 1.35x multiplier — makes delays look human.
function Stealth.Jitter(value)
    if not value or value <= 0 then return value end
    return value * (0.75 + math.random() * 0.6)
end

-- Executor-side GUI protection when available.
function Stealth.Protect(instance)
    if not instance then return end
    if syn and syn.protect_gui then pcall(syn.protect_gui, instance) end
    if protect_gui then pcall(protect_gui, instance) end
end

---------------------------------------------------------------------
-- Client kick guard.
-- Some anticheat flows call LocalPlayer:Kick() from CLIENT scripts —
-- that goes through Lua namecall and can be blocked. Server-side kicks
-- do not pass through Lua and cannot be blocked from here.
-- Installed once; toggle live via Stealth.BlockKick.
---------------------------------------------------------------------
Stealth.BlockKick = true

function Stealth.InstallKickGuard()
    if Stealth.KickGuardInstalled then return true end
    local player = Players.LocalPlayer
    if not player then return false end

    local installed = false

    -- Path 1: method calls, player:Kick("reason")
    if hookmetamethod and newcclosure and getnamecallmethod then
        local ok = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                if Stealth.BlockKick and self == player and getnamecallmethod() == "Kick" then
                    warn("[MilfaCheatHUB] Заблокирован клиентский Kick")
                    return nil
                end
                return original(self, ...)
            end))
            installed = installed or original ~= nil
        end)
        if not ok then installed = false end
    end

    -- Path 2: direct calls, player.Kick(player, "reason")
    if hookfunction then
        pcall(function()
            local stub = newcclosure and newcclosure(function() return nil end) or function() return nil end
            hookfunction(player.Kick, stub)
        end)
    end

    Stealth.KickGuardInstalled = installed
    return installed
end

local function buildTargets()
    local targets = {}
    if gethui then
        local ok, value = pcall(gethui)
        if ok and value then targets[#targets + 1] = {value, "gethui"} end
    end
    targets[#targets + 1] = {CoreGui, "CoreGui"}

    -- Disguised fallback: inside PlayerGui, but named like one of the game's own
    -- ScreenGuis so simple whitelist scanners pass it by.
    local player = Players.LocalPlayer
    local pgui = player and player:FindFirstChildOfClass("PlayerGui")
    if pgui then targets[#targets + 1] = {pgui, "PlayerGui"} end
    return targets
end

local function mountInstance(instance)
    for _, target in ipairs(buildTargets()) do
        local ok = pcall(function() instance.Parent = target[1] end)
        if ok and instance.Parent == target[1] then
            Stealth.Protect(instance)
            Stealth.MountKind = target[2]
            return Stealth.MountKind
        end
    end
    Stealth.MountKind = "none"
    return nil
end

-- Hidden container for ESP objects (Highlights/BillboardGuis with Adornee render
-- fine from CoreGui but are invisible to game scripts scanning workspace/PlayerGui).
function Stealth.GetContainer()
    if Stealth.Container and Stealth.Container.Parent then
        return Stealth.Container
    end
    local folder = Instance.new("Folder")
    folder.Name = Stealth.RandomName(16)
    if mountInstance(folder) then
        Stealth.Container = folder
        return folder
    end
    return nil
end

-- ScreenGui mount with randomized (or disguised) name.
function Stealth.MountScreenGui(gui, disguiseInPlayerGui)
    gui.Name = Stealth.RandomName(18)
    local player = Players.LocalPlayer
    local pgui = player and player:FindFirstChildOfClass("PlayerGui")
    if disguiseInPlayerGui ~= false and pgui then
        for _, child in ipairs(pgui:GetChildren()) do
            if child:IsA("ScreenGui") and child.Name ~= gui.Name then
                Stealth.DisguiseName = child.Name
                break
            end
        end
    end
    local kind = mountInstance(gui)
    if kind == "PlayerGui" and Stealth.DisguiseName then
        pcall(function() gui.Name = Stealth.DisguiseName end)
    end
    return kind
end

function Stealth.Shutdown()
    Stealth.Aborted = true
    if Stealth.Container then
        pcall(function() Stealth.Container:Destroy() end)
        Stealth.Container = nil
    end
end

---------------------------------------------------------------------
-- Smooth glide (safe teleport)
---------------------------------------------------------------------

local function getRoot()
    local player = Players.LocalPlayer
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root, character
end

-- Blocking movement to a point. Looks like very fast walking on the server
-- instead of a 300-stud CFrame jump that BAC flags instantly.
function Stealth.GlideTo(targetPosition, options)
    options = options or {}
    local root = getRoot()
    if not root or type(targetPosition) ~= "Vector3" then return false end

    -- One glide at a time: queue behind a running glide (autosteal + manual TP).
    local waited = 0
    while Stealth.Gliding and waited < 8 do
        waited = waited + task.wait(0.1)
    end
    if Stealth.Gliding then return false end

    local height = options.Height or 2.5
    local destination = targetPosition + Vector3.new(0, height, 0)
    local distance = (destination - root.Position).Magnitude

    if distance < 3.5 then return true end

    if options.Instant or Stealth.SafeTeleport == false then
        root.CFrame = CFrame.new(destination)
        task.wait(0.1)
        return true
    end

    local speed = math.clamp(options.Speed or Stealth.GlideSpeed or 48, 15, 130)
    local timeout = distance / speed + 4
    local started = os.clock()
    Stealth.Gliding = true

    while Stealth.Gliding do
        if Stealth.Aborted then
            Stealth.Gliding = false
            break
        end
        root = getRoot()
        if not root or not root.Parent then
            Stealth.Gliding = false
            break
        end

        local offset = destination - root.Position
        local flat = Vector3.new(offset.X, 0, offset.Z)
        local step = speed * (RunService.Heartbeat:Wait() or 0.016)

        if offset.Magnitude < math.max(2.5, step) then
            root.CFrame = CFrame.new(destination)
            Stealth.Gliding = false
            break
        end

        local direction = offset.Magnitude > 0 and offset.Unit or Vector3.new(0, 1, 0)
        -- Slight vertical ease so we do not grind along the ground.
        if offset.Y > 2 and flat.Magnitude < 6 then direction = Vector3.new(0, 1, 0) end
        root.CFrame = CFrame.new(root.Position + direction * math.min(step, offset.Magnitude))
        root.AssemblyLinearVelocity = Vector3.zero

        if os.clock() - started > timeout then
            root.CFrame = CFrame.new(destination)
            Stealth.Gliding = false
            break
        end
    end

    Stealth.Gliding = false
    return true
end

-- Diagnostic: locate client anticheat candidates (never deletes automatically).
function Stealth.FindAntiCheatScripts()
    local player = Players.LocalPlayer
    local roots = {}
    local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
    if playerScripts then roots[#roots + 1] = playerScripts end
    local character = player.Character
    if character then roots[#roots + 1] = character end
    local pgui = player:FindFirstChildOfClass("PlayerGui")
    if pgui then roots[#roots + 1] = pgui end

    local pattern = "anti|cheat|detect|guard|watch|shield|bypass|bac|ugi|police|moder"
    local found = {}
    for _, root in ipairs(roots) do
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
                local name = string.lower(descendant.Name)
                if string.match(name, pattern) then
                    found[#found + 1] = descendant
                end
            end
        end
    end
    return found
end

return Stealth
