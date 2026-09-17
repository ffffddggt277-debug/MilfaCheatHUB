-- MilfaCheatHUB • Murder Mystery 2
-- Troll pack v0.3.1 (FIXED against live scripts).
--
-- Починено/добавлено:
--   * Эмоции: ремоут это Remotes.PlayEmote (сразу под Remotes, рекурсивный
--     поиск — подтверждено W-Azeox). Пробуем :FireServer(имя) и :Fire(имя).
--     Если ремоута нет — локальная анимация (видно только тебе).
--   * Фейк-пистолет: Remotes.Gameplay.FakeGun:FireServer(true) — родной
--     предмет игры, видно ВСЕМ (подтверждено 3 скриптами).
--   * Фейк нож: метод «как делают другие» (MM2 Mods): игрушка SprayPaint
--     (Remotes.Extras.ReplicateToy) рисует ДЕКАЛЬ ножа на правой руке —
--     спрей реплицируется сервером, ВСЕ видят нож в твоей руке.
--   * Фейк глитч: персонаж «глючит» для всех — микроТП, спины, дёрганья
--     анимаций (CFrame реплицируется, другие игроки это видят).
--   * Невидимка: Remotes.Gameplay.Stealth:FireServer(true) — родная
--     невидимость игры (подтверждено 3 скриптами), risky.
--   * Фейк смерть 2 типа остались (рагдолл/призрак, локальный вид).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local Troll = {}

Troll.ActiveKind = nil      -- "Рагдолл" | "Призрак" | nil
Troll.FakeGlitch = false
Troll.Invisible = false
Troll.Debug = false

local ConfigRef = nil
local StealthRef = nil
local localPlayer = Players.LocalPlayer

local savedState = nil
local ghostParts = {}
local connections = {}
local deathSound = nil

-- Фейк глитч state
local glitchConnection = nil
-- Фейк нож state
local fakeKnifeDecals = {}

local function note(...)
    if Troll.Debug then print("[mh troll]", ...) end
end

local function findRemote(name, className)
    local found
    pcall(function() found = ReplicatedStorage:FindFirstChild(name, true) end)
    if found and (not className or found:IsA(className)) then return found end
    return nil
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
    if not character then return nil, nil, nil end
    return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------
-- Fake death type 1: ragdoll
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
    return true
end

---------------------------------------------------------------------
-- Fake death type 2: ghost
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

-- kind: nil (выключить) | "Рагдолл" | "Призрак"
function Troll.SetFakeDeath(kind)
    if kind == Troll.ActiveKind then return true end
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
-- Эмоции: Remotes.PlayEmote (рекурсивно) + локальный фолбэк
---------------------------------------------------------------------

local EMOTE_ANIMS = {
    ["Махать"] = "rbxassetid://507770239",
    ["Танец"] = "rbxassetid://507771013",
    ["Радость"] = "rbxassetid://507770677",
    ["Смех"] = "rbxassetid://507770819",
    ["Указать"] = "rbxassetid://507770453",
    ["Танец 2"] = "rbxassetid://507771955",
    ["Танец 3"] = "rbxassetid://507777268",
    ["Zen"] = "rbxassetid://507771955",
}

-- имена для игрового ремоута (список живых эмотов: xsync69/fogyhub —
-- sit, zombie, ninja, zen, floss, dab + wave/dance/cheer/laugh/point)
local GAME_EMOTE_NAMES = {
    ["Zen"] = "zen",
    ["Махать"] = "wave",
    ["Танец"] = "dance",
    ["Радость"] = "cheer",
    ["Смех"] = "laugh",
    ["Указать"] = "point",
    ["Сесть"] = "sit",
    ["Зомби"] = "zombie",
    ["Ниндзя"] = "ninja",
    ["Флосс"] = "floss",
    ["Дэб"] = "dab",
}

local emoteTrack = nil

function Troll.PlayEmote(buttonName)
    local character, humanoid = getCharacterParts()
    if not humanoid then return false, "нет персонажа" end
    if buttonName == "Сесть" then
        pcall(function() humanoid.Sit = true end)
        return true, "сел"
    end
    -- 1) родной игровой ремоут (видно всем)
    local played = false
    pcall(function()
        local playEmote = findRemote("PlayEmote", "RemoteEvent")
        local gameName = GAME_EMOTE_NAMES[buttonName]
        if playEmote and gameName then
            local fired = false
            pcall(function() playEmote:FireServer(gameName); fired = true end)
            if not fired then pcall(function() playEmote:Fire(gameName); fired = true end) end
            played = fired
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
-- SprayPaint-игрушка: база для фейка ножа (видно всем)
---------------------------------------------------------------------

local KNIFE_SPRAY_IDS = { 15093138669, 15096522641 }

-- Достаём SprayPaint в Character (сначала ReplicateToy, потом свой).
local function obtainSprayPaint()
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local character = localPlayer.Character
    local spray = character and character:FindFirstChild("SprayPaint")
    if spray then return spray end
    -- из "Toys" папки или напрямую
    local toys = backpack and (backpack:FindFirstChild("Toys") or backpack)
    spray = toys and toys:FindFirstChild("SprayPaint")
    if not spray then
        pcall(function()
            local replicateToy = findRemote("ReplicateToy", "RemoteFunction")
            if replicateToy then replicateToy:InvokeServer("SprayPaint") end
        end)
        task.wait(0.4)
        toys = backpack and (backpack:FindFirstChild("Toys") or backpack)
        spray = toys and toys:FindFirstChild("SprayPaint")
    end
    if spray and character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then pcall(function() humanoid:EquipTool(spray) end) end
        spray = character:FindFirstChild("SprayPaint")
    end
    return spray
end

-- Спрей картинки на часть. Видно всем (реплицируется сервером).
local function sprayOn(spray, imageId, normalId, size, part, cframe)
    local ok = false
    pcall(function()
        local remote = spray:FindFirstChild("Remote")
        if remote and remote:IsA("RemoteEvent") then
            remote:FireServer(imageId, normalId, size, part, cframe)
            ok = true
        end
    end)
    return ok
end

-- Фейк-нож (метод MM2 Mods «Fake Knife»): ДВА спрея на правую руку —
--   15093138669 на NormalId.Right и 15096522641 на NormalId.Left (в оригинале
--   именно так: разные грани, один size 3). Туl переносится в Character
--   ПРЯМЫМ parent (EquipTool у игрушек может сработать не на всех экзекьюторах)
--   и возвращается в рюкзак после выстрела ремоутом.
function Troll.FakeKnife()
    local character, _, root = getCharacterParts()
    if not character or not root then return false, "нет персонажа" end
    local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
    if not hand then return false, "нет руки" end
    local spray = obtainSprayPaint()
    if not spray then return false, "SprayPaint недоступна" end
    -- прямой перенос в Character (как в оригинале) + фолбэк EquipTool
    if spray.Parent ~= character then
        local moved = pcall(function() spray.Parent = character end)
        if not moved or spray.Parent ~= character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then pcall(function() humanoid:EquipTool(spray) end) end
        end
    end
    if spray.Parent ~= character then return false, "спрей не удалось взять в руку" end
    local sprayRemote = spray:FindFirstChild("Remote")
    local okCount = 0
    if sprayRemote and sprayRemote:IsA("RemoteEvent") then
        local cframe = hand.CFrame * CFrame.new(0, 0, -0.7)
        if sprayOn(spray, KNIFE_SPRAY_IDS[1], Enum.NormalId.Right, 3, hand, cframe) then
            okCount = okCount + 1
        end
        if sprayOn(spray, KNIFE_SPRAY_IDS[2], Enum.NormalId.Left, 3, hand, cframe) then
            okCount = okCount + 1
        end
    end
    -- вернуть спрей в рюкзак (не мешает играть)
    pcall(function()
        local backpack = localPlayer:FindFirstChildOfClass("Backpack")
        if backpack then spray.Parent = backpack end
    end)
    if okCount > 0 then
        return true, "фейк-нож на руке (видно всем)"
    end
    return false, "спрей не сработал"
end

---------------------------------------------------------------------
-- Фейк-бомба: локальная игрушка (для скринов/видео)
---------------------------------------------------------------------

local fakeBombModel = nil

function Troll.FakeBomb()
    local character, _, root = getCharacterParts()
    if not root then return false, "нет персонажа" end
    pcall(function()
        if fakeBombModel then fakeBombModel:Destroy(); fakeBombModel = nil end
        local bomb = Instance.new("Part")
        bomb.Size = Vector3.new(1, 1.2, 1)
        bomb.Shape = Enum.PartType.Ball
        bomb.Color = Color3.fromRGB(20, 20, 24)
        bomb.Material = Enum.Material.SmoothPlastic
        bomb.CanCollide = false
        bomb.Massless = true
        bomb.CFrame = root.CFrame * CFrame.new(0, -2.6, -1.6)
        local light = Instance.new("PointLight")
        light.Color = Color3.fromRGB(255, 60, 40)
        light.Range = 6
        light.Brightness = 2
        light.Parent = bomb
        local spark = Instance.new("ParticleEmitter")
        spark.Color = ColorSequence.new(Color3.fromRGB(255, 180, 60))
        spark.Size = NumberSequence.new(0.25, 0)
        spark.Lifetime = NumberRange.new(0.2, 0.4)
        spark.Rate = 40
        spark.Speed = NumberRange.new(1, 2)
        spark.Parent = bomb
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = bomb
        weld.Part1 = root
        weld.Parent = bomb
        bomb.Parent = character
        fakeBombModel = bomb
        task.delay(6, function()
            pcall(function()
                if fakeBombModel == bomb then bomb:Destroy(); fakeBombModel = nil end
            end)
        end)
    end)
    playOof()
    return true, "фейк-бомба у ног (6 сек, видно на твоём экране)"
end

---------------------------------------------------------------------
-- Фейк-пистолет: родной предмет игры (видно всем)
---------------------------------------------------------------------

function Troll.FakeGun()
    local ok = pcall(function()
        local fakeGun = findRemote("FakeGun", "RemoteEvent")
        if fakeGun then
            fakeGun:FireServer(true)
        else
            error("не найден")
        end
    end)
    if ok then return true, "фейк-пистолет показан (видно всем)" end
    return false, "ремоут FakeGun не найден"
end

---------------------------------------------------------------------
-- Невидимка: родной Stealth игры (видно всем)
---------------------------------------------------------------------

function Troll.SetInvisible(value)
    Troll.Invisible = value and true or false
    ConfigRef.Settings.Invisible = Troll.Invisible
    local ok = pcall(function()
        local stealthRemote = findRemote("Stealth", "RemoteEvent")
        if not stealthRemote then error("нет") end
        stealthRemote:FireServer(Troll.Invisible)
    end)
    if ok then
        return true, Troll.Invisible and "невидимка ВКЛ (родная стелс-функция)" or "невидимка ВЫКЛ"
    end
    return false, "ремоут Stealth не найден"
end

---------------------------------------------------------------------
-- Спид-глитч (то, что в популярных хабах зовут Glitch / Slide Glitch):
-- CFrame-сдвиг по направлению бега каждый Heartbeat (fogyhub: force 45,
-- CGS: velocity*1.48). Персонаж визуально «глится» — сдвиг реплицируется.
-- ВАЖНО: работает ТОЛЬКО когда персонаж реально бежит (MoveDirection > 0).
---------------------------------------------------------------------

function Troll.SetFakeGlitch(value)
    Troll.FakeGlitch = value and true or false
    ConfigRef.Settings.FakeGlitch = Troll.FakeGlitch
    if glitchConnection then
        pcall(function() glitchConnection:Disconnect() end)
        glitchConnection = nil
    end
    if not value then
        return true, "спид-глитч ВЫКЛ"
    end
    glitchConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not Troll.FakeGlitch then return end
        pcall(function()
            local character = localPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root and humanoid and humanoid.Health > 0 and humanoid.MoveDirection.Magnitude > 0 then
                local force = ConfigRef.Settings.GlitchForce or 40
                local slide = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z).Unit
                root.CFrame = root.CFrame + (slide * (force * deltaTime))
            end
        end)
    end)
    return true, "спид-глитч ВКЛ (глитч-бег, видно всем)"
end

---------------------------------------------------------------------
-- Спид-глитч (см. SetFakeGlitch): отключение в Shutdown и при выгрузке
---------------------------------------------------------------------

function Troll.Configure(config, stealth)
    ConfigRef = config
    StealthRef = stealth
    Troll.Debug = config.Settings.DebugLogs == true
    connections[#connections + 1] = localPlayer.CharacterAdded:Connect(function()
        if Troll.ActiveKind then
            Troll.ActiveKind = nil
            savedState = nil
            ghostParts = {}
            fakeBombModel = nil
            note("fake death cleared by respawn")
        end
    end)
end

function Troll.Shutdown()
    pcall(function() Troll.SetFakeDeath(nil) end)
    Troll.ActiveKind = nil
    if Troll.FakeGlitch then pcall(function() Troll.SetFakeGlitch(false) end) end
    if emoteTrack then pcall(function() emoteTrack:Stop(0.1) end) emoteTrack = nil end
    if deathSound then pcall(function() deathSound:Destroy() end) deathSound = nil end
    pcall(function() if fakeBombModel then fakeBombModel:Destroy(); fakeBombModel = nil end end)
    pcall(function() if fakeKnifeDecals then for _, d in ipairs(fakeKnifeDecals) do d:Destroy() end end end)
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
end

return Troll
