-- MilfaCheatHUB • Murder Mystery 2
-- Troll pack v0.2.0: fake death (2 types), emotes/animations,
-- fake gun and toy bomb (game's own troll remotes).
--
-- Fake death types are CLIENT-SIDE visuals (MM2 death is server-authoritative,
-- nobody can fake a real death):
--   Type 1 "Рагдолл": character lies down locally (physics state + rotated
--            root), classic "oof" sound, controls frozen. Good for screenshots
--            and pranking friends on your screen.
--   Type 2 "Призрак": own character becomes fully transparent locally —
--            you walk as an invisible ghost (still alive, can watch the
--            murderer work; combine with ESP).
-- Emotes: game's own Remotes.Misc.PlayEmote if present, otherwise a local
-- Animator plays classic Roblox emote animations.
-- FakeGun/FakeBomb: Remotes.Gameplay.FakeGun + Remotes.Extras.ReplicateToy
-- ("FakeBomb") — the game's built-in troll items (see FINDINGS_MM2.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Troll = {}

Troll.ActiveKind = nil   -- "Рагдолл" | "Призрак" | nil
Troll.Debug = false

local ConfigRef = nil
local StealthRef = nil
local localPlayer = Players.LocalPlayer

local savedState = nil   -- snapshot for restore
local ghostParts = {}    -- [part] = original Transparency
local connections = {}
local deathSound = nil

local function note(...)
    if Troll.Debug then print("[mh troll]", ...) end
end

local function playOof()
    pcall(function()
        if not deathSound then
            deathSound = Instance.new("Sound")
            deathSound.SoundId = "rbxasset://sounds/uuhhh.mp3"
            deathSound.Volume = 0.7
            deathSound.Parent = SoundService
        end
        deathSound:Play()
    end)
end

local function getCharacterParts()
    local character = localPlayer and localPlayer.Character
    if not character then return nil, nil end
    return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------
-- Fake death type 1: ragdoll (local lie-down)
---------------------------------------------------------------------

local function enterRagdoll()
    local character, humanoid, root = getCharacterParts()
    if not humanoid or not root then return false end
    savedState = {
        WalkSpeed = humanoid.WalkSpeed,
        JumpPower = humanoid.JumpPower,
        PlatformStand = humanoid.PlatformStand,
        AutoRotate = humanoid.AutoRotate,
    }
    pcall(function()
        humanoid.AutoRotate = false
        humanoid.PlatformStand = true
        humanoid.WalkSpeed = 0
        root.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(82))
    end)
    playOof()
    note("fake death: ragdoll on")
    return true
end

---------------------------------------------------------------------
-- Fake death type 2: ghost (local invisibility)
---------------------------------------------------------------------

local function enterGhost()
    local character = localPlayer and localPlayer.Character
    if not character then return false end
    ghostParts = {}
    pcall(function()
        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") then
                ghostParts[descendant] = descendant.Transparency
                descendant.Transparency = 1
                descendant.LocalTransparencyModifier = 1
            elseif descendant:IsA("Decal") then
                ghostParts[descendant] = descendant.Transparency
                descendant.Transparency = 1
            end
        end
    end)
    playOof()
    note("fake death: ghost on")
    return true
end

local function restoreRagdoll()
    local character, humanoid, root = getCharacterParts()
    if humanoid and savedState then
        pcall(function()
            humanoid.PlatformStand = savedState.PlatformStand
            humanoid.AutoRotate = savedState.AutoRotate
            humanoid.WalkSpeed = savedState.WalkSpeed
            humanoid.JumpPower = savedState.JumpPower
        end)
    end
    -- выпрямить персонажа, если лежит
    if root and root.Parent then
        pcall(function()
            local pos = root.Position
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
    savedState = nil
end

local function restoreGhost()
    for descendant, transparency in pairs(ghostParts) do
        pcall(function()
            if descendant.Parent then
                descendant.Transparency = transparency
                if descendant:IsA("BasePart") then
                    descendant.LocalTransparencyModifier = 0
                end
            end
        end)
    end
    ghostParts = {}
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

-- kind: nil (выключить) | "Рагдолл" | "Призрак"
function Troll.SetFakeDeath(kind)
    if kind == Troll.ActiveKind then return true end
    -- сначала всегда восстановиться
    if Troll.ActiveKind == "Рагдолл" then restoreRagdoll() end
    if Troll.ActiveKind == "Призрак" then restoreGhost() end
    Troll.ActiveKind = nil
    if kind == "Рагдолл" then
        if enterRagdoll() then Troll.ActiveKind = kind end
    elseif kind == "Призрак" then
        if enterGhost() then Troll.ActiveKind = kind end
    end
    return true
end

function Troll.CycleFakeDeath()
    -- выключено -> рагдолл -> призрак -> выключено
    if Troll.ActiveKind == nil then
        Troll.SetFakeDeath("Рагдолл")
        return "фейк-смерть: РАГДОЛЛ"
    elseif Troll.ActiveKind == "Рагдолл" then
        Troll.SetFakeDeath("Призрак")
        return "фейк-смерть: ПРИЗРАК"
    else
        Troll.SetFakeDeath(nil)
        return "фейк-смерть выключена"
    end
end

---------------------------------------------------------------------
-- Emotes: game remote first, local animation fallback.
---------------------------------------------------------------------

local EMOTE_ANIMS = {
    ["Махать"] = "rbxassetid://507770239",
    ["Танец"] = "rbxassetid://507771013",
    ["Радость"] = "rbxassetid://507770677",
    ["Смех"] = "rbxassetid://507770819",
    ["Указать"] = "rbxassetid://507770453",
    ["Танец 2"] = "rbxassetid://507771955",
    ["Танец 3"] = "rbxassetid://507777268",
}

-- соответствие кнопок -> имена эмоций игрового ремоута
local GAME_EMOTE_NAMES = {
    ["Zen"] = "zen",
    ["Махать"] = "wave",
    ["Танец"] = "dance",
    ["Радость"] = "cheer",
    ["Смех"] = "laugh",
    ["Указать"] = "point",
}

local emoteTrack = nil

function Troll.PlayEmote(buttonName)
    local humanoid = localPlayer and localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false, "нет персонажа" end
    if buttonName == "Сесть" then
        pcall(function() humanoid.Sit = true end)
        return true, "сел"
    end
    -- 1) родной игровой ремоут (видно всем)
    local played = false
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local misc = remotes and remotes:FindFirstChild("Misc")
        local playEmote = misc and misc:FindFirstChild("PlayEmote")
        if playEmote and GAME_EMOTE_NAMES[buttonName] then
            playEmote:FireServer(GAME_EMOTE_NAMES[buttonName])
            played = true
        end
    end)
    if played then
        return true, "эмоция: " .. buttonName
    end
    -- 2) локальная анимация (видно только тебе)
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false, "нет Animator" end
    local animId = EMOTE_ANIMS[buttonName]
    if not animId then return false, "неизвестная эмоция" end
    pcall(function()
        if emoteTrack then emoteTrack:Stop(0.2) end
        local animation = Instance.new("Animation")
        animation.AnimationId = animId
        emoteTrack = animator:LoadAnimation(animation)
        emoteTrack:Play()
    end)
    return true, "локальная эмоция: " .. buttonName
end

---------------------------------------------------------------------
-- Game's own troll items
---------------------------------------------------------------------

function Troll.FakeGun()
    local ok = pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local gameplay = remotes and remotes:FindFirstChild("Gameplay")
        local fakeGun = gameplay and gameplay:FindFirstChild("FakeGun")
        if fakeGun then fakeGun:FireServer(true) end
    end)
    if ok then return true, "фейк-пистолет показан" end
    return false, "ремоут FakeGun не найден"
end

function Troll.FakeBomb()
    local ok = pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local extras = remotes and remotes:FindFirstChild("Extras")
        local replicateToy = extras and extras:FindFirstChild("ReplicateToy")
        if replicateToy then replicateToy:InvokeServer("FakeBomb") end
    end)
    if ok then return true, "фейк-бомба выдана" end
    return false, "ремоут ReplicateToy не найден"
end

---------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------

function Troll.Configure(config, stealth)
    ConfigRef = config
    StealthRef = stealth
    Troll.Debug = config.Settings.DebugLogs == true
    -- смерть/респавн снимает любые локальные эффекты
    connections[#connections + 1] = localPlayer.CharacterAdded:Connect(function()
        if Troll.ActiveKind then
            Troll.ActiveKind = nil
            savedState = nil
            ghostParts = {}
            note("fake death cleared by respawn")
        end
    end)
end

function Troll.Shutdown()
    pcall(function() Troll.SetFakeDeath(nil) end)
    Troll.ActiveKind = nil
    if emoteTrack then pcall(function() emoteTrack:Stop(0.1) end) emoteTrack = nil end
    if deathSound then pcall(function() deathSound:Destroy() end) deathSound = nil end
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
end

return Troll
