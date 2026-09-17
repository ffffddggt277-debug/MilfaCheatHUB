-- MilfaCheatHUB • Murder Mystery 2
-- Combat v0.5.0 — REWRITE (Activate-first).
--
-- Почему v0.4.x «не работал» (разобрано по живым хабам CGS_Movil/fogyhub/
-- KittyHub/StyearX, скачанным свежими версиями):
--   1) Мы шлём ТОЛЬКО сырые ремоуты. Рабочие мобильные хабы сначала дергают
--      tool:Activate() — это запускает СОБСТВЕННЫЙ LocalScript тула: он сам
--      играет замах/выстрел (анимации!), шлёт правильные ремоуты и звук.
--      CGS_Movil (мобильный!): knife:Activate() в ауре, gun:Activate() в
--      TriggerBot/AutoShoot. fogyhub: TP + knife:Activate() + firetouch.
--   2) findTool мог вернуть нож ИЗ РЮКЗАКА — сервер отклоняет удары из
--      рюкзака. Теперь ensureEquipped ЖДЁТ, пока тул окажется в Character.
--   3) У актуального MM2 есть ремоут Gun.Shoot:FireServer(fromCF, toCF)
--      (StyearX) — добавлен как ПЕРВЫЙ канал выстрела, CreateBeam/AH2 —
--      второй, ShootGun/AH — третий.
--   4) ТП-стаб без якоря HRP флингует тело (fogyhub якорит). Теперь якорим.
--   5) Кнопки умирали на «роли не определены». Теперь при неизвестных ролях
--      выстрел/бросок летят в ТОЧКУ ПРИЦЕЛА — кнопка всегда делает видимое
--      действие.
--
-- Каналы удара (все сразу, сервер дедуплицирует):
--   knife:Activate() + swing-анимация тула
--   Knife.Stab:FireServer("Down") ... 0.07с ... ("Up")     (R3TH/KittyHub)
--   Knife.Events.KnifeStabbed:FireServer()                  (StyearX)
--   Knife.Events.HandleTouched:FireServer(корень цели)      (StyearX)
--   firetouchinterest(нож, корень цели)                     (fogyhub)
-- Каналы выстрела:
--   Gun.Shoot:FireServer(rightHandCF, CFrame.new(pos))      (StyearX)
--   Gun.KnifeLocal.CreateBeam.RemoteFunction(1, pos, "AH2"/"AH") (KittyHub)
--   Gun.KnifeServer.ShootGun(1, pos, "AH")                  (R3TH/MM2fun)
-- Бросок: Knife.Events.KnifeThrown:FireServer(from ОРИЕНТИРОВАННЫЙ,
--   to = CFrame.new(pos) * (from - from.Position)) + анимация броска с тула
--   (KittyHub: читаем Animation с ножа, играем через Animator до броска).

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

---------------------------------------------------------------------
-- Экипировка: тул ОБЯЗАН оказаться в Character, иначе сервер отклоняет.
---------------------------------------------------------------------

local function ensureEquipped(toolName, timeout)
    local character = localPlayer.Character
    if not character then return nil end
    local held = character:FindFirstChild(toolName)
    if held then return held end

    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local stowed = backpack and backpack:FindFirstChild(toolName)
    if not stowed then return nil end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    pcall(function() humanoid:EquipTool(stowed) end)

    local limit = timeout or 1.0
    local began = os.clock()
    while os.clock() - began < limit do
        character = localPlayer.Character
        held = character and character:FindFirstChild(toolName)
        if held then return held end
        task.wait(0.03)
    end
    -- не экипировался: ремоуты из рюкзака сервер отклоняет — честный nil
    character = localPlayer.Character
    return character and character:FindFirstChild(toolName) or nil
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

-- Фолбэк роли по оружию: тул в Character (реплицируется всем) ИЛИ в своём
-- Backpack (шериф спавнится с пистолетом В РЮКЗАКЕ, до экипировки — именно
-- этот случай раньше отсекал кнопку «ВЫСТРЕЛ» словом «нужна роль»).
local function holdingTool(name)
    local character = localPlayer.Character
    if character and character:FindFirstChild(name) then return true end
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    return (backpack and backpack:FindFirstChild(name) ~= nil) or false
end

local function amMurderer()
    if RolesRef.LocalIsMurderer() then return true end
    return holdingTool("Knife") == true
end

local function amSheriff()
    if RolesRef.LocalIsSheriff() then return true end
    return holdingTool("Gun") == true
end

---------------------------------------------------------------------
-- Анимации тулов: играем замах/выстрел/бросок сами (KittyHub-подход:
-- читаем Animation с тула, грузим в Animator — реплицируется всем).
---------------------------------------------------------------------

local animCache = {}   -- [animationInstance] = track

local function findToolAnimation(tool, patterns)
    if not tool then return nil end
    local only, count = nil, 0
    local ok, result = pcall(function()
        local matched = nil
        for _, inst in ipairs(tool:GetDescendants()) do
            if inst:IsA("Animation") and inst.AnimationId ~= "" then
                count = count + 1
                only = inst
                local lowered = string.lower(inst.Name)
                for _, pattern in ipairs(patterns or {}) do
                    if string.find(lowered, pattern, 1, true) then
                        matched = inst
                        break
                    end
                end
                if matched then break end
            end
        end
        return matched
    end)
    if ok and result then return result end
    -- ни один не совпал по имени: одна анимация на тул = она и есть нужная
    if count == 1 then return only end
    return nil
end

local function animatorOf(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    return humanoid:FindFirstChildOfClass("Animator") or humanoid
end

-- Проиграть анимацию тула; возвращает трек или nil. Перезапускаем, если
-- уже играет (два удара подряд = два замаха, а не каша).
local function playToolAnimation(tool, patterns)
    if ConfigRef and ConfigRef.Settings.CombatAnimations == false then return nil end
    local character = localPlayer.Character
    local animator = animatorOf(character)
    local animation = findToolAnimation(tool, patterns)
    if not animation or not animator then return nil end

    local track = animCache[animation]
    if not track or not track.Animator or track.Animator ~= animator then
        local ok, loaded = pcall(function() return animator:LoadAnimation(animation) end)
        if not ok or not loaded then return nil end
        track = loaded
        animCache[animation] = track
    end
    pcall(function()
        if track.IsPlaying then track:Stop(0) end
        track:Play(0.05)
    end)
    return track
end

local function stopCachedAnimation(tool)
    if not tool then return end
    pcall(function()
        for _, inst in ipairs(tool:GetDescendants()) do
            if inst:IsA("Animation") and animCache[inst] then
                local track = animCache[inst]
                if track.IsPlaying then track:Stop(0.1) end
            end
        end
    end)
end

---------------------------------------------------------------------
-- Точка прицела (когда роли неизвестны — бьём туда, куда смотрит юзер)
---------------------------------------------------------------------

local function aimPoint(fallbackDistance)
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local point = nil
    pcall(function()
        local mouse = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local exclude = {}
        if localPlayer.Character then exclude[#exclude + 1] = localPlayer.Character end
        params.FilterDescendantsInstances = exclude
        local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
        point = result and result.Position or (ray.Origin + ray.Direction * (fallbackDistance or 200))
    end)
    if not point then
        point = (camera.CFrame * CFrame.new(0, 0, -(fallbackDistance or 200))).Position
    end
    return point
end

---------------------------------------------------------------------
-- Нож: замах всеми каналами (Activate + Stab Down/Up + StyearX-пара + тач)
---------------------------------------------------------------------

local function swingKnife(knife, targetRoot)
    local ok = false
    -- 1) Собственный LocalScript тула: анимация замаха + его ремоуты.
    pcall(function()
        if knife.Activate then
            knife:Activate()
            ok = true
        end
    end)
    -- 2) Свою swing-анимацию тоже играем (если у тула нет локального скрипта).
    pcall(function() playToolAnimation(knife, { "swing", "stab", "slash", "attack" }) end)
    -- 3) Прямая пара Down/Up (R3TH/KittyHub).
    pcall(function()
        local stab = knife:FindFirstChild("Stab")
        if stab and stab:IsA("RemoteEvent") then
            stab:FireServer("Down")
            ok = true
            task.delay(0.07, function()
                pcall(function() stab:FireServer("Up") end)
            end)
        end
    end)
    -- 4) Страховка StyearX: KnifeStabbed + HandleTouched(корень цели).
    pcall(function()
        local events = knife:FindFirstChild("Events")
        if events then
            local stabbed = events:FindFirstChild("KnifeStabbed")
            if stabbed and stabbed:IsA("RemoteEvent") then
                stabbed:FireServer()
                ok = true
                local touched = events:FindFirstChild("HandleTouched")
                if touched and touched:IsA("RemoteEvent") and targetRoot then
                    touched:FireServer(targetRoot)
                end
            end
        end
    end)
    -- 5) Физический тач (fogyhub) — сервер считает касание ножа.
    pcall(function()
        local handle = knife:FindFirstChild("Handle") or knife:FindFirstChildWhichIsA("BasePart")
        if handle and targetRoot and type(firetouchinterest) == "function" then
            firetouchinterest(handle, targetRoot, 0)
            firetouchinterest(handle, targetRoot, 1)
        end
    end)
    return ok
end

-- ТП-стаб: якорим корень (fogyhub), мигаем за спину цели (2.5 стада),
-- замах всеми каналами, возвращаемся. Якорь держит физику от флинга.
local function tpStabTarget(targetRoot, targetCharacter)
    local _, myRoot = getCharacterParts()
    if not myRoot then return false end
    local knife = ensureEquipped("Knife", 0.8)
    if not knife then
        Combat.Status = "нож не найден/не экипировался"
        return false
    end

    local origin = myRoot.CFrame
    local wasAnchored = myRoot.Anchored
    local moved = false
    local dist = (targetRoot.Position - myRoot.Position).Magnitude
    if dist > 6 then
        pcall(function()
            myRoot.Anchored = true
            myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 2.5)
        end)
        moved = true
        task.wait(jitter(0.07))
    end

    local fresh = localPlayer.Character
    local freshKnife = fresh and fresh:FindFirstChild("Knife")
    local hit = swingKnife(freshKnife or knife, targetRoot)

    task.wait(jitter(0.12))
    pcall(function()
        if myRoot.Parent then
            if moved then myRoot.CFrame = origin end
            myRoot.Anchored = wasAnchored
        end
    end)
    return hit
end

-- Удар без телепорта (цель в 6 стадах): замах на месте.
local function stabInPlace(targetRoot)
    local knife = ensureEquipped("Knife", 0.8)
    if not knife then
        Combat.Status = "нож не найден/не экипировался"
        return false
    end
    return swingKnife(knife, targetRoot)
end

---------------------------------------------------------------------
-- Выстрел: Gun.Shoot -> CreateBeam(AH2/AH) -> ShootGun; Activate — фолбэк
---------------------------------------------------------------------

local function findShootRemote(gun)
    local found = nil
    pcall(function()
        -- новый канал (StyearX): RemoteEvent с именем Shoot где-то в туле
        for _, inst in ipairs(gun:GetDescendants()) do
            if inst:IsA("RemoteEvent") and string.lower(inst.Name) == "shoot" then
                found = inst
                break
            end
        end
        if not found and gun:FindFirstChild("Shoot") then
            found = gun:FindFirstChild("Shoot")
        end
    end)
    return found
end

local function beamRemote(gun)
    local remote = nil
    pcall(function()
        local knifeLocal = gun:FindFirstChild("KnifeLocal")
        local createBeam = knifeLocal and knifeLocal:FindFirstChild("CreateBeam")
        if createBeam then
            remote = createBeam:FindFirstChildOfClass("RemoteFunction")
                or (createBeam:IsA("RemoteFunction") and createBeam) or nil
        end
    end)
    return remote
end

local function shootGunRemote(gun)
    local remote = nil
    pcall(function()
        local knifeServer = gun:FindFirstChild("KnifeServer")
        local shootGun = knifeServer and knifeServer:FindFirstChild("ShootGun")
        if shootGun and shootGun:IsA("RemoteFunction") then remote = shootGun end
    end)
    return remote
end

local function rightHandCFrame(character, myRoot)
    local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
    if hand then return hand.CFrame end
    return myRoot and myRoot.CFrame or CFrame.new(0, 0, 0)
end

local function shootAt(targetPosition)
    local character, myRoot = getCharacterParts()
    if not myRoot then return false, "нет персонажа" end

    local gun = ensureEquipped("Gun", 0.6)
    if not gun then
        Combat.Status = "пистолет не найден/не экипировался"
        return false, "пистолет не найден/не экипировался"
    end
    character = localPlayer.Character
    gun = character and character:FindFirstChild("Gun") or gun
    if not gun or gun.Parent ~= character then
        return false, "пистолет не в руке"
    end

    -- доворачиваем корпус к цели (выглядит естественно, помогает серверу)
    pcall(function()
        local flat = Vector3.new(targetPosition.X, myRoot.Position.Y, targetPosition.Z)
        if (flat - myRoot.Position).Magnitude > 0.5 then
            myRoot.CFrame = CFrame.lookAt(myRoot.Position, flat)
        end
    end)

    -- анимация выстрела с тула
    pcall(function() playToolAnimation(gun, { "fire", "shoot", "recoil", "shot" }) end)

    local fired = false
    -- 1) Gun.Shoot:FireServer(from, to) — актуальный канал (StyearX)
    pcall(function()
        local shoot = findShootRemote(gun)
        if shoot then
            shoot:FireServer(rightHandCFrame(character, myRoot), CFrame.new(targetPosition))
            fired = true
        end
    end)
    -- 2) CreateBeam RemoteFunction(1, pos, тег), тег AH2 -> AH
    if not fired then
        pcall(function()
            local beam = beamRemote(gun)
            if beam then
                beam:InvokeServer(1, targetPosition, SHOT_TAGS[1])
                fired = true
            end
        end)
    end
    if not fired then
        pcall(function()
            local beam = beamRemote(gun)
            if beam then
                beam:InvokeServer(1, targetPosition, SHOT_TAGS[2])
                fired = true
            end
        end)
    end
    -- 3) ShootGun(1, pos, "AH") — старый канал
    if not fired then
        pcall(function()
            local shootGun = shootGunRemote(gun)
            if shootGun then
                shootGun:InvokeServer(1, targetPosition, "AH")
                fired = true
            end
        end)
    end
    -- 4) Последний шанс: собственный выстрел тула по камере
    if not fired then
        pcall(function()
            local camera = workspace.CurrentCamera
            if camera then
                camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPosition)
            end
            if gun.Activate then gun:Activate() end
            fired = true
        end)
    end

    note("shot fired=" .. tostring(fired))
    return fired, fired and "выстрел отправлен" or "ремоуты выстрела не найдены"
end

---------------------------------------------------------------------
-- Бросок ножа (ориентированный CFrame + анимация броска с тула)
---------------------------------------------------------------------

local function throwKnifeAt(targetPosition)
    local knife = ensureEquipped("Knife", 0.8)
    if not knife then
        Combat.Status = "нож не найден/не экипировался"
        return false, "нож не найден/не экипировался"
    end
    local character = localPlayer.Character
    local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
    if not hand then return false, "нет руки" end

    -- KittyHub: анимация броска играется ДО ремоута — бросок не выглядит
    -- как нож, выпавший из статуи.
    local track = nil
    pcall(function() track = playToolAnimation(knife, { "throw", "toss" }) end)
    local hold = 0.1
    pcall(function()
        if track and track.Length > 0 then
            hold = math.min(track.Length * 0.55, 0.75)
        end
    end)

    if hold > 0.02 then task.wait(hold) end

    -- рука могла смениться, пока игралась анимация — берём свежую
    character = localPlayer.Character
    hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
    if not hand then return false, "нет руки" end

    local from = CFrame.new(hand.Position)
    if (targetPosition - hand.Position).Magnitude > 0.5 then
        from = CFrame.new(hand.Position, targetPosition)
    end

    local ok = false
    pcall(function()
        local events = knife:FindFirstChild("Events")
        local thrown = events and events:FindFirstChild("KnifeThrown")
        if not (thrown and thrown:IsA("RemoteEvent")) then
            thrown = knife:FindFirstChild("Throw")
        end
        if thrown and thrown:IsA("RemoteEvent") then
            -- второй аргумент — ОРИЕНТИРОВАННЫЙ CFrame; голый CFrame.new(point)
            -- разворачивает нож по мировой оси и он летит мимо
            thrown:FireServer(from, CFrame.new(targetPosition) * (from - from.Position))
            ok = true
        end
    end)
    return ok, ok and "бросок отправлен" or "ремоут броска не найден"
end

---------------------------------------------------------------------
-- SheriffAim: выстрел в маньяка, при неизвестных ролях — в прицел
---------------------------------------------------------------------

local function trySheriffShot(allowAimFallback)
    local settings = ConfigRef.Settings
    if not amSheriff() then
        Combat.Status = "нужна роль ШЕРИФ/ГЕРОЙ (подбери пистолет)"
        return false, "нужен пистолет (шериф/герой)"
    end
    local _, myRoot = getCharacterParts()
    if not myRoot then return false, "нет персонажа" end
    if os.clock() - lastShotAt < 0.45 then
        return false, "перезарядка"
    end

    local murderers = RolesRef.FindByRole("Murderer")
    if #murderers > 0 then
        for _, name in ipairs(murderers) do
            local target = Players:FindFirstChild(name)
            local root = target and aliveTargetRoot(target)
            if root then
                local dist = (root.Position - myRoot.Position).Magnitude
                if dist <= (settings.SheriffRange or 300) then
                    local ok, message = shootAt(root.Position)
                    lastShotAt = os.clock()
                    if ok then
                        Combat.LastKillName = name
                        Combat.Status = "выстрел: " .. name
                        if Combat.OnNotify then pcall(Combat.OnNotify, "Выстрел в маньяка: " .. name) end
                        return true, "выстрел в " .. name
                    end
                    return false, message
                end
                Combat.Status = string.format("маньяк далеко (%.0fм)", dist)
                return false, string.format("маньяк далеко (%.0fм)", dist)
            end
        end
    end

    -- роли неизвестны (или маньяк мёртв): выстрел в точку прицела, чтобы
    -- кнопка всегда делала видимое действие
    if allowAimFallback then
        local point = aimPoint(200)
        if not point then return false, "нет камеры" end
        local ok, message = shootAt(point)
        lastShotAt = os.clock()
        if ok then
            Combat.Status = "выстрел в прицел (роли неизвестны)"
            return true, "выстрел в прицел (роли неизвестны)"
        end
        return false, message
    end
    return false, "маньяк неизвестен — роли не определены"
end

local function sheriffLoop()
    while sheriffRunning do
        local ok, err = pcall(trySheriffShot, false)
        if not ok then note("sheriff: " .. tostring(err)) end
        task.wait(jitter(1.2))
    end
end

---------------------------------------------------------------------
-- Ближние цели (обёртка с pcall на Roles)
---------------------------------------------------------------------

local function nearbyTargetsSafe(radius, maxCount)
    local _, myRoot = getCharacterParts()
    if not myRoot then return {} end
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            local alive = true
            pcall(function() alive = RolesRef.IsAlive(player.Name) end)
            if alive then
                local root = aliveTargetRoot(player)
                if root and (root.Position - myRoot.Position).Magnitude <= radius then
                    list[#list + 1] = { Player = player, Root = root }
                    if maxCount and #list >= maxCount then break end
                end
            end
        end
    end
    return list
end

---------------------------------------------------------------------
-- Аура маньяка: ТП-стаб по ближайшим
---------------------------------------------------------------------

local function auraLoop()
    while auraRunning do
        local settings = ConfigRef.Settings
        if not amMurderer() then
            Combat.Status = "нужна роль МАНЬЯК (подбери нож)"
        else
            local targets = nearbyTargetsSafe(settings.AuraRadius or 14, 2)
            if #targets == 0 then
                Combat.Status = "целей рядом нет"
            else
                for _, target in ipairs(targets) do
                    if not auraRunning then break end
                    tpStabTarget(target.Root, target.Player.Character)
                    -- честный счёт: убийство = цель реально умерла
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
        task.wait(jitter(0.4))
    end
end

---------------------------------------------------------------------
-- KILL ALL: маньяк — ТП-стаб всех в радиусе; шериф — очередь выстрелов
---------------------------------------------------------------------

function Combat.KillAll()
    local isMurderer = amMurderer()
    local isSheriff = amSheriff()
    if not isMurderer and not isSheriff then
        return false, "нужна роль МАНЬЯК или ШЕРИФ"
    end
    local radius = (ConfigRef.Settings.KillAllRadius or 60)
    local targets = nearbyTargetsSafe(radius, 12)
    if #targets == 0 then
        return false, "никого в радиусе " .. tostring(radius)
    end
    if isMurderer then
        local knife = ensureEquipped("Knife", 0.8)
        if not knife then return false, "нож не найден" end
        task.spawn(function()
            for _, target in ipairs(targets) do
                local freshRoot = aliveTargetRoot(target.Player)
                if freshRoot then
                    tpStabTarget(freshRoot, target.Player.Character)
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
        local gun = ensureEquipped("Gun", 0.8)
        if not gun then return false, "пистолет не найден" end
        task.spawn(function()
            for _, target in ipairs(targets) do
                local freshRoot = aliveTargetRoot(target.Player)
                if freshRoot then
                    shootAt(freshRoot.Position)
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
-- MurderAim: бросок ножа в шерифа (или в прицел, если роли неизвестны)
---------------------------------------------------------------------

function Combat.MurderAimThrow()
    local settings = ConfigRef.Settings
    if not amMurderer() then
        Combat.Status = "нужна роль МАНЬЯК (подбери нож)"
        return false, "нужен нож (маньяк)"
    end
    local _, myRoot = getCharacterParts()
    if not myRoot then return false, "нет персонажа" end
    if os.clock() - lastThrowAt < 1.0 then
        return false, "нож ещё летит (перезарядка)"
    end

    local sheriffs = RolesRef.FindByRole("Sheriff")
    if #sheriffs > 0 then
        local target = Players:FindFirstChild(sheriffs[1])
        local root = target and aliveTargetRoot(target)
        if root then
            local dist = (root.Position - myRoot.Position).Magnitude
            if dist > (settings.AimMaxDistance or 260) then
                return false, string.format("далеко: %.0fм", dist)
            end
            local ok, message = throwKnifeAt(root.Position)
            lastThrowAt = os.clock()
            if ok then
                Combat.LastKillName = sheriffs[1]
                Combat.Status = "бросок ножа: " .. sheriffs[1]
                if Combat.OnNotify then pcall(Combat.OnNotify, "Бросок ножа в шерифа: " .. sheriffs[1]) end
                return true, "бросок в " .. sheriffs[1]
            end
            return false, message
        end
    end

    -- шериф неизвестен: бросок в точку прицела
    local point = aimPoint(200)
    if not point then return false, "нет камеры" end
    local ok, message = throwKnifeAt(point)
    lastThrowAt = os.clock()
    if ok then
        Combat.Status = "бросок в прицел (шериф неизвестен)"
        return true, "бросок в прицел (шериф неизвестен)"
    end
    return false, message
end

---------------------------------------------------------------------
-- SheriffAimShot: по кнопке/клавише (с фолбэком в прицел)
---------------------------------------------------------------------

function Combat.SheriffAimShot()
    return trySheriffShot(true)
end

---------------------------------------------------------------------
-- StabNearest: удар ножом в ближайшего живого (кнопка быстрого меню)
---------------------------------------------------------------------

function Combat.StabNearest()
    if not amMurderer() then
        Combat.Status = "нужна роль МАНЬЯК (подбери нож)"
        return false, "нужен нож (маньяк)"
    end
    local _, myRoot = getCharacterParts()
    if not myRoot then return false, "нет персонажа" end
    local targets = nearbyTargetsSafe(30, 1)
    if #targets == 0 then
        -- никого рядом: удар в точку прицела (если там кто-то есть)
        local point = aimPoint(150)
        if point then
            local ok = stabInPlace(nil)
            return ok, ok and "замах в прицел" or "нож не экипировался"
        end
        return false, "рядом никого"
    end
    local target = targets[1]
    local dist = (target.Root.Position - myRoot.Position).Magnitude
    local ok
    if dist > 6 then
        ok = tpStabTarget(target.Root, target.Player.Character)
    else
        ok = stabInPlace(target.Root)
    end
    if ok then
        Combat.Status = "удар: " .. target.Player.Name
        task.wait(jitter(0.3))
        if not aliveTargetRoot(target.Player) then
            Combat.KillCount = Combat.KillCount + 1
            Combat.LastKillName = target.Player.Name
            Combat.Status = "убит: " .. target.Player.Name
        end
    end
    return ok, ok and ("удар по " .. target.Player.Name) or "не экипировался"
end

---------------------------------------------------------------------
-- Бросок ножа в точку прицела
---------------------------------------------------------------------

function Combat.ThrowAtAim()
    if not amMurderer() then
        return false, "нужен нож (маньяк)"
    end
    if os.clock() - lastThrowAt < 1.0 then
        return false, "нож ещё летит (перезарядка)"
    end
    local point = aimPoint(200)
    if not point then return false, "нет камеры" end
    local ok, message = throwKnifeAt(point)
    lastThrowAt = os.clock()
    if ok then
        Combat.Status = "бросок в прицел"
        return true, "бросок выполнен"
    end
    return false, message
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

-- Профили AutoDodge (аудит v0.4.0: вместо 4 контролов — тогл + один профиль).
local DODGE_PROFILES = {
    Calm       = { Power = 10, Cooldown = 1.6, Radius = 38 },
    Balanced   = { Power = 12, Cooldown = 1.2, Radius = 45 },
    Aggressive = { Power = 16, Cooldown = 0.8, Radius = 55 },
}

function Combat.SetDodgeProfile(name)
    local profile = DODGE_PROFILES[name] or DODGE_PROFILES.Balanced
    if ConfigRef and ConfigRef.Settings then
        ConfigRef.Settings.DodgePower = profile.Power
        ConfigRef.Settings.DodgeCooldown = profile.Cooldown
        ConfigRef.Settings.DodgeRadius = profile.Radius
    end
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
                            local role = nil
                            pcall(function() role = RolesRef.Get(player.Name) end)
                            local character = player.Character
                            local root = character and character:FindFirstChild("HumanoidRootPart")
                            local armed = role == "Murderer" or role == "Sheriff" or role == "Hero"
                                or (character and (character:FindFirstChild("Knife") or character:FindFirstChild("Gun"))) ~= nil
                            if root and armed then
                                local alive = true
                                pcall(function() alive = RolesRef.IsAlive(player.Name) end)
                                if alive then
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
        end
        task.wait(0.12)
    end
end

function Combat.SetDodge(value)
    Combat.DodgeEnabled = value and true or false
    ConfigRef.Settings.AutoDodge = Combat.DodgeEnabled
    if value and not dodgeRunning and #dodgeConnections == 0 then
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
    pcall(function()
        local character = localPlayer.Character
        local tool = character and (character:FindFirstChild("Knife") or character:FindFirstChild("Gun"))
        if tool then stopCachedAnimation(tool) end
    end)
    animCache = {}
end

return Combat
