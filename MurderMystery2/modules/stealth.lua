-- MilfaCheatHUB • stealth core v0.6.1 (MUTE doctrine)
-- Field evidence timeline:
--   v0.4.0: crash BEFORE any GUI/hooks — STILL kicked in ~5s. The only traces
--           were console output (LogService IS readable by game scripts via
--           GetLogHistory) and getgenv keys carrying the word "Cheat".
--   v0.5.0: hooks/getgc masking -> BAC-2516 (tampering detector)
--   v0.6.0: plain PlayerGui ScreenGui + zero hooks -> BAC-7517
--   Research (Krexel/TFN/Madara, same PlaceId): BAC runs a ~5s scan cycle
--   (IntegrityHeartbeat); BAC-7517 = hook/RemoteSpy-like detection; working
--   hubs mount their GUI in gethui()/CoreGui — NOT in PlayerGui.
-- So the stealth layer now means:
--   1) hidden mount first: gethui() -> CoreGui, PlayerGui ONLY as a last
--      resort and then with a camouflage name cloned from an existing game gui
--   2) silent operation: Stealth.Note() prints ONLY when DebugLogs is on
--   3) ESP container in workspace under a RANDOM name
--   4) smooth CFrame glide instead of instant teleports (server position checks)
--   5) humanized delays (jitter) for every automation remote call
--   6) CFrame walk speed that never touches Humanoid.WalkSpeed
--   7) panic switch that wipes every trace instantly
--   NO hooks are installed here. Aggressive BAC counters live in anticheat.lua
--   and are strictly opt-in (Settings.BacAutoBypass).

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
Stealth.GuiMount = "Hidden" -- "Hidden" (gethui/CoreGui, невидимы игровым сканерам) | "PlayerGui" | "Auto"
Stealth.PublicName = nil    -- камуфляж-имя для PlayerGui-фолбэка (клон имени игрового GUI)
Stealth.Debug = false       -- включается из Config.Settings.DebugLogs

-- ЕДИНСТВЕННАЯ точка печати. Молчит, если Debug выключен: каждый print/warn
-- попадает в LogService, который читается игровыми скриптами.
function Stealth.Note(...)
    if not Stealth.Debug then return end
    print("[mh]", ...)
end

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
-- Client kick guard moved to anticheat.lua (v0.5.0): single __namecall
-- hook covers Kick + HttpGet probe masking. Toggle: Stealth.BlockKick.
---------------------------------------------------------------------
Stealth.BlockKick = false -- v0.6.0 GHOST: kick-guard ставится только в агрессивном режиме

local function getPlayerGui()
    local player = Players.LocalPlayer
    return player and player:FindFirstChildOfClass("PlayerGui")
end

local function hiddenTargets()
    local targets = {}
    if gethui then
        local ok, value = pcall(gethui)
        if ok and value then targets[#targets + 1] = {value, "gethui"} end
    end
    targets[#targets + 1] = {CoreGui, "CoreGui"}
    return targets
end

-- Mount order follows Stealth.GuiMount. Hidden (gethui/CoreGui) is the default:
-- game scripts cannot enumerate those roots at all, so no scanner ever sees the
-- GUI. PlayerGui is a LAST resort: game scripts enumerate it freely, so there we
-- camouflage by cloning the name of an existing game ScreenGui.
local function buildTargets()
    local targets = {}
    local mode = Stealth.GuiMount or "Hidden"

    if mode == "PlayerGui" then
        local pgui = getPlayerGui()
        if pgui then targets[#targets + 1] = {pgui, "PlayerGui"} end
        return targets
    end

    -- Hidden / Auto: hidden roots first.
    for _, target in ipairs(hiddenTargets()) do
        targets[#targets + 1] = target
    end

    local pgui = getPlayerGui()
    if pgui then targets[#targets + 1] = {pgui, "PlayerGui"} end
    return targets
end

-- PlayerGui fallback: clone the name of an existing game ScreenGui so a
-- name-whitelist scan sees a familiar entry. Generic fallback otherwise.
local function camouflageName()
    local pgui = getPlayerGui()
    if pgui then
        for _, child in ipairs(pgui:GetChildren()) do
            if child:IsA("ScreenGui") and child.Name and #child.Name > 0 then
                return child.Name
            end
        end
    end
    return "ScreenOverlay"
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

-- Hidden container for ESP objects. Workspace folder under a RANDOM name
-- (no "ESP"-like signature; folder is created only when ESP is enabled).
function Stealth.GetContainer()
    if Stealth.Container and Stealth.Container.Parent then
        return Stealth.Container
    end

    local workspace = game:GetService("Workspace")
    local folder = Instance.new("Folder")
    folder.Name = Stealth.RandomName(12)
    local ok = pcall(function() folder.Parent = workspace end)
    if ok and folder.Parent == workspace then
        Stealth.Container = folder
        Stealth.ContainerKind = "Workspace"
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = Stealth.RandomName(16)
    if mountInstance(folder) then
        Stealth.Container = folder
        Stealth.ContainerKind = Stealth.MountKind
        return folder
    end
    return nil
end

-- ScreenGui mount. Hidden roots get a random name (they are invisible to game
-- scripts anyway). PlayerGui fallback gets a camouflage name cloned from an
-- existing game ScreenGui (whitelist scanners see a familiar entry).
function Stealth.MountScreenGui(gui)
    gui.Name = Stealth.RandomName(18)
    local kind = mountInstance(gui)
    if kind == "PlayerGui" then
        pcall(function() gui.Name = camouflageName() end)
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
