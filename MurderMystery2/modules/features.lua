-- MilfaCheatHUB • Murder Mystery 2
-- Feature wiring v0.1.0. Six tabs: ИГРОКИ / АВТО / ПЕРСОНАЖ / ВИЗУАЛ / БОЙ / СИСТЕМА.
-- 40+ controls; risky combat features are labeled and rate-capped.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local Features = {}
Features.__index = Features

function Features.new(config, ui, roles, network, world, esp, farm, combat, movement, visuals, alive, stealth)
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
    self.Running = false
    self.LastGrabAt = 0
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
    self.UI:AddToggle(autoTab, "Автоподбор пистолета (GunDrop)", settings.GunGrabber, function(value)
        settings.GunGrabber = value
    end)
    self.UI:AddText(autoTab, "Как работает подбор", "Глайд к выпавшему GunDrop, потом обратно. Маньяк поднять пистолет не может (сервер).")
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

    -- ============================== БОЙ ==============================
    self.UI:AddHeading(combatTab, "Оружие (только у своей роли)")
    self.UI:AddText(combatTab, "Внимание", "Функции боя используют родные ремоуты игры. Максимальный риск репортов от игроков — включай осознанно.")
    self.CombatStatus = self.UI:AddText(combatTab, "Состояние", "выключено")
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
    self.UI:AddSection(combatTab, "Шериф")
    self.UI:AddToggle(combatTab, "Авто-выстрел в маньяка (шериф/герой)", settings.SheriffAuto, function(value)
        self.Combat.SetSheriffAuto(value)
    end)
    self.UI:AddSlider(combatTab, "Дистанция выстрела", 50, 500, settings.SheriffRange, " м", function(value)
        settings.SheriffRange = value
    end)

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
        "CALM: печатается только номер версии, рандомный ключ реестра, скрытый маунт, ноль хуков. 40+ функций.")
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

---------------------------------------------------------------------
-- Monitor loop: statuses + gun grabber
---------------------------------------------------------------------

function Features:Start()
    if self.Running then return end
    self.Running = true
    self.World.Start()

    task.spawn(function()
        task.wait(0.6)
        pcall(function() self.Roles.Refresh() end)
        while self.Running and self.Alive() do
            pcall(function() self:UpdateRoleStatus() end)
            if self.FarmStatus then pcall(function() self.FarmStatus:Set(self.Farm.Summary()) end) end
            if self.CombatStatus and self.Combat.Status and self.Combat.Status ~= "" then
                pcall(function() self.CombatStatus:Set(self.Combat.Status) end)
            end

            -- Gun grabber: non-murderer glides to a dropped gun, then back.
            local settings = self.Config.Settings
            if settings.GunGrabber and not self.Roles.LocalIsMurderer() then
                local drop = self.World.GetGunDrop()
                if drop and os.clock() - self.LastGrabAt > 4 then
                    self.LastGrabAt = os.clock()
                    local myRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if myRoot and self.Stealth and self.Stealth.GlideTo then
                        task.spawn(function()
                            local before = myRoot.CFrame
                            self.Stealth.GlideTo(drop.Position, { Speed = 70 })
                            -- wait for pickup confirmation (drop disappears)
                            local waited = 0
                            while drop.Parent and waited < 2.5 do
                                waited = waited + task.wait(0.25)
                            end
                            if not drop.Parent then
                                if self.Stealth.Registry and self.Stealth.Registry.NotifyGrab then
                                    -- no-op hook for future notifications
                                end
                                task.wait(0.6)
                                self.Stealth.GlideTo(before.Position, { Speed = 70 })
                            end
                        end)
                    end
                end
            end

            task.wait(1.2)
        end
    end)
end

function Features:Destroy()
    self.Running = false
    pcall(function() self.ESP.Destroy() end)
    pcall(function() self.Farm.Destroy() end)
    pcall(function() self.Combat.Destroy() end)
    pcall(function() self.Movement.Destroy() end)
    pcall(function() self.Visuals.Destroy() end)
    pcall(function() self.Roles.Shutdown() end)
    pcall(function() self.World.Destroy() end)
end

return Features
