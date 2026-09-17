-- MilfaCheatHUB • Murder Mystery 2
-- Feature wiring v0.4.1. GUI почищен (аудит NEX + разметка юзера):
-- 7 вкладок: ГЛАВНАЯ / ИГРОКИ / БОЙ / АВТО / ПЕРСОНАЖ / ТРОЛЛИНГ / СИСТЕМА.
-- ГЛАВНАЯ — статус раунда/ролей/соединения + быстрые действия (новичок сразу видит главное).
-- Убрано: дубль-тоглы SheriffAim/MurderAim (кнопки делают то же),
-- слайдеры AimMaxDistance/AuraDelay/DodgeRadius/DodgeCooldown/FarmDelay/
-- PistolSpeed/PistolReturnDelay/EspMaxDistance (адекватные дефолты вшиты),
-- FakeBomb (видно только себе), RemoveRagdolls/RemoveBarriers (балласт),
-- NetworkStatus/mount-инфо, HumanizeDelays/GlideSpeed (внутренние).
-- AutoDodge: 1 слайдер профиля (Осторожно/Баланс/Агрессивно) вместо 4.
-- Эмоции: dropdown вместо 6 кнопок. ТП: dropdown вместо 3 кнопок.
-- Прогноз победы остаётся живым полем в ИГРОКАХ (ТЗ юзера).
-- Mobile: всё тапами; PC: горячие клавиши G/H/J/K.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local localPlayer = Players.LocalPlayer

local Features = {}
Features.__index = Features

-- профили AutoDodge: [радиус, сила, кулдаун]
local DODGE_PROFILES = {
    { Radius = 60, Power = 10, Cooldown = 2.0, Name = "Осторожно" },
    { Radius = 45, Power = 12, Cooldown = 1.2, Name = "Баланс" },
    { Radius = 30, Power = 16, Cooldown = 0.7, Name = "Агрессивно" },
}

function Features.new(config, ui, roles, network, world, esp, farm, combat, movement, visuals, alive, stealth, troll, beta)
    local self = setmetatable({}, Features)
    self.Config = config
    self.UI = ui
    self.Roles = roles
    self.Network = network
    self.World = world
    self.ESP = esp
    self.Farm = farm
    self.Combat = combat
    self.Movement = movement
    self.Visuals = visuals
    self.Alive = alive
    self.Stealth = stealth
    self.Troll = troll
    self.Beta = beta
    self.Running = false
    self.LastGrabAt = 0
    self.Connections = {}
    self.LastPredictionAt = 0
    return self
end

function Features:Build()
    local colors = self.Config.Colors
    local settings = self.Config.Settings

    local homeTab = self.UI:CreateTab("Главная", "HOME", colors.Accent)
    local playersTab = self.UI:CreateTab("Игроки", "ESP", colors.ESP)
    local combatTab = self.UI:CreateTab("Бой", "HIT", colors.Combat)
    local autoTab = self.UI:CreateTab("Авто", "BOT", colors.Combat)
    local playerTab = self.UI:CreateTab("Персонаж", "PLR", colors.Player)
    local trollTab = self.UI:CreateTab("Троллинг", "TRL", colors.Misc)
    local systemTab = self.UI:CreateTab("Система", "SYS", colors.Misc)

    -- ============================== ГЛАВНАЯ ==============================
    self.UI:AddHeading(homeTab, "Статус раунда")
    self.HomeRole = self.UI:AddText(homeTab, "Роли", "определяю...")
    self.HomeTimer = self.UI:AddText(homeTab, "Таймер", "—")
    self.HomeFarm = self.UI:AddText(homeTab, "Фарм", "выключено")
    self.HomeCombat = self.UI:AddText(homeTab, "Бой", "выключено")
    self.UI:AddSection(homeTab, "Соединение")
    self.UI:AddText(homeTab, "Ремоуты", self.Network:Summary())
    self.UI:AddSection(homeTab, "Быстрые действия")
    self.UI:AddButton(homeTab, "Выстрел в маньяка (шериф)", function()
        local ok, message = self.Combat.SheriffAimShot()
        if self.HomeCombat then self.HomeCombat:Set("SheriffAim: " .. tostring(message)) end
    end)
    self.UI:AddButton(homeTab, "Бросок ножа в шерифа (маньяк)", function()
        local ok, message = self.Combat.MurderAimThrow()
        if self.HomeCombat then self.HomeCombat:Set("MurderAim: " .. tostring(message)) end
    end)
    self.UI:AddButton(homeTab, "Подобрать пистолет", function()
        local ok, message = self:GrabGunNow()
        if self.HomeFarm then self.HomeFarm:Set(tostring(message)) end
    end)

    -- ============================== ИГРОКИ ==============================
    self.UI:AddHeading(playersTab, "Кто есть кто (видно до ножа)")
    self.RoleStatus = self.UI:AddText(playersTab, "Роли", "обновляется автоматически")
    self.ESP.OnAlert = function(message)
        pcall(function() self.RoleStatus:Set(message) end)
    end
    -- Прогноз победы: ЖИВОЕ ПОЛЕ в основном GUI (ТЗ юзера).
    self.PredictionStatus = self.UI:AddText(playersTab, "Кто выиграет", "считаю...")
    self.TimerStatus = self.UI:AddText(playersTab, "Таймер раунда", "—")
    self.UI:AddSection(playersTab, "Экран")
    self.UI:AddToggle(playersTab, "Плавающий таймер (HUD)", settings.ShowTimerHud, function(value)
        settings.ShowTimerHud = value
        if self.Hud then self.Hud:SetVisible(value) end
    end)
    self.UI:AddToggle(playersTab, "Квадратная быстрая кнопка", settings.ShowQuickMenu, function(value)
        settings.ShowQuickMenu = value
        if self.QuickMenu then self.QuickMenu:SetVisible(value) end
    end)
    self.UI:AddSection(playersTab, "ESP игроков")
    self.UI:AddToggle(playersTab, "Включить ESP", settings.PlayerESP, function(value)
        self.ESP.SetEnabled(value)
    end)
    self.UI:AddToggle(playersTab, "Показывать роль", settings.EspShowRole, function(value)
        settings.EspShowRole = value
    end)
    self.UI:AddToggle(playersTab, "Показывать дистанцию", settings.EspShowDistance, function(value)
        settings.EspShowDistance = value
    end)
    self.UI:AddToggle(playersTab, "Только цели (скрыть мирных)", settings.EspOnlyTargets, function(value)
        settings.EspOnlyTargets = value
    end)
    self.UI:AddToggle(playersTab, "Трейсеры к игрокам", settings.Tracers, function(value)
        settings.Tracers = value
    end)
    self.UI:AddSection(playersTab, "Алерты")
    self.UI:AddToggle(playersTab, "«МАНЬЯК рядом» + звук", settings.MurderAlert, function(value)
        settings.MurderAlert = value
        settings.AlertBeep = value
    end)
    self.UI:AddToggle(playersTab, "Алерты о выпавшем пистолете", settings.GunDropAlert, function(value)
        settings.GunDropAlert = value
    end)
    self.UI:AddToggle(playersTab, "Подсветка GunDrop", settings.GunDropESP, function(value)
        settings.GunDropESP = value
    end)
    self.UI:AddSection(playersTab, "Телепорт к роли")
    self.UI:AddButton(playersTab, "К маньяку", function()
        local list = self.Roles.FindByRole("Murderer")
        if #list > 0 then
            self:GlideToPlayer(list[1])
        else
            self.RoleStatus:Set("маньяк неизвестен — жди раунд")
        end
    end)
    self.UI:AddButton(playersTab, "К шерифу", function()
        local list = self.Roles.FindByRole("Sheriff")
        if #list > 0 then
            self:GlideToPlayer(list[1])
        else
            self.RoleStatus:Set("шериф неизвестен — жди раунд")
        end
    end)

    -- ============================== БОЙ ==============================
    self.UI:AddHeading(combatTab, "Оружие")
    self.CombatStatus = self.UI:AddText(combatTab, "Состояние", "выключено")
    self.UI:AddToggle(combatTab, "Нож-аура (ТП-стаб рядом)", settings.KnifeAura, function(value)
        self.Combat.SetAura(value)
    end)
    self.UI:AddSlider(combatTab, "Радиус ауры", 8, 30, settings.AuraRadius, " м", function(value)
        settings.AuraRadius = value
    end)
    self.UI:AddButton(combatTab, "KILL ALL (все в радиусе)", function()
        local ok, message = self.Combat.KillAll()
        if self.CombatStatus then self.CombatStatus:Set(ok and ("KILL ALL: " .. message) or ("ошибка: " .. message)) end
    end)
    self.UI:AddSection(combatTab, "Тихие прицелы")
    self.UI:AddButton(combatTab, "SheriffAim: выстрел в маньяка", function()
        local ok, message = self.Combat.SheriffAimShot()
        if self.CombatStatus then self.CombatStatus:Set("SheriffAim: " .. tostring(message)) end
    end)
    self.UI:AddToggle(combatTab, "Авто-выстрел (шериф/герой)", settings.SheriffAuto, function(value)
        self.Combat.SetSheriffAuto(value)
    end)
    self.UI:AddButton(combatTab, "MurderAim: бросок ножа в шерифа", function()
        local ok, message = self.Combat.MurderAimThrow()
        if self.CombatStatus then self.CombatStatus:Set("MurderAim: " .. tostring(message)) end
    end)
    self.UI:AddButton(combatTab, "Бросок в точку прицела", function()
        local ok, message = self.Combat.ThrowAtAim()
        if self.CombatStatus then self.CombatStatus:Set("Throw: " .. tostring(message)) end
    end)
    self.UI:AddSection(combatTab, "AutoDodge (уклонение)")
    self.UI:AddToggle(combatTab, "Включить уклонение", settings.AutoDodge, function(value)
        self:ApplyDodgeProfile(settings.DodgeProfile or 2)
        self.Combat.SetDodge(value)
    end)
    self.UI:AddSlider(combatTab, "Реакция: 1 Осторожно / 2 Баланс / 3 Агрессивно", 1, 3, settings.DodgeProfile or 2, "", function(value)
        self:ApplyDodgeProfile(value)
    end)

    -- ============================== АВТО ==============================
    self.UI:AddHeading(autoTab, "Фарм монет")
    self.FarmStatus = self.UI:AddText(autoTab, "Состояние фарма", "выключено")
    self.UI:AddToggle(autoTab, "Магнит монет (сбор без движения)", settings.CoinMagnet, function(value)
        self.Farm.SetMagnet(value)
    end)
    self.UI:AddSlider(autoTab, "Радиус магнита", 8, 60, settings.MagnetRadius, " м", function(value)
        settings.MagnetRadius = value
    end)
    self.UI:AddToggle(autoTab, "Автофарм (обход монет)", settings.CoinFarm, function(value)
        self.Farm.SetFarm(value)
    end)
    self.UI:AddDropdown(autoTab, "Режим фарма", { "Teleport", "Smooth", "Walk" }, settings.FarmMode, function(option)
        settings.FarmMode = option
    end)
    self.UI:AddToggle(autoTab, "Стоп при полной сумке", settings.StopOnFull, function(value)
        settings.StopOnFull = value
    end)
    self.UI:AddSection(autoTab, "Пистолет (AutoPistol)")
    self.PistolStatus = self.UI:AddText(autoTab, "Состояние", "режим: " .. tostring(settings.AutoPistolMode))
    self.UI:AddDropdown(autoTab, "Режим AutoPistol", { "Выключено", "Кнопка", "Авто" }, settings.AutoPistolMode, function(option)
        settings.AutoPistolMode = option
        if self.PistolStatus then
            self.PistolStatus:Set(option == "Кнопка" and "кнопка в быстром меню и на клавише J"
                or (option == "Авто" and "авто-подбор включён" or "выключено"))
        end
    end)
    self.UI:AddButton(autoTab, "Подобрать пистолет сейчас", function()
        local ok, message = self:GrabGunNow()
        if self.PistolStatus then self.PistolStatus:Set(ok and tostring(message) or ("ошибка: " .. tostring(message))) end
    end)
    self.UI:AddSection(autoTab, "Прочее")
    self.UI:AddToggle(autoTab, "Anti-AFK", settings.AntiAFK, function(value)
        self.Movement.SetAntiAFK(value)
    end)

    -- ============================== ПЕРСОНАЖ ==============================
    self.UI:AddHeading(playerTab, "Движение")
    self.UI:AddSlider(playerTab, "Скорость (безопасно до 50)", 16, 50, settings.WalkSpeed, "", function(value)
        settings.WalkSpeed = value
        self.Movement.ApplySpeed(value)
    end)
    self.UI:AddSlider(playerTab, "Прыжок", 50, 120, settings.JumpPower, "", function(value)
        settings.JumpPower = value
        self.Movement.ApplyJump(value)
    end)
    self.UI:AddToggle(playerTab, "Бесконечный прыжок", settings.InfiniteJump, function(value)
        settings.InfiniteJump = value
        self.Movement.SetInfJump(value)
    end)
    self.UI:AddToggle(playerTab, "Noclip (сквозь стены)", settings.Noclip, function(value)
        settings.Noclip = value
        self.Movement.SetNoclip(value)
    end)
    self.UI:AddToggle(playerTab, "Клик-телепорт (glide к точке)", settings.ClickTP, function(value)
        settings.ClickTP = value
        self.Movement.SetClickTP(value)
    end)
    self.UI:AddSection(playerTab, "Телепорты")
    self.UI:AddDropdown(playerTab, "Точка", { "Лобби", "Карта (спавн)", "Над картой (обзор)" }, "Лобби", function(option)
        self.TpChoice = option
    end)
    self.UI:AddButton(playerTab, "Телепортироваться", function()
        if self.TpChoice == "Карта (спавн)" then
            if not self.Movement.ToMap() and self.FarmStatus then
                self.FarmStatus:Set("карта не найдена — подойди к карте")
            end
        elseif self.TpChoice == "Над картой (обзор)" then
            self.Movement.AboveMap()
        else
            self.Movement.ToLobby()
        end
    end)

    -- ============================== ТРОЛЛИНГ ==============================
    self.UI:AddHeading(trollTab, "Фейк предметы (видно всем)")
    self.TrollStatus = self.UI:AddText(trollTab, "Активно", "ничего")
    self.UI:AddButton(trollTab, "Фейк НОЖ на руке", function()
        local ok, message = self.Troll.FakeKnife()
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Фейк-пистолет", function()
        local ok, message = self.Troll.FakeGun()
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Фейк-смерть (по кругу: рагдолл/призрак/выкл)", function()
        local message = self.Troll.CycleFakeDeath()
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddSection(trollTab, "Спид-глитч (глитч-бег как в популярных хабах)")
    self.UI:AddToggle(trollTab, "Спид-глитч", settings.FakeGlitch, function(value)
        local ok, message = self.Troll.SetFakeGlitch(value)
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddSlider(trollTab, "Сила глитча", 20, 60, settings.GlitchForce or 40, "", function(value)
        settings.GlitchForce = value
    end)
    self.UI:AddSection(trollTab, "Эмоции (ремоут игры — видно всем)")
    self.UI:AddDropdown(trollTab, "Эмоция", { "Zen", "Махать", "Танец", "Радость", "Смех", "Указать", "Сесть", "Зомби", "Ниндзя", "Флосс", "Дэб" }, "Zen", function(option)
        self.EmoteChoice = option
    end)
    self.UI:AddButton(trollTab, "Воспроизвести эмоцию", function()
        local ok, message = self.Troll.PlayEmote(self.EmoteChoice or "Zen")
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddSection(trollTab, "Прочее")
    self.UI:AddToggle(trollTab, "Невидимка (родная стелс игры)", settings.Invisible, function(value)
        local ok, message = self.Troll.SetInvisible(value)
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)

    -- ============================== СИСТЕМА ==============================
    self.UI:AddHeading(systemTab, "Система")
    self.UI:AddButton(systemTab, "Диагностика в консоль (F9)", function()
        local registry = self.Stealth and self.Stealth.Registry
        if registry and registry.Diag then
            registry.Diag()
            if self.StealthStatus then self.StealthStatus:Set("Диагностика выведена в консоль F9") end
        end
    end)
    self.StealthStatus = self.UI:AddText(systemTab, "Статус", "ремоуты: " .. tostring(self.Network:Summary()))
    self.UI:AddText(systemTab, "Горячие клавиши (ПК)",
        (settings.KeySheriffAim or "G") .. " — SheriffAim • " ..
        (settings.KeyMurderAim or "H") .. " — MurderAim • " ..
        (settings.KeyGrabGun or "J") .. " — пистолет • " ..
        (settings.KeyFakeDeath or "K") .. " — фейк-смерть • " ..
        "RightControl — скрыть/показать")
    self.UI:AddButton(systemTab, "Реджойн в эту же игру", function()
        pcall(function()
            TeleportService:Teleport(self.Config.PlaceId, localPlayer)
        end)
    end)

    -- ============================== ПЛАВАЮЩИЕ ЭЛЕМЕНТЫ ==============================
    self.Hud = self.UI:AddFloatingHud()
    self.Hud:SetVisible(settings.ShowTimerHud ~= false)

    self.QuickMenu = self.UI:AddQuickMenu({
        { Text = "ВЫСТРЕЛ", Color = colors.Combat, Callback = function()
            local ok, message = self.Combat.SheriffAimShot()
            if self.CombatStatus then pcall(function() self.CombatStatus:Set("SheriffAim: " .. tostring(message)) end) end
        end },
        { Text = "НОЖ", Color = colors.Danger, Callback = function()
            local ok, message = self.Combat.MurderAimThrow()
            if self.CombatStatus then pcall(function() self.CombatStatus:Set("MurderAim: " .. tostring(message)) end) end
        end },
        { Text = "ПИСТ", Color = colors.Movement, Callback = function()
            local ok, message = self:GrabGunNow()
            if self.PistolStatus then pcall(function() self.PistolStatus:Set(ok and tostring(message) or ("ошибка: " .. tostring(message))) end) end
        end },
        { Text = "ФЕЙК-СМЕРТЬ", Color = colors.Misc, Callback = function()
            local message = self.Troll.CycleFakeDeath()
            if self.TrollStatus then pcall(function() self.TrollStatus:Set(tostring(message)) end) end
        end },
        { Text = "ФЕЙК НОЖ", Color = colors.Success, Callback = function()
            local ok, message = self.Troll.FakeKnife()
            if self.TrollStatus then pcall(function() self.TrollStatus:Set(tostring(message)) end) end
        end },
        { Text = "ГЛИТЧ", Color = colors.World, Callback = function()
            local ok, message = self.Troll.SetFakeGlitch(not self.Troll.FakeGlitch)
            if self.TrollStatus then pcall(function() self.TrollStatus:Set(tostring(message)) end) end
        end },
    })
    pcall(function() self.QuickMenu:SetVisible(settings.ShowQuickMenu ~= false) end)
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

-- Профиль AutoDodge: пересчитывает радиус/силу/кулдаун в settings.
function Features:ApplyDodgeProfile(index)
    local settings = self.Config.Settings
    local profile = DODGE_PROFILES[math.clamp(math.floor(index or 2), 1, #DODGE_PROFILES)]
    settings.DodgeProfile = index
    settings.DodgeRadius = profile.Radius
    settings.DodgePower = profile.Power
    settings.DodgeCooldown = profile.Cooldown
end

function Features:UpdateRoleStatus()
    local murderer = self.Roles.FindByRole("Murderer")
    local sheriff = self.Roles.FindByRole("Sheriff")
    local hero = self.Roles.FindByRole("Hero")
    local parts = {}
    parts[#parts + 1] = "маньяк: " .. (#murderer > 0 and table.concat(murderer, ", ") or "?")
    parts[#parts + 1] = "шериф: " .. (#sheriff > 0 and table.concat(sheriff, ", ") or "?")
    if #hero > 0 then parts[#parts + 1] = "герой: " .. table.concat(hero, ", ") end
    if self.RoleStatus then
        local text = table.concat(parts, " • ")
        self._lastRoleText = text
        self.RoleStatus:Set(text)
    end
end

function Features:GlideToPlayer(playerName)
    local target = Players:FindFirstChild(playerName)
    local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if root and self.Stealth and self.Stealth.GlideTo then
        task.spawn(function()
            self.Stealth.GlideTo(root.Position, {})
        end)
        return true
    end
    return false
end

-- AutoPistol: глайд к выпавшему пистолету, подбор, возврат на место.
function Features:GrabGunNow()
    local drop = self.World.GetGunDrop()
    if not drop then return false, "пистолет не выпал" end
    local amMurderer = false
    pcall(function() amMurderer = self.Roles.LocalIsMurderer() end)
    if amMurderer then return false, "маньяк поднять не может (сервер)" end
    local character = localPlayer.Character
    local myRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return false, "нет персонажа" end
    local settings = self.Config.Settings
    if not (self.Stealth and self.Stealth.GlideTo) then
        myRoot.CFrame = drop.CFrame + Vector3.new(0, 1.5, 0)
        return true, "мгновенное ТП к пистолету"
    end
    task.spawn(function()
        local before = myRoot.CFrame
        self.Stealth.GlideTo(drop.Position + Vector3.new(0, 1.5, 0), { Speed = settings.PistolSpeed or 110 })
        local waited = 0
        while drop.Parent and waited < 2.5 do
            waited = waited + task.wait(0.2)
        end
        if not drop.Parent then
            task.wait(settings.PistolReturnDelay or 0.8)
            self.Stealth.GlideTo(before.Position, { Speed = settings.PistolSpeed or 110 })
        end
    end)
    return true, "лечу к пистолету"
end

local function formatTimer(seconds)
    if not seconds or seconds <= 1 then return "ЛОББИ" end
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

---------------------------------------------------------------------
-- Monitor loop: statuses, AutoPistol, prediction, hotkeys
---------------------------------------------------------------------

function Features:Start()
    if self.Running then return end
    self.Running = true
    self.World.Start()
    self:ApplyDodgeProfile(self.Config.Settings.DodgeProfile or 2)

    self.Connections[#self.Connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local settings = self.Config.Settings
        local name = input.KeyCode and input.KeyCode.Name or ""
        if name == (settings.KeySheriffAim or "G") then
            local ok, message = self.Combat.SheriffAimShot()
            if self.CombatStatus then pcall(function() self.CombatStatus:Set("SheriffAim: " .. tostring(message)) end) end
        elseif name == (settings.KeyMurderAim or "H") then
            local ok, message = self.Combat.MurderAimThrow()
            if self.CombatStatus then pcall(function() self.CombatStatus:Set("MurderAim: " .. tostring(message)) end) end
        elseif name == (settings.KeyGrabGun or "J") then
            self:GrabGunNow()
        elseif name == (settings.KeyFakeDeath or "K") then
            local message = self.Troll.CycleFakeDeath()
            if self.TrollStatus then pcall(function() self.TrollStatus:Set(tostring(message)) end) end
        end
    end)

    task.spawn(function()
        task.wait(0.6)
        pcall(function() self.Roles.Refresh() end)
        while self.Running and self.Alive() do
            local settings = self.Config.Settings
            -- роли обновляет свой цикл; подстраховка здесь
            pcall(function() self:UpdateRoleStatus() end)
            -- зеркалим статусы на ГЛАВНУЮ
            if self.HomeRole and self._lastRoleText then
                pcall(function() self.HomeRole:Set(self._lastRoleText) end)
            end
            if self.FarmStatus then pcall(function() self.FarmStatus:Set(self.Farm.Summary()) end) end
            if self.HomeFarm then pcall(function() self.HomeFarm:Set(self.Farm.Summary()) end) end
            if self.CombatStatus and self.Combat.Status and self.Combat.Status ~= "" then
                pcall(function() self.CombatStatus:Set(self.Combat.Status) end)
            end
            if self.HomeCombat then
                pcall(function() self.HomeCombat:Set(self.Combat.Status and self.Combat.Status ~= "" and self.Combat.Status or "выключено") end)
            end

            -- Таймер раунда (карточка + плавающий HUD + зеркало на ГЛАВНУЮ)
            pcall(function()
                local seconds = self.World.GetTimer()
                local timerText
                if not seconds then
                    timerText = "таймер недоступен / лобби"
                elseif seconds <= 1 then
                    timerText = "раунд закончился"
                else
                    timerText = formatTimer(seconds) .. " до конца раунда"
                end
                if self.TimerStatus then self.TimerStatus:Set(timerText) end
                if self.HomeTimer then self.HomeTimer:Set(timerText) end
                if self.Hud then
                    self.Hud:SetTime(formatTimer(seconds))
                    local roleText = "роль: " .. (self.Roles.LocalRole and self.Roles.Label(self.Roles.LocalRole) or "?")
                    local murderer = self.Roles.FindByRole("Murderer")
                    if #murderer > 0 then
                        local m = Players:FindFirstChild(murderer[1])
                        local mRoot = m and m.Character and m.Character:FindFirstChild("HumanoidRootPart")
                        local myRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if mRoot and myRoot then
                            roleText = roleText .. string.format(" • маньяк: %.0fм", (mRoot.Position - myRoot.Position).Magnitude)
                        end
                    end
                    self.Hud:SetInfo(roleText)
                end
            end)

            -- Прогноз победы (живое поле в «Игроках»)
            if os.clock() - self.LastPredictionAt > (settings.PredictionRefresh or 4) then
                self.LastPredictionAt = os.clock()
                pcall(function()
                    local result = self.Beta.Compute()
                    if self.PredictionStatus then self.PredictionStatus:Set(result.Text) end
                end)
            end

            -- AutoPistol: ТП к пистолету и обратно (авторежим)
            local amMurderer = false
            pcall(function() amMurderer = self.Roles.LocalIsMurderer() end)
            local dropNow = self.World.GetGunDrop()
            local mode = settings.AutoPistolMode or "Кнопка"
            if mode == "Авто" and not amMurderer and dropNow and os.clock() - self.LastGrabAt > 4 then
                self.LastGrabAt = os.clock()
                self:GrabGunNow()
            end

            task.wait(1.2)
        end
    end)
end

function Features:Destroy()
    self.Running = false
    for _, connection in ipairs(self.Connections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    self.Connections = {}
    pcall(function() if self.QuickMenu then self.QuickMenu:Destroy() end end)
    pcall(function() self.ESP.Destroy() end)
    pcall(function() self.Farm.Destroy() end)
    pcall(function() self.Combat.Destroy() end)
    pcall(function() self.Movement.Destroy() end)
    pcall(function() self.Visuals.Destroy() end)
    pcall(function() self.Troll.Shutdown() end)
    pcall(function() self.Roles.Shutdown() end)
    pcall(function() self.World.Destroy() end)
    pcall(function()
        local camera = workspace.CurrentCamera
        if camera then camera.FieldOfView = 70 end
        localPlayer.CameraMaxZoomDistance = 128
    end)
end

return Features
