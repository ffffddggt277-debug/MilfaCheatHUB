-- MilfaCheatHUB • Murder Mystery 2
-- Combat v0.4.0 (FIXED against live scripts: KittyHub/R3TH/StyearX/MM2 Mods).
--
-- Причины красных кругов v0.2.0 и как теперь:
--   * удар ножом: ремоуты Events.KnifeStabbed/HandleTouched НЕ наносят урон в
--     актуальной MM2. Рабочий путь (подтверждён 3 скриптами):
--     Knife.Stab:FireServer("Down") и через ~0.06с ("Up") — пара вниз/вверх;
--   * убийство на дистанции: сервер засчитывает касание ножа, поэтому все
--     рабочие ауры делают ТП-стаб: мигнуть к цели (2.5 стада за спину),
--     stab, мигнуть обратно. Сделали режим по умолчанию;
--   * выстрел шерифа: Gun.KnifeLocal.CreateBeam.RemoteFunction(1, pos, тег);
--     сервер сам проверяет попадание. Теги: "AH2" (новые), "AH" (старые);
--     фолбэк Gun.KnifeServer.ShootGun(1, 0, "AH");
--   * бросок ножа: Knife.Events.KnifeThrown:FireServer(fromCF, toCF), где
--     fromCF — ОРИЕНТИРОВАННЫЙ (CFrame.new(from, to)), иначе нож летит мимо;
--   * всё завязано на роли — починкой roles.lua они снова живые.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Combat = {}

Combat.AuraEnabled = false
Combat.SheriffAutoEnabled = false
Combat.DodgeEnabled = false
Combat.LastKillName = "—"
Combat.KillCount = 0
Combat.Status = "выключено"
Combat.Debug = false
Combat.OnNotify = nil

local ConfigRef = nil
local RolesRef = nil
local StealthRef = nil

local localPlayer = Players.LocalPlayer
local auraRunning = false
local sheriffRunning = false
local dodgeRunning = false
local lastShotAt = 0
local lastThrowAt = 0
local lastDodgeAt = 0
local dodgeConnections = {}
local watchedProjectiles = {}

local SHOT_TAGS = { "AH2", "AH" }
local shotTagIndex = 1

local function note(...)
    if Combat.Debug then print("[mh combat]", ...) end
end

local function jitter(value)
    if ConfigRef and ConfigRef.Settings.HumanizeDelays then
        return value * (0.8 + math.random() * 0.5)
    end
    return value
end

local function getCharacterParts()
    local character = localPlayer.Character
    if not character then return nil, nil end
    return character, character:FindFirstChild("HumanoidRootPart")
end

-- Найти тул (в руке или рюкзаке), при необходимости экипировать.
local function findTool(character, name)
    if character and character:FindFirstChild(name) then
        return character:FindFirstChild(name)
    end
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local stowed = backpack and backpack:FindFirstChild(name)
    if stowed and character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then pcall(function() humanoid:EquipTool(stowed) end) end
        return character:FindFirstChild(name)
    end
    return stowed
end

local function aliveTargetRoot(targetPlayer)
    local character = targetPlayer and targetPlayer.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and root then
        return root
    end
    return nil
end

-- Фолбэк роли по тулу в Character (реплицируется всем): если детект ролей
-- мигнул/опоздал, а нож/пистолет у нас В РУКЕ — роль очевидна. Это снимает
-- главный симптом «половина не работает» — жёсткий гейт по протухшему роли.
local function holdingTool(name)
    local character = localPlayer.Character
    return character and character:FindFirstChild(name) ~= nil
end

local function amMurderer()
    if RolesRef.LocalIsMurderer() then return true end
    return holdingTool("Knife") == true
end

local function amSheriff()
    if RolesRef.LocalIsSheriff() then return true end
    return holdingTool("Gun") == true
end

-- Прямая видимость между корнями (исключаем обе модели).
local function hasLineOfSight(myRoot, targetRoot, targetCharacter)
    local origin = myRoot.Position
    local direction = targetRoot.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    if localPlayer.Character then exclude[#exclude + 1] = localPlayer.Character end
    if targetCharacter then exclude[#exclude + 1] = targetCharacter end
    params.FilterDescendantsInstances = exclude
    local hit = workspace:Raycast(origin, direction, params)
    return hit == nil
end

local function nearbyTargets(radius, maxCount)
    local _, myRoot = getCharacterParts()
    if not myRoot then return {} end
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and RolesRef.IsAlive(player.Name) then
            local root = aliveTargetRoot(player)
            if root and (root.Position - myRoot.Position).Magnitude <= radius then
                list[#list + 1] = { Player = player, Root = root }
                if maxCount and #list >= maxCount then break end
            end
        end
    end
    return list
end

---------------------------------------------------------------------
-- Нож: удар (Down/Up пара) и ТП-стаб
---------------------------------------------------------------------

-- Рабочий удар: Stab("Down") + отложенный "Up" (без него тул залипает),
-- плюс страховочный комбо StyearX: KnifeStabbed + HandleTouched(корень цели)
-- — свежие хабы шлют ОБА канала, сервер засчитывает любой.
local function stabWith(knife, targetRoot)
    local ok = false
    pcall(function()
        local stab = knife:FindFirstChild("Stab")
        if stab and stab:IsA("RemoteEvent") then
            stab:FireServer("Down")
            ok = true
            task.delay(0.07, function()
                pcall(function() stab:FireServer("Up") end)
            end)
        end
        -- страховка (StyearX KnifeAura/KillAll): пара KnifeStabbed+HandleTouched
        local events = knife:FindFirstChild("Events")
        if events then
            local stabbed = events:FindFirstChild("KnifeStabbed")
            if stabbed and stabbed:IsA("RemoteEvent") then
                pcall(function() stabbed:FireServer() end)
                ok = true
                local touched = events:FindFirstChild("HandleTouched")
                if touched and touched:IsA("RemoteEvent") and targetRoot then
                    pcall(function() touched:FireServer(targetRoot) end)
                end
            end
        end
    end)
    return ok
end

-- ТП-стаб: мигнуть за спину цели, удар, вернуть то же тело обратно.
local function tpStabTarget(knife, targetRoot, targetCharacter)
    local _, myRoot = getCharacterParts()
    if not myRoot then return false end
    local origin = myRoot.CFrame
    local moved = false
    local dist = (targetRoot.Position - myRoot.Position).Magnitude
    if dist > 6 then
        myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 2.5)
        moved = true
        task.wait(jitter(0.08))
    end
    local freshKnife = localPlayer.Character and localPlayer.Character:FindFirstChild("Knife") or knife
    local hit = stabWith(freshKnife, targetRoot)
    -- физический тач-фолбэк для экзекьюторов с firetouchinterest
    pcall(function()
        local handle = freshKnife and (freshKnife:FindFirstChild("Handle") or freshKnife:FindFirstChildWhichIsA("BasePart"))
        if handle and type(firetouchinterest) == "function" then
            firetouchinterest(handle, targetRoot, 0)
            firetouchinterest(handle, targetRoot, 1)
        end
    end)
    task.wait(jitter(0.1))
    if moved and myRoot.Parent then
        myRoot.CFrame = origin
    end
    return hit
end

---------------------------------------------------------------------
-- Выстрел шерифа (CreateBeam + ShootGun фолбэк, теги AH2/AH)
---------------------------------------------------------------------

local function shotRemote(gun)
    local knifeLocal = gun:FindFirstChild("KnifeLocal")
    local createBeam = knifeLocal and knifeLocal:FindFirstChild("CreateBeam")
    if createBeam then
        local rf = createBeam:FindFirstChildOfClass("RemoteFunction")
        if rf then return rf end
        if createBeam:IsA("RemoteFunction") then return createBeam end
    end
    -- фолбэк: старый путь R3TH — Gun.KnifeServer.ShootGun
    local knifeServer = gun:FindFirstChild("KnifeServer")
    local shootGun = knifeServer and knifeServer:FindFirstChild("ShootGun")
    if shootGun and shootGun:IsA("RemoteFunction") then return shootGun end
    local any = gun:FindFirstChildWhichIsA("RemoteFunction", true)
    return any
end

local function fireShot(gun, targetPosition)
    local remote = shotRemote(gun)
    if not remote then return false, "ремоут выстрела не найден" end
    local isShootGun = remote.Parent and remote.Parent.Name == "ShootGun"
    local ok = pcall(function()
        if isShootGun then
            remote:InvokeServer(1, 0, SHOT_TAGS[shotTagIndex])
        else
            remote:InvokeServer(1, targetPosition, SHOT_TAGS[shotTagIndex])
        end
    end)
    if not ok then
        -- переключаем тег: сервер принял другой формат
        shotTagIndex = (shotTagIndex % #SHOT_TAGS) + 1
        pcall(function()
            if isShootGun then
                remote:InvokeServer(1, 0, SHOT_TAGS[shotTagIndex])
            else
                remote:InvokeServer(1, targetPosition, SHOT_TAGS[shotTagIndex])
            end
        end)
    end
    return true
end

---------------------------------------------------------------------
-- SheriffAim: тихий выстрел в маньяка (кнопка/клавиша/авто-цикл)
---------------------------------------------------------------------

local function trySheriffShot()
    local settings = ConfigRef.Settings
    if not amSheriff() then
        Combat.Status = "нужна роль ШЕРИФ/ГЕРОЙ"
        return false, "нужна роль ШЕРИФ/ГЕРОЙ"
    end
    local character, myRoot = getCharacterParts()
    local gun = character and findTool(character, "Gun")
    if not gun then
        Combat.Status = "пистолет не найден"
        return false, "пистолет не найден"
    end
    if not myRoot then
        return false, "нет персонажа"
    end
    -- KittyHub: сервер отклоняет выстрел из пистолета, который ещё не в руке.
    -- Ждём экип до 0.35с (первый выстрел после подбора — типичный «не работает»).
    if gun.Parent ~= character then
        local began = os.clock()
        while gun.Parent ~= character and os.clock() - began < 0.35 do
            task.wait(0.05)
            character = localPlayer.Character
            if not character then return false, "нет персонажа" end
        end
        if gun.Parent ~= character then
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local backpack = localPlayer:FindFirstChildOfClass("Backpack")
            local stowed = backpack and backpack:FindFirstChild("Gun")
            if stowed and humanoid then
                pcall(function() humanoid:EquipTool(stowed) end)
                gun = character:FindFirstChild("Gun") or stowed
            end
        end
        if gun and gun.Parent ~= character then
            Combat.Status = "пистолет не экипировался"
            return false, "пистолет не экипировался"
        end
    end

    local murderers = RolesRef.FindByRole("Murderer")
    if #murderers == 0 then
        return false, "маньяк неизвестен — роли не определены"
    end
    for _, name in ipairs(murderers) do
        local target = Players:FindFirstChild(name)
        local root = target and aliveTargetRoot(target)
        if root and target and target.Character then
            local dist = (root.Position - myRoot.Position).Magnitude
            if dist <= (settings.SheriffRange or 300) then
                if not hasLineOfSight(myRoot, root, target.Character) then
                    Combat.Status = "маньяк за препятствием"
                    return false, "маньяк за препятствием"
                end
                local ok = fireShot(gun, root.Position)
                if ok then
                    Combat.LastKillName = name
                    Combat.KillCount = Combat.KillCount + 1
                    Combat.Status = "выстрел: " .. name
                    if Combat.OnNotify then pcall(Combat.OnNotify, "Выстрел в маньяка: " .. name) end
                    lastShotAt = os.clock()
                    return true, "выстрел в " .. name
                end
                return false, "ремоут выстрела не сработал"
            end
        end
    end
    return false, "маньяк вне дистанции"
end

local function sheriffLoop()
    while sheriffRunning do
        local ok, err = pcall(trySheriffShot)
        if not ok then note("sheriff: " .. tostring(err)) end
        task.wait(jitter(1.2))
    end
end

---------------------------------------------------------------------
-- Аура маньяка: ТП-стаб по ближайшим
---------------------------------------------------------------------

local function auraLoop()
    while auraRunning do
        local settings = ConfigRef.Settings
        if not amMurderer() then
            Combat.Status = "нужна роль МАНЬЯК"
        else
            local character = localPlayer.Character
            local knife = character and findTool(character, "Knife")
            if not knife then
                Combat.Status = "нож не найден"
            else
                local targets = nearbyTargets(settings.AuraRadius or 14, 2)
                if #targets == 0 then
                    Combat.Status = "целей рядом нет"
                else
                    for _, target in ipairs(targets) do
                        tpStabTarget(knife, target.Root, target.Player.Character)
                        -- честный счёт: убийство = цель реально умерла (Health),
                        -- а не «мы отправили удар»
                        task.wait(jitter(0.3))
                        if not aliveTargetRoot(target.Player) then
                            Combat.KillCount = Combat.KillCount + 1
                            Combat.LastKillName = target.Player.Name
                            Combat.Status = "убит: " .. target.Player.Name
                        else
                            Combat.Status = "удар: " .. target.Player.Name
                        end
                        task.wait(jitter(math.max(0.5, settings.AuraDelay or 1.0)))
                    end
                end
            end
        end
        task.wait(jitter(0.4))
    end
end

---------------------------------------------------------------------
-- KILL ALL: маньяк — ТП-стаб всех в радиусе; шериф — очередь выстрелов
---------------------------------------------------------------------

function Combat.KillAll()
    if not amMurderer() and not amSheriff() then
        return false, "нужна роль МАНЬЯК или ШЕРИФ"
    end
    local radius = (ConfigRef.Settings.KillAllRadius or 60)
    local targets = nearbyTargets(radius, 12)
    if #targets == 0 then
        return false, "никого в радиусе " .. tostring(radius)
    end
    local isMurderer = amMurderer()
    if isMurderer then
        local character = localPlayer.Character
        local knife = character and findTool(character, "Knife")
        if not knife then return false, "нож не найден" end
        task.spawn(function()
            for _, target in ipairs(targets) do
                local fresh = localPlayer.Character
                local freshKnife = fresh and findTool(fresh, "Knife")
                if freshKnife then
                    tpStabTarget(freshKnife, target.Root, target.Player.Character)
                    task.wait(jitter(0.3))
                    if not aliveTargetRoot(target.Player) then
                        Combat.KillCount = Combat.KillCount + 1
                        Combat.LastKillName = target.Player.Name
                    end
                end
                task.wait(jitter(0.45))
            end
            Combat.Status = "kill all: " .. tostring(#targets) .. " целей"
        end)
    else
        local character = localPlayer.Character
        local gun = character and findTool(character, "Gun")
        if not gun then return false, "пистолет не найден" end
        task.spawn(function()
            for _, target in ipairs(targets) do
                local freshChar = localPlayer.Character
                local freshGun = freshChar and findTool(freshChar, "Gun")
                if freshGun and freshGun.Parent == freshChar then
                    fireShot(freshGun, target.Root.Position)
                    task.wait(jitter(0.35))
                    if not aliveTargetRoot(target.Player) then
                        Combat.KillCount = Combat.KillCount + 1
                        Combat.LastKillName = target.Player.Name
                    end
                end
                task.wait(jitter(0.25))
            end
            Combat.Status = "kill all: " .. tostring(#targets) .. " выстрелов"
        end)
    end
    return true, "целей: " .. tostring(#targets)
end

---------------------------------------------------------------------
-- MurderAim: тихий бросок ножа в шерифа (ориентированный CFrame)
---------------------------------------------------------------------

local function throwKnifeAt(knife, fromRoot, targetPosition)
    local character = localPlayer.Character
    local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) or fromRoot
    local from = hand.CFrame
    if (targetPosition - hand.Position).Magnitude > 0.5 then
        from = CFrame.new(hand.Position, targetPosition)
    end
    local ok = pcall(function()
        local events = knife:FindFirstChild("Events")
        local thrown = events and events:FindFirstChild("KnifeThrown")
        if thrown and thrown:IsA("RemoteEvent") then
            -- KittyHub: второй аргумент — ОРИЕНТИРОВАННЫЙ CFrame (поза from).
            -- Голый CFrame.new(point) разворачивает нож по мировой оси — он летит
            -- мимо и сервер отклоняет попадание. Именно это ломало бросок.
            thrown:FireServer(from, CFrame.new(targetPosition) * (from - from.Position))
            return
        end
        local throw = knife:FindFirstChild("Throw")
        if throw and throw:IsA("RemoteEvent") then
            throw:FireServer(from, CFrame.new(targetPosition) * (from - from.Position))
        else
            error("нет ремоута броска")
        end
    end)
    return ok
end

function Combat.MurderAimThrow()
    local settings = ConfigRef.Settings
    if not amMurderer() then
        Combat.Status = "нужна роль МАНЬЯК"
        return false, "нужна роль МАНЬЯК"
    end
    local character, myRoot = getCharacterParts()
    local knife = character and findTool(character, "Knife")
    if not knife then
        Combat.Status = "нож не найден"
        return false, "нож не найден"
    end
    if not myRoot then
        return false, "нет персонажа"
    end
    local sheriffs = RolesRef.FindByRole("Sheriff")
    if #sheriffs == 0 then
        return false, "шериф неизвестен — роли не определены"
    end
    local target = Players:FindFirstChild(sheriffs[1])
    local root = target and aliveTargetRoot(target)
    if not root or not (target and target.Character) then
        return false, "шериф недоступен"
    end
    local dist = (root.Position - myRoot.Position).Magnitude
    if dist > (settings.AimMaxDistance or 260) then
        return false, string.format("далеко: %.0fм", dist)
    end
    if os.clock() - lastThrowAt < 1.0 then
        return false, "нож ещё летит (перезарядка)"
    end
    if not hasLineOfSight(myRoot, root, target.Character) then
        Combat.Status = "шериф за препятствием"
        return false, "шериф за препятствием"
    end

    local ok = throwKnifeAt(knife, myRoot, root.Position)
    lastThrowAt = os.clock()
    if not ok then
        Combat.Status = "ремоут броска не найден"
        return false, "ремоут броска не найден"
    end
    Combat.LastKillName = sheriffs[1]
    Combat.Status = "бросок ножа: " .. sheriffs[1]
    if Combat.OnNotify then pcall(Combat.OnNotify, "Бросок ножа в шерифа: " .. sheriffs[1]) end
    return true, "бросок в " .. sheriffs[1]
end

---------------------------------------------------------------------
-- SheriffAimShot: то же, но по кнопке/клавише (без цикла)
---------------------------------------------------------------------

function Combat.SheriffAimShot()
    return trySheriffShot()
end

---------------------------------------------------------------------
-- Бросок ножа в точку прицела
---------------------------------------------------------------------

function Combat.ThrowAtAim()
    if not amMurderer() then
        return false, "нужна роль МАНЬЯК"
    end
    local character, myRoot = getCharacterParts()
    local knife = character and findTool(character, "Knife")
    if not knife then return false, "нож не найден" end
    if not myRoot then return false, "нет персонажа" end
    if os.clock() - lastThrowAt < 1.0 then
        return false, "нож ещё летит (перезарядка)"
    end
    local camera = workspace.CurrentCamera
    if not camera then return false, "нет камеры" end
    local targetPoint = nil
    pcall(function()
        local mouse = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        if localPlayer.Character then params.FilterDescendantsInstances = { localPlayer.Character } end
        local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
        targetPoint = result and result.Position or (ray.Origin + ray.Direction * 200)
    end)
    if not targetPoint then
        targetPoint = (camera.CFrame * CFrame.new(0, 0, -150)).Position
    end
    local ok = throwKnifeAt(knife, myRoot, targetPoint)
    lastThrowAt = os.clock()
    if not ok then return false, "ремоут броска не найден" end
    Combat.Status = "бросок в прицел"
    return true, "бросок выполнен"
end

---------------------------------------------------------------------
-- AutoDodge: резкий стрейф от летящих ножей и стрелков в упор
---------------------------------------------------------------------

local DODGE_NAMES = { "knife", "throw", "projectile", "bullet" }

local function isDodgeName(name)
    local lowered = string.lower(name)
    for _, fragment in ipairs(DODGE_NAMES) do
        if string.find(lowered, fragment, 1, true) then return true end
    end
    return false
end

local function trackProjectile(part)
    if watchedProjectiles[part] then return end
    watchedProjectiles[part] = os.clock() + 4
end

local function dodgeNow(myRoot, threatPosition)
    local settings = ConfigRef.Settings
    local power = settings.DodgePower or 12
    local base = threatPosition - myRoot.Position
    base = Vector3.new(base.X, 0, base.Z)
    if base.Magnitude < 0.5 then base = myRoot.CFrame.LookVector end
    base = base.Unit
    local perp = Vector3.new(-base.Z, 0, base.X)
    if math.random() < 0.5 then perp = -perp end
    local target = myRoot.Position + perp * power - base * (power * 0.2) + Vector3.new(0, 2, 0)
    myRoot.CFrame = CFrame.lookAt(target, target - base)
    lastDodgeAt = os.clock()
    Combat.Status = "dodge!"
end

local function dodgeLoop()
    while dodgeRunning do
        local _, myRoot = getCharacterParts()
        if myRoot then
            local now = os.clock()
            if now - lastDodgeAt > (ConfigRef.Settings.DodgeCooldown or 1.2) then
                local dodged = false
                for part, deadline in pairs(watchedProjectiles) do
                    if dodged then break end
                    if now > deadline or not part.Parent then
                        watchedProjectiles[part] = nil
                    else
                        local ok, threat = pcall(function()
                            local velocity = part.AssemblyLinearVelocity
                            local speed = velocity.Magnitude
                            if speed < 20 then return false end
                            local offset = myRoot.Position - part.Position
                            local dist = offset.Magnitude
                            if dist > (ConfigRef.Settings.DodgeRadius or 45) or dist < 2 then return false end
                            return velocity.Unit:Dot(offset.Unit) > 0.82
                        end)
                        if ok and threat then
                            dodgeNow(myRoot, part.Position)
                            dodged = true
                        end
                    end
                end
                if not dodged then
                    for _, player in ipairs(Players:GetPlayers()) do
                        if dodged then break end
                        if player ~= localPlayer then
                            -- угрозой считаем маньяка/шерифа по ролям ИЛИ любого
                            -- с ножом в руке (стрелявшего героя фиксируем по пистолету)
                            local role = RolesRef.Get(player.Name)
                            local character = player.Character
                            local root = character and character:FindFirstChild("HumanoidRootPart")
                            local armed = role == "Murderer" or role == "Sheriff" or role == "Hero"
                                or (character and (character:FindFirstChild("Knife") or character:FindFirstChild("Gun"))) ~= nil
                            if root and armed and RolesRef.IsAlive(player.Name) then
                                local dist = (root.Position - myRoot.Position).Magnitude
                                if dist < 16 then
                                    local look = root.CFrame.LookVector
                                    local toMe = (myRoot.Position - root.Position).Unit
                                    if look:Dot(toMe) > 0.78 then
                                        dodgeNow(myRoot, root.Position)
                                        dodged = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.12)
    end
end

function Combat.SetDodge(value)
    Combat.DodgeEnabled = value and true or false
    ConfigRef.Settings.AutoDodge = Combat.DodgeEnabled
    if value and not dodgeRunning then
        dodgeRunning = true
        dodgeConnections[#dodgeConnections + 1] = workspace.DescendantAdded:Connect(function(descendant)
            if dodgeRunning and descendant:IsA("BasePart") and isDodgeName(descendant.Name) then
                trackProjectile(descendant)
            end
        end)
        pcall(function()
            for _, descendant in ipairs(workspace:GetDescendants()) do
                if descendant:IsA("BasePart") and isDodgeName(descendant.Name) then
                    trackProjectile(descendant)
                end
            end
        end)
        task.spawn(dodgeLoop)
    elseif not value then
        dodgeRunning = false
        for _, connection in ipairs(dodgeConnections) do
            pcall(function() connection:Disconnect() end)
        end
        dodgeConnections = {}
        watchedProjectiles = {}
        Combat.Status = "выключено"
    end
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

function Combat.SetAura(value)
    Combat.AuraEnabled = value and true or false
    ConfigRef.Settings.KnifeAura = Combat.AuraEnabled
    if value and not auraRunning then
        auraRunning = true
        task.spawn(auraLoop)
    elseif not value then
        auraRunning = false
        Combat.Status = "выключено"
    end
end

function Combat.SetSheriffAuto(value)
    Combat.SheriffAutoEnabled = value and true or false
    ConfigRef.Settings.SheriffAuto = Combat.SheriffAutoEnabled
    if value and not sheriffRunning then
        sheriffRunning = true
        task.spawn(sheriffLoop)
    elseif not value then
        sheriffRunning = false
        Combat.Status = "выключено"
    end
end

function Combat.Configure(config, roles, stealth)
    ConfigRef = config
    RolesRef = roles
    StealthRef = stealth
    Combat.Debug = config.Settings.DebugLogs == true
end

function Combat.Destroy()
    auraRunning = false
    sheriffRunning = false
    dodgeRunning = false
    for _, connection in ipairs(dodgeConnections) do
        pcall(function() connection:Disconnect() end)
    end
    dodgeConnections = {}
    watchedProjectiles = {}
end

return Combat
