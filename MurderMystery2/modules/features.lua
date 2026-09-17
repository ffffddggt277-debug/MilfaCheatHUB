-- MilfaCheatHUB • Murder Mystery 2
-- Feature wiring v0.2.0. Eight tabs:
-- ИГРОКИ / АВТО / ПЕРСОНАЖ / ВИЗУАЛ / БОЙ / ТРОЛЛИНГ / БЕТА / СИСТЕМА.
-- Mobile: floating action buttons; PC: hotkeys (G/H/J/K).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local localPlayer = Players.LocalPlayer

local Features = {}
Features.__index = Features

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

    local playersTab = self.UI:CreateTab("Игроки", "ESP", colors.ESP)
    local autoTab = self.UI:CreateTab("Авто", "BOT", colors.Combat)
    local playerTab = self.UI:CreateTab("Персонаж", "PLR", colors.Player)
    local visualTab = self.UI:CreateTab("Визуал", "VIS", colors.World)
    local combatTab = self.UI:CreateTab("Бой", "HIT", colors.Combat)
    local trollTab = self.UI:CreateTab("Троллинг", "TRL", colors.Misc)
    local betaTab = self.UI:CreateTab("Бета", "BETA", colors.ESP)
    local systemTab = self.UI:CreateTab("Система", "SYS", colors.Misc)

    -- ============================== ИГРОКИ ==============================
    self.UI:AddHeading(playersTab, "Роли (видно до ножа)")
    self.RoleStatus = self.UI:AddText(playersTab, "Кто есть кто", "Первый опрос — после открытия GUI")
    -- ESP alerts (murderer nearby / gun dropped) surface on the status card.
    self.ESP.OnAlert = function(message)
        pcall(function() self.RoleStatus:Set(message) end)
    end
    self.UI:AddButton(playersTab, "Обновить роли сейчас", function()
        pcall(function() self.Roles.Refresh() end)
        self:UpdateRoleStatus()
    end)
    self.TimerStatus = self.UI:AddText(playersTab, "Таймер раунда", "—")
    self.UI:AddSection(playersTab, "Экран")
    self.UI:AddToggle(playersTab, "Плавающий таймер (HUD)", settings.ShowTimerHud, function(value)
        settings.ShowTimerHud = value
        if self.Hud then self.Hud:SetVisible(value) end
    end)
    self.UI:AddToggle(playersTab, "Плавающие кнопки (телефон)", settings.ShowFloatingButtons, function(value)
        settings.ShowFloatingButtons = value
        pcall(function() self.UI:SetFloatingHostVisible(value) end)
    end)
    self.UI:AddSection(playersTab, "ESP игроков")
    self.UI:AddToggle(playersTab, "Включить ESP игроков", settings.PlayerESP, function(value)
        self.ESP.SetEnabled(value)
    end)
    self.UI:AddToggle(playersTab, "Подсветка сквозь стены (Highlight)", settings.EspHighlight, function(value)
        settings.EspHighlight = value
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
    self.UI:AddSlider(playersTab, "Макс. дистанция ESP", 100, 2000, settings.EspMaxDistance, " м", function(value)
        settings.EspMaxDistance = value
    end)
    self.UI:AddSlider(playersTab, "Частота обновления", 0.5, 3, settings.RefreshSeconds, " с", function(value)
        settings.RefreshSeconds = value
    end)
    self.UI:AddSection(playersTab, "Алерты")
    self.UI:AddToggle(playersTab, "Алерты «МАНЬЯК рядом»", settings.MurderAlert, function(value)
        settings.MurderAlert = value
    end)
    self.UI:AddSlider(playersTab, "Радиус алерта маньяка", 20, 200, settings.MurderAlertDistance, " м", function(value)
        settings.MurderAlertDistance = value
    end)
    self.UI:AddToggle(playersTab, "Алерты о выпавшем пистолете", settings.GunDropAlert, function(value)
        settings.GunDropAlert = value
    end)
    self.UI:AddToggle(playersTab, "Подсветка GunDrop", settings.GunDropESP, function(value)
        settings.GunDropESP = value
    end)
    self.UI:AddButton(playersTab, "Телепорт к маньяку", function()
        local list = self.Roles.FindByRole("Murderer")
        if #list > 0 then
            self:GlideToPlayer(list[1])
        else
            self.RoleStatus:Set("маньяк неизвестен — обнови роли")
        end
    end)
    self.UI:AddButton(playersTab, "Телепорт к шерифу", function()
        local list = self.Roles.FindByRole("Sheriff")
        if #list > 0 then
            self:GlideToPlayer(list[1])
        else
            self.RoleStatus:Set("шериф неизвестен — обнови роли")
        end
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
    self.UI:AddSlider(autoTab, "Задержка фарма", 0.3, 3, settings.FarmDelay, " с", function(value)
        settings.FarmDelay = value
    end)
    self.UI:AddToggle(autoTab, "Стоп при полной сумке", settings.StopOnFull, function(value)
        settings.StopOnFull = value
    end)
    self.UI:AddToggle(autoTab, "Уходить в лобби при полной сумке", settings.LobbyOnFull, function(value)
        settings.LobbyOnFull = value
    end)
    self.UI:AddToggle(autoTab, "Собирать монеты и в лобби", settings.FarmLobbyCoins, function(value)
        settings.FarmLobbyCoins = value
    end)
    self.UI:AddButton(autoTab, "Сбросить счётчик собранных", function()
        self.Farm.CoinsCollected = 0
    end)
    self.UI:AddSection(autoTab, "Помощники раунда")
    self.UI:AddHeading(autoTab, "AutoPistol: ТП к пистолету и обратно")
    self.UI:AddDropdown(autoTab, "Режим AutoPistol", { "Выключено", "Кнопка", "Авто" }, settings.AutoPistolMode, function(option)
        settings.AutoPistolMode = option
        if self.PistolStatus then
            self.PistolStatus:Set(option == "Кнопка" and "кнопка появится, когда пистолет выпадет"
                or (option == "Авто" and "авто-подбор включён" or "выключено"))
        end
    end)
    self.PistolStatus = self.UI:AddText(autoTab, "Состояние", "режим: " .. tostring(settings.AutoPistolMode))
    self.UI:AddSlider(autoTab, "Скорость ТП к пистолету", 60, 150, settings.PistolSpeed, " ст/с", function(value)
        settings.PistolSpeed = value
    end)
    self.UI:AddSlider(autoTab, "Пауза перед возвратом", 0.3, 3, settings.PistolReturnDelay, " с", function(value)
        settings.PistolReturnDelay = value
    end)
    self.UI:AddButton(autoTab, "ТП к пистолету и обратно (сейчас)", function()
        local ok, message = self:GrabGunNow()
        if self.PistolStatus then
            self.PistolStatus:Set(ok and tostring(message) or ("ошибка: " .. tostring(message)))
        end
    end)
    self.UI:AddText(autoTab, "Как работает", "Кнопка/Авто: глайд к выпавшему GunDrop, подбор, возврат на место. Маньяк поднять не может (сервер). Клавиша ПК: J")
    self.UI:AddSection(autoTab, "Прочее")
    self.UI:AddToggle(autoTab, "Подсветка монет (Coin ESP)", settings.CoinESP, function(value)
        self.ESP.SetCoins(value)
    end)
    self.UI:AddToggle(autoTab, "Anti-AFK", settings.AntiAFK, function(value)
        self.Movement.SetAntiAFK(value)
    end)

    -- ============================== ПЕРСОНАЖ ==============================
    self.UI:AddHeading(playerTab, "Движение")
    self.UI:AddSlider(playerTab, "Скорость (безопасно до 50)", 16, 50, settings.WalkSpeed, "", function(value)
        settings.WalkSpeed = value
        self.Movement.ApplySpeed(value)
    end)
    self.UI:AddButton(playerTab, "Сбросить скорость", function()
        settings.WalkSpeed = 16
        self.Movement.ApplySpeed(16)
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
    self.UI:AddButton(playerTab, "В лобби", function()
        self.Movement.ToLobby()
    end)
    self.UI:AddButton(playerTab, "На карту (спавн)", function()
        if not self.Movement.ToMap() and self.FarmStatus then
            self.FarmStatus:Set("карта не найдена — подойди к карте")
        end
    end)
    self.UI:AddButton(playerTab, "Над картой (обзор)", function()
        self.Movement.AboveMap()
    end)

    -- ============================== ВИЗУАЛ ==============================
    self.UI:AddHeading(visualTab, "Клиентский визуал")
    self.UI:AddToggle(visualTab, "Fullbright (максимальная яркость)", settings.Fullbright, function(value)
        settings.Fullbright = value
        self.Visuals.SetFullbright(value)
    end)
    self.UI:AddToggle(visualTab, "Убрать туман", settings.NoFog, function(value)
        settings.NoFog = value
        self.Visuals.SetNoFog(value)
    end)
    self.UI:AddToggle(visualTab, "Убирать трупы (Raggy)", settings.RemoveRagdolls, function(value)
        self.Visuals.SetRemoveRagdolls(value)
    end)
    self.UI:AddToggle(visualTab, "Убирать барьеры карты (GlitchProof)", settings.RemoveBarriers, function(value)
        self.Visuals.SetRemoveBarriers(value)
    end)
    self.FpsStatus = self.UI:AddText(visualTab, "Производительность", "Обычный режим")
    self.UI:AddToggle(visualTab, "Лёгкий FPS-режим (для телефона)", false, function(value)
        self.Visuals.SetFpsMode(value)
        self.FpsStatus:Set(value and "Тени/эффекты выключены" or "Настройки восстановлены")
    end)
    self.UI:AddSection(visualTab, "Экран")
    self.UI:AddToggle(visualTab, "Трейсеры к игрокам (Beam)", settings.Tracers, function(value)
        settings.Tracers = value
    end)
    self.UI:AddToggle(visualTab, "Звук «маньяк рядом» (пинг)", settings.AlertBeep, function(value)
        settings.AlertBeep = value
    end)
    self.UI:AddSlider(visualTab, "Поле зрения (FOV)", 60, 120, settings.FOV or 70, "°", function(value)
        settings.FOV = value
        pcall(function()
            local camera = workspace.CurrentCamera
            if camera then camera.FieldOfView = value end
        end)
    end)
    self.UI:AddToggle(visualTab, "Дальний зум (обзор карты)", settings.WideZoom, function(value)
        settings.WideZoom = value
        pcall(function()
            localPlayer.CameraMaxZoomDistance = value and 400 or 128
        end)
    end)

    -- ============================== БОЙ ==============================
    self.UI:AddHeading(combatTab, "Оружие (только у своей роли)")
    self.UI:AddText(combatTab, "Внимание", "Функции боя используют родные ремоуты игры. Максимальный риск репортов от игроков — включай осознанно.")
    self.CombatStatus = self.UI:AddText(combatTab, "Состояние", "выключено")
    self.UI:AddSection(combatTab, "Нож-аура")
    self.UI:AddToggle(combatTab, "Нож-аура (автоудар рядом)", settings.KnifeAura, function(value)
        self.Combat.SetAura(value)
    end)
    self.UI:AddSlider(combatTab, "Радиус ауры", 8, 30, settings.AuraRadius, " м", function(value)
        settings.AuraRadius = value
    end)
    self.UI:AddSlider(combatTab, "Пауза между ударами", 0.5, 3, settings.AuraDelay, " с", function(value)
        settings.AuraDelay = value
    end)
    self.UI:AddButton(combatTab, "KILL ALL (все в радиусе 60)", function()
        local ok, message = self.Combat.KillAll()
        if self.CombatStatus then self.CombatStatus:Set(ok and ("KILL ALL: " .. message) or ("ошибка: " .. message)) end
    end)
    self.UI:AddSection(combatTab, "Тихий аим (кнопка/клавиша, без циклов)")
    self.UI:AddText(combatTab, "SheriffAim", "Кнопка «ВЫСТРЕЛ» на экране (или клавиша G): тихий выстрел в маньяка — ТОЛЬКО если между вами нет препятствий (рейкаст). Кнопка видна когда ты шериф/герой.")
    self.UI:AddToggle(combatTab, "SheriffAim: показывать кнопку", settings.SheriffAimButton, function(value)
        settings.SheriffAimButton = value
    end)
    self.UI:AddButton(combatTab, "SheriffAim: выстрелить сейчас", function()
        local ok, message = self.Combat.SheriffAimShot()
        if self.CombatStatus then self.CombatStatus:Set("SheriffAim: " .. tostring(message)) end
    end)
    self.UI:AddText(combatTab, "MurderAim", "Кнопка «НОЖ» на экране (или клавиша H): тихий бросок ножа в шерифа — если между вами нет препятствий. Кнопка видна когда ты маньяк.")
    self.UI:AddToggle(combatTab, "MurderAim: показывать кнопку", settings.MurderAimButton, function(value)
        settings.MurderAimButton = value
    end)
    self.UI:AddButton(combatTab, "MurderAim: бросить нож сейчас", function()
        local ok, message = self.Combat.MurderAimThrow()
        if self.CombatStatus then self.CombatStatus:Set("MurderAim: " .. tostring(message)) end
    end)
    self.UI:AddButton(combatTab, "Бросок ножа в точку прицела", function()
        local ok, message = self.Combat.ThrowAtAim()
        if self.CombatStatus then self.CombatStatus:Set("Throw: " .. tostring(message)) end
    end)
    self.UI:AddSlider(combatTab, "Макс. дистанция тихих прицелов", 50, 500, settings.AimMaxDistance, " м", function(value)
        settings.AimMaxDistance = value
    end)
    self.UI:AddSection(combatTab, "AutoDodge (уклонение)")
    self.UI:AddToggle(combatTab, "AutoDodge: стрейф от ножей и стрелков", settings.AutoDodge, function(value)
        self.Combat.SetDodge(value)
    end)
    self.UI:AddSlider(combatTab, "Радиус угрозы", 15, 80, settings.DodgeRadius, " м", function(value)
        settings.DodgeRadius = value
    end)
    self.UI:AddSlider(combatTab, "Сила рывка", 6, 20, settings.DodgePower, " м", function(value)
        settings.DodgePower = value
    end)
    self.UI:AddSlider(combatTab, "Пауза между уклонениями", 0.6, 3, settings.DodgeCooldown, " с", function(value)
        settings.DodgeCooldown = value
    end)
    self.UI:AddText(combatTab, "Как работает", "Ловим летящие в тебя ножи и резко уводим вбок. Пуля — хитскан, поэтому от стрелков/маньяка в упор уклоняемся ЗАРАНЕЕ, когда целятся. Кулдаун настраивается.")
    self.UI:AddSection(combatTab, "Шериф")
    self.UI:AddToggle(combatTab, "Авто-выстрел в маньяка (шериф/герой)", settings.SheriffAuto, function(value)
        self.Combat.SetSheriffAuto(value)
    end)
    self.UI:AddSlider(combatTab, "Дистанция выстрела", 50, 500, settings.SheriffRange, " м", function(value)
        settings.SheriffRange = value
    end)

    -- ============================== ТРОЛЛИНГ ==============================
    self.UI:AddHeading(trollTab, "Фейк смерть (2 типа)")
    self.UI:AddText(trollTab, "Как работает", "Смерть в MM2 подтверждает сервер — фейк полностью обмануть игру не может. Оба типа — вид на ТВОЁМ экране: для скринов, прикола и наблюдения.")
    self.TrollStatus = self.UI:AddText(trollTab, "Активно", "ничего")
    self.UI:AddButton(trollTab, "Тип 1: РАГДОЛЛ (лечь + oof)", function()
        self.Troll.SetFakeDeath("Рагдолл")
        if self.TrollStatus then self.TrollStatus:Set("фейк-смерть: РАГДОЛЛ (повторное нажатие — включить другой тип)") end
    end)
    self.UI:AddButton(trollTab, "Тип 2: ПРИЗРАК (невидимка)", function()
        self.Troll.SetFakeDeath("Призрак")
        if self.TrollStatus then self.TrollStatus:Set("фейк-смерть: ПРИЗРАК — ходи и смотри, кто кто") end
    end)
    self.UI:AddButton(trollTab, "Выключить фейк-смерть", function()
        self.Troll.SetFakeDeath(nil)
        if self.TrollStatus then self.TrollStatus:Set("выключено") end
    end)
    self.UI:AddText(trollTab, "Подсказка (ПК)", "Клавиша K переключает по кругу: выкл → рагдолл → призрак → выкл")
    self.UI:AddSection(trollTab, "Эмоции и анимации")
    self.UI:AddButton(trollTab, "Zen (медитация)", function()
        local ok, message = self.Troll.PlayEmote("Zen")
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Махать", function()
        local ok, message = self.Troll.PlayEmote("Махать")
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Танец", function()
        local ok, message = self.Troll.PlayEmote("Танец")
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Радость", function()
        local ok, message = self.Troll.PlayEmote("Радость")
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Смех", function()
        local ok, message = self.Troll.PlayEmote("Смех")
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Сесть", function()
        local ok, message = self.Troll.PlayEmote("Сесть")
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddText(trollTab, "Как работают эмоции", "Родной ремоут игры PlayEmote — видно всем. Если ремоут недоступен, проигрывается локальная анимация (видно только тебе).")
    self.UI:AddSection(trollTab, "Игровые троллинг-предметы")
    self.UI:AddButton(trollTab, "Фейк-пистолет (показать)", function()
        local ok, message = self.Troll.FakeGun()
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)
    self.UI:AddButton(trollTab, "Фейк-бомба (игрушка)", function()
        local ok, message = self.Troll.FakeBomb()
        if self.TrollStatus then self.TrollStatus:Set(tostring(message)) end
    end)

    -- ============================== БЕТА ==============================
    self.UI:AddHeading(betaTab, "Прогноз победы (БЕТА)")
    self.PredictionStatus = self.UI:AddText(betaTab, "Прогноз", "считаю при первом открытии...")
    self.UI:AddButton(betaTab, "Пересчитать сейчас", function()
        pcall(function()
            local result = self.Beta.Compute()
            if self.PredictionStatus then
                self.PredictionStatus:Set(result.Ready and result.Text or result.Text)
            end
        end)
    end)
    self.UI:AddSlider(betaTab, "Период пересчёта", 2, 10, settings.PredictionRefresh, " с", function(value)
        settings.PredictionRefresh = value
    end)
    self.PredictionFactors = self.UI:AddText(betaTab, "Почему такой прогноз", "факторы появятся здесь")
    self.UI:AddText(betaTab, "Как это работает (честно)", "Это эвристика, а не магия: жив ли шериф/герой, дистанция маньяк-шериф (далеко = шериф может спокойно стрелять; вплотную = нож быстрее), число живых мирных (запас времени), давление маньяка на мирных и таймер. Прогноз обновляется сам.")
    self.UI:AddSection(betaTab, "Статус")
    self.BetaNote = self.UI:AddText(betaTab, "Стабильность", "Раздел бета: механику прогноза будем докручивать по фидбеку из реальных раундов.")

    -- ============================== СИСТЕМА ==============================
    self.UI:AddHeading(systemTab, "СТЕЛС CALM (v" .. self.Config.Version .. ")")
    local mountKind = self.Stealth and tostring(self.Stealth.MountKind) or "неизвестно"
    self.StealthStatus = self.UI:AddText(systemTab, "Маунт GUI: " .. mountKind,
        "Скрытый маунт (gethui/CoreGui) — невидим игровым сканерам; в лог при загрузке идёт только номер версии")
    self.UI:AddToggle(systemTab, "Безопасные телепорты (glide)", settings.SafeTeleport, function(value)
        settings.SafeTeleport = value
        if self.Stealth then self.Stealth.SafeTeleport = value end
    end)
    self.UI:AddSlider(systemTab, "Скорость glide", 20, 100, settings.GlideSpeed, " ст/с", function(value)
        settings.GlideSpeed = value
        if self.Stealth then self.Stealth.GlideSpeed = value end
    end)
    self.UI:AddToggle(systemTab, "Человеческие задержки", settings.HumanizeDelays, function(value)
        settings.HumanizeDelays = value
    end)
    self.UI:AddToggle(systemTab, "Подробные логи (держать ВЫКЛ)", settings.DebugLogs, function(value)
        settings.DebugLogs = value
        if self.Stealth then self.Stealth.Debug = value end
        if self.ESP then self.ESP.Debug = value end
        if self.Farm then self.Farm.Debug = value end
        if self.Combat then self.Combat.Debug = value end
    end)
    self.UI:AddButton(systemTab, "PANIC: убрать все следы", function()
        local registry = self.Stealth and self.Stealth.Registry
        if registry and registry.Panic then registry.Panic() end
    end)
    self.UI:AddButton(systemTab, "Диагностика в консоль (F9)", function()
        local registry = self.Stealth and self.Stealth.Registry
        if registry and registry.Diag then
            registry.Diag()
            self.StealthStatus:Set("Диагностика выведена в консоль F9")
        end
    end)
    self.NetworkStatus = self.UI:AddText(systemTab, "Networking", self.Network:Summary())
    self.UI:AddButton(systemTab, "Проверить известные Remotes", function()
        self.NetworkStatus:Set(self.Network:Summary())
    end)
    self.UI:AddText(systemTab, "Безопасность", "Античита в MM2 не найдено (проверено по 9 хабам), но Roblox-античит на уровне клиента зависит от экзекьютора. Не провоцируй игроков на репорты.")

    self.UI:AddHeading(systemTab, "Диагностика")
    self.UI:AddText(systemTab, "Сборка " .. self.Config.Version,
        "CALM: печатается только номер версии, рандомный ключ реестра, скрытый маунт, ноль хуков. 60+ функций в 8 вкладках.")
    self.UI:AddSection(systemTab, "Горячие клавиши (ПК)")
    self.UI:AddText(systemTab, "Раскладка",
        (settings.KeySheriffAim or "G") .. " — SheriffAim (тихий выстрел) • " ..
        (settings.KeyMurderAim or "H") .. " — MurderAim (тихий бросок ножа) • " ..
        (settings.KeyGrabGun or "J") .. " — ТП к пистолету и обратно • " ..
        (settings.KeyFakeDeath or "K") .. " — фейк-смерть по кругу • " ..
        "RightControl — скрыть/показать окно. На телефоне — плавающие кнопки на экране.")
    self.UI:AddSection(systemTab, "Сессия")
    self.UI:AddButton(systemTab, "Реджойн в эту же игру", function()
        pcall(function()
            TeleportService:Teleport(self.Config.PlaceId, localPlayer)
        end)
    end)

    -- ============================== ПЛАВАЮЩИЕ КНОПКИ + HUD ==============================
    self.Hud = self.UI:AddFloatingHud()
    self.Hud:SetVisible(settings.ShowTimerHud ~= false)

    self.FabSheriff = self.UI:AddFloatingButton("ВЫСТРЕЛ", colors.Combat, function()
        local ok, message = self.Combat.SheriffAimShot()
        if self.CombatStatus then pcall(function() self.CombatStatus:Set("SheriffAim: " .. tostring(message)) end) end
    end)
    self.FabMurder = self.UI:AddFloatingButton("НОЖ", colors.Danger, function()
        local ok, message = self.Combat.MurderAimThrow()
        if self.CombatStatus then pcall(function() self.CombatStatus:Set("MurderAim: " .. tostring(message)) end) end
    end)
    self.FabPistol = self.UI:AddFloatingButton("ПИСТ", colors.Movement, function()
        local ok, message = self:GrabGunNow()
        if self.PistolStatus then pcall(function() self.PistolStatus:Set(ok and tostring(message) or ("ошибка: " .. tostring(message))) end) end
    end)
    pcall(function() self.UI:SetFloatingHostVisible(settings.ShowFloatingButtons ~= false) end)
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

function Features:UpdateRoleStatus()
    local murderer = self.Roles.FindByRole("Murderer")
    local sheriff = self.Roles.FindByRole("Sheriff")
    local hero = self.Roles.FindByRole("Hero")
    local parts = {}
    parts[#parts + 1] = "маньяк: " .. (#murderer > 0 and table.concat(murderer, ", ") or "неизвестен")
    parts[#parts + 1] = "шериф: " .. (#sheriff > 0 and table.concat(sheriff, ", ") or "неизвестен")
    if #hero > 0 then parts[#parts + 1] = "герой: " .. table.concat(hero, ", ") end
    if self.RoleStatus then
        self.RoleStatus:Set(table.concat(parts, " • "))
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
        -- ждём подтверждения подбора (GunDrop исчезает)
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
-- Monitor loop: statuses, AutoPistol, floating buttons, hotkeys
---------------------------------------------------------------------

function Features:Start()
    if self.Running then return end
    self.Running = true
    self.World.Start()

    -- Горячие клавиши (ПК). На телефоне то же самое — плавающими кнопками.
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
            -- роли обновляет ESP-луп; если он выключен — обновляем здесь
            local espRunning = false
            pcall(function() espRunning = self.ESP.Enabled end)
            if not espRunning then pcall(function() self.Roles.Refresh() end) end

            pcall(function() self:UpdateRoleStatus() end)
            if self.FarmStatus then pcall(function() self.FarmStatus:Set(self.Farm.Summary()) end) end
            if self.CombatStatus and self.Combat.Status and self.Combat.Status ~= "" then
                pcall(function() self.CombatStatus:Set(self.Combat.Status) end)
            end

            -- Таймер раунда (карточка в «Игроках» + плавающий HUD)
            pcall(function()
                local seconds = self.World.GetTimer()
                if self.TimerStatus then
                    if not seconds then
                        self.TimerStatus:Set("таймер недоступен / лобби")
                    elseif seconds <= 1 then
                        self.TimerStatus:Set("раунд закончился")
                    else
                        self.TimerStatus:Set(formatTimer(seconds) .. " до конца раунда")
                    end
                end
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

            -- БЕТА: прогноз победы (периодический пересчёт)
            if os.clock() - self.LastPredictionAt > (settings.PredictionRefresh or 4) then
                self.LastPredictionAt = os.clock()
                pcall(function()
                    local result = self.Beta.Compute()
                    if self.PredictionStatus then self.PredictionStatus:Set(result.Text) end
                    if self.PredictionFactors then
                        local factorText = "факторы неизвестны"
                        if #result.Factors > 0 then
                            local visible = {}
                            for index = 1, math.min(3, #result.Factors) do
                                visible[index] = result.Factors[index]
                            end
                            factorText = table.concat(visible, " • ")
                        end
                        self.PredictionFactors:Set(factorText)
                    end
                end)
            end

            -- AutoPistol: ТП к пистолету и обратно (авторежим) + видимость кнопок
            local amMurderer = false
            pcall(function() amMurderer = self.Roles.LocalIsMurderer() end)
            local dropNow = self.World.GetGunDrop()
            local mode = settings.AutoPistolMode or "Кнопка"
            if mode == "Авто" and not amMurderer and dropNow and os.clock() - self.LastGrabAt > 4 then
                self.LastGrabAt = os.clock()
                self:GrabGunNow()
            end
            -- легаси-настройка GunGrabber из v0.1.0 ведёт себя как «Авто»
            if settings.GunGrabber and not amMurderer and dropNow and os.clock() - self.LastGrabAt > 4 then
                self.LastGrabAt = os.clock()
                self:GrabGunNow()
            end
            pcall(function()
                local showBase = settings.ShowFloatingButtons ~= false
                self.FabPistol:SetVisible(showBase and dropNow ~= nil and not amMurderer and mode == "Кнопка")
                self.FabSheriff:SetVisible(showBase and settings.SheriffAimButton ~= false and self.Roles.LocalIsSheriff())
                self.FabMurder:SetVisible(showBase and settings.MurderAimButton ~= false and self.Roles.LocalIsMurderer())
            end)

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
