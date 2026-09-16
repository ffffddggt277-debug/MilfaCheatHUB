-- MilfaCheatHUB • feature controller v0.4 (stealth)

local Features = {}
Features.__index = Features

function Features.new(config, ui, scanner, network, positions, esp, eggs, automation, player, rarity, alive, stealth)
    local self = setmetatable({}, Features)
    self.Config = config
    self.UI = ui
    self.Scanner = scanner
    self.Network = network
    self.Positions = positions
    self.ESP = esp
    self.Eggs = eggs
    self.Automation = automation
    self.Player = player
    self.Rarity = rarity
    self.Alive = alive
    self.Stealth = stealth
    self.Running = false
    self.FpsOriginal = {}
    return self
end

-- Glide wrapper used by every manual teleport button.
function Features:GlideTo(position, height)
    local stealth = self.Stealth
    if stealth and stealth.GlideTo and self.Config.Settings.SafeTeleport then
        stealth.SafeTeleport = true
        stealth.GlideSpeed = self.Config.Settings.GlideSpeed or 48
        task.spawn(function()
            pcall(stealth.GlideTo, stealth, position, {Height = height or 2.5})
        end)
        return
    end
    local root = self.Eggs:GetRoot()
    if root then root.CFrame = CFrame.new(position + Vector3.new(0, height or 2.5, 0)) end
end

function Features:SetFpsMode(enabled)
    local effectClasses = {
        ParticleEmitter = true,
        Trail = true,
        Beam = true,
        Smoke = true,
        Fire = true,
        Sparkles = true,
    }

    if enabled then
        local processed = 0
        for _, object in ipairs(workspace:GetDescendants()) do
            if effectClasses[object.ClassName] then
                self.FpsOriginal[object] = object.Enabled
                object.Enabled = false
            elseif object:IsA("BasePart") then
                self.FpsOriginal[object] = object.CastShadow
                object.CastShadow = false
            end
            processed = processed + 1
            if processed % 500 == 0 then task.wait() end
        end
    else
        local processed = 0
        for object, value in pairs(self.FpsOriginal) do
            if object and object.Parent then
                pcall(function()
                    if object:IsA("BasePart") then object.CastShadow = value
                    else object.Enabled = value end
                end)
            end
            processed = processed + 1
            if processed % 500 == 0 then task.wait() end
        end
        self.FpsOriginal = {}
    end
end

function Features:UpdateEggs()
    local settings = self.Config.Settings
    local records = self.Eggs:Scan()
    self.AllRecords = records

    local filtered = self.Eggs:Filter(records, {
        Rarities = settings.RarityFilter,
        MaxDistance = settings.MaxListDistance,
    })
    self.Eggs:Sort(filtered, settings.SortMode)
    self.FilteredRecords = filtered

    if self.EggStatus then
        self.EggStatus:Set(string.format("Всего объектов: %d  •  по фильтру: %d", #records, #filtered))
    end
    if self.EggList then
        self.EggList:Rebuild(filtered, {
            OnTeleport = function(record)
                if record.Position then
                    self:GlideTo(record.Position)
                end
            end,
            OnSteal = function(record)
                pcall(function() self.Automation:StealOne(record) end)
            end,
        })
    end
    if self.ESP.Enabled then
        local espRecords = settings.EspFilterOnly and filtered or records
        self.ESP:Refresh(espRecords, self.Scanner)
    end
    return records
end

function Features:RefreshStatuses()
    local status = self.Automation.Status
    if self.StealStatus then self.StealStatus:Set("Кража: " .. tostring(status.Steal or "—")) end
    if self.SellStatus then self.SellStatus:Set("Продажа: " .. tostring(status.Sell or "—")) end
    if self.HatchStatus then self.HatchStatus:Set("Вылупление: " .. tostring(status.Hatch or "—")) end
    if self.CollectStatus then self.CollectStatus:Set("Доход: " .. tostring(status.Collect or "—")) end
    if self.TreadmillStatus then self.TreadmillStatus:Set("Дорожка: " .. tostring(status.Treadmill or "—")) end
    if self.UpgradeStatus then self.UpgradeStatus:Set("Апгрейды: " .. tostring(status.Upgrades or "—")) end
    if self.PetsStatus then self.PetsStatus:Set("Питомцы: " .. tostring(status.Pets or "—")) end
    if self.TrapsStatus then self.TrapsStatus:Set("Ловушки: " .. tostring(status.Traps or "—")) end
end

-- Fast egg carry: zero hold time on the game's "CarryAreaEgg" ProximityPrompt.
-- Community-proven utility (l10scripts style): subscribe once, zero every prompt
-- both at enable-time and whenever the game shows a fresh one.
function Features:ApplyFastPrompt(enabled)
    local service = game:GetService("ProximityPromptService")
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer

    if self._FastPromptConn then
        pcall(function() self._FastPromptConn:Disconnect() end)
        self._FastPromptConn = nil
    end

    if not enabled then return end

    local function zeroPrompt(prompt)
        pcall(function()
            if prompt and prompt:IsA("ProximityPrompt") and prompt.Name == "CarryAreaEgg" then
                prompt.HoldDuration = 0
            end
        end)
    end

    -- Existing prompts in the world right now.
    pcall(function()
        for _, descendant in ipairs(workspace:GetDescendants()) do
            if descendant:IsA("ProximityPrompt") then zeroPrompt(descendant) end
        end
    end)

    -- Fresh prompts shown later (hold begins -> zero before progress starts).
    self._FastPromptConn = service.PromptButtonHoldBegan:Connect(function(prompt, player)
        if player == localPlayer then zeroPrompt(prompt) end
    end)
end

-- Soft anti-teleport: disconnect the client handlers of RE/RigSync/Refresh so
-- the server cannot rubber-band our glides back. Reversible via Disable when
-- the executor supports it; falls back to Disconnect otherwise.
function Features:ApplyRigSyncCut(enabled)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    local remote = networking and networking:FindFirstChild("RE/RigSync/Refresh")
    if not remote then
        print("[MilfaCheatHUB] RigSync: remote RE/RigSync/Refresh не найден")
        return
    end

    -- Restore previously disabled connections first.
    if self._RigSyncConns then
        for _, connection in ipairs(self._RigSyncConns) do
            pcall(function() connection:Enable() end)
        end
        self._RigSyncConns = nil
    end

    if not enabled then return end

    if type(getconnections) ~= "function" then
        print("[MilfaCheatHUB] RigSync: getconnections не поддерживается экзекьютором")
        return
    end

    local ok, connections = pcall(getconnections, remote.OnClientEvent)
    if not ok or type(connections) ~= "table" then
        print("[MilfaCheatHUB] RigSync: не удалось получить connections: " .. tostring(connections))
        return
    end

    local patched = 0
    local stored = {}
    for _, connection in ipairs(connections) do
        local disabled = pcall(function() connection:Disable() end)
        if not disabled then
            disabled = pcall(function() connection:Disconnect() end)
        end
        if disabled then
            patched = patched + 1
            stored[#stored + 1] = connection
        end
    end
    self._RigSyncConns = stored
    print("[MilfaCheatHUB] RigSync: отключено обработчиков: " .. patched)
end

function Features:Build()
    local colors = self.Config.Colors
    local settings = self.Config.Settings

    local eggsTab = self.UI:CreateTab("Яйца", "EGG", colors.World)
    local autoTab = self.UI:CreateTab("Авто", "BOT", colors.Combat)
    local espTab = self.UI:CreateTab("ESP", "ESP", colors.ESP)
    local playerTab = self.UI:CreateTab("Игрок", "PLR", colors.Player)
    local pointsTab = self.UI:CreateTab("Точки", "POS", colors.Movement)
    local systemTab = self.UI:CreateTab("Система", "SYS", colors.Misc)

    -- ============================== ЯЙЦА ==============================
    self.UI:AddHeading(eggsTab, "Динамический сканер яиц")
    self.EggStatus = self.UI:AddText(eggsTab, "Состояние", "Первый скан запускается после открытия GUI")
    self.UI:AddButton(eggsTab, "Обновить список яиц", function()
        local ok, result = pcall(function() return self:UpdateEggs() end)
        if not ok then self.EggStatus:Set("Ошибка сканера: " .. tostring(result)) end
    end)

    self.RarityChips = self.UI:AddChips(eggsTab, "Фильтр редкости (список, ESP-фильтр и автокража)",
        self.Rarity.Ids(), settings.RarityFilter, function(list)
            settings.RarityFilter = list
        end)

    self.MaxDistanceSlider = self.UI:AddSlider(eggsTab, "Макс. дистанция списка", 0, 2000, settings.MaxListDistance, " st", function(value)
        settings.MaxListDistance = value
    end)
    self.UI:AddDropdown(eggsTab, "Сортировка списка", {"rarity", "distance"}, settings.SortMode, function(option)
        settings.SortMode = option
        if self.FilteredRecords then
            self.Eggs:Sort(self.FilteredRecords, option)
            pcall(function() self:UpdateEggs() end)
        end
    end)
    self.UI:AddToggle(eggsTab, "Автообновление списка", settings.EggListAutoRefresh, function(value)
        settings.EggListAutoRefresh = value
    end)

    self.UI:AddSection(eggsTab, "Список яиц")
    self.EggList = self.UI:CreateEggList(eggsTab, self.Rarity)
    self.UI:AddText(eggsTab, "Кнопки", "TP — телепорт к яйцу, СТЛ — украсть это яйцо (TP + Carry + Place).")
    self.UI:AddText(eggsTab, "Важно", "Прямого ремоута кражи у игроков в игре нет — автокража работает с полевыми яйцами биомов и промптами. FirstAreaSlotKey подставляется автоматически.")

    -- ============================== АВТО ==============================
    self.UI:AddHeading(autoTab, "Автокража")
    self.StealStatus = self.UI:AddText(autoTab, "Кража", "выключено")
    self.UI:AddToggle(autoTab, "Автокража включена", settings.AutoSteal, function(value)
        settings.AutoSteal = value
        if not value then self.Automation.Status.Steal = "выключено" end
    end)
    self.UI:AddDropdown(autoTab, "Приоритет цели", {"rarity", "distance"}, settings.StealPriority, function(option)
        settings.StealPriority = option
    end)
    self.UI:AddSlider(autoTab, "Радиус поиска целей", 50, 2000, settings.StealRadius, " st", function(value)
        settings.StealRadius = value
    end)
    self.UI:AddSlider(autoTab, "Пауза между попытками", 0.5, 10, settings.StealDelay, " c", function(value)
        settings.StealDelay = value
    end)
    self.UI:AddToggle(autoTab, "Телепорт к цели (иначе ходьба)", settings.StealTeleport, function(value)
        settings.StealTeleport = value
    end)
    self.UI:AddToggle(autoTab, "Нести домой и ставить", settings.AutoReturn, function(value)
        settings.AutoReturn = value
    end)
    self.UI:AddToggle(autoTab, "Сбрасывать яйцо из рук", settings.AutoDrop, function(value)
        settings.AutoDrop = value
    end)
    self.UI:AddToggle(autoTab, "Автопостановка яиц из инвентаря", settings.AutoPlace, function(value)
        settings.AutoPlace = value
    end)

    self.UI:AddSection(autoTab, "Автоматика базы")
    self.HatchStatus = self.UI:AddText(autoTab, "Вылупление", "выключено")
    self.UI:AddToggle(autoTab, "Автовылупление (GrowingEggs + AskHatch)", settings.AutoHatch, function(value)
        settings.AutoHatch = value
        if not value then self.Automation.Status.Hatch = "выключено" end
    end)
    self.CollectStatus = self.UI:AddText(autoTab, "Доход", "выключено")
    self.UI:AddToggle(autoTab, "Автосбор дохода (AskCollect)", settings.AutoCollect, function(value)
        settings.AutoCollect = value
        if value then self.Automation.Status.Collect = "включено" end
    end)
    self.UI:AddToggle(autoTab, "Дорожка: вставать (AskWearStill)", settings.AutoTreadmill, function(value)
        settings.AutoTreadmill = value
    end)
    self.TreadmillStatus = self.UI:AddText(autoTab, "Дорожка", "выключено")
    self.UI:AddToggle(autoTab, "Дорожка: сходить каждые 5с (AskDoff)", settings.AutoDoff, function(value)
        settings.AutoDoff = value
    end)

    self.UI:AddSection(autoTab, "Автоулучшения")
    self.UpgradeStatus = self.UI:AddText(autoTab, "Апгрейды", "выключено")
    self.UI:AddToggle(autoTab, "Улучшать дорожку (AskTierRaise)", settings.AutoTreadmillUpgrade, function(value)
        settings.AutoTreadmillUpgrade = value
    end)
    self.UI:AddToggle(autoTab, "Улучшать базу (AskBaseTierRaise)", settings.AutoBaseUpgrade, function(value)
        settings.AutoBaseUpgrade = value
    end)
    self.UI:AddSlider(autoTab, "Пауза между апгрейдами", 30, 600, settings.UpgradeInterval, " c", function(value)
        settings.UpgradeInterval = value
    end)

    self.UI:AddSection(autoTab, "Питомцы и защита")
    self.PetsStatus = self.UI:AddText(autoTab, "Питомцы", "выключено")
    self.UI:AddToggle(autoTab, "Надевать лучших питомцев (PenRoster)", settings.AutoPetsBest, function(value)
        settings.AutoPetsBest = value
    end)
    self.UI:AddSlider(autoTab, "Сколько питомцев надевать", 1, 8, settings.PetSlots, "", function(value)
        settings.PetSlots = value
    end)
    self.TrapsStatus = self.UI:AddText(autoTab, "Ловушки", "выключено")
    self.UI:AddToggle(autoTab, "Отключать чужие ловушки (__DEBRIS)", settings.NeutralizeTraps, function(value)
        settings.NeutralizeTraps = value
    end)

    self.UI:AddSection(autoTab, "Автопродажа с фильтром редкости")
    self.SellStatus = self.UI:AddText(autoTab, "Продажа", "выключено")
    self.UI:AddToggle(autoTab, "Продавать яйца", settings.AutoSellEggs, function(value)
        settings.AutoSellEggs = value
        if not value then self.Automation.Status.Sell = "выключено" end
    end)
    self.UI:AddToggle(autoTab, "Продавать питомцев", settings.AutoSellPets, function(value)
        settings.AutoSellPets = value
        if not value then self.Automation.Status.Sell = "выключено" end
    end)
    self.UI:AddChips(autoTab, "НЕ продавать эти редкости (остальное продаётся)",
        self.Rarity.Ids(), settings.KeepRarities, function(list)
            settings.KeepRarities = list
        end)
    self.UI:AddSlider(autoTab, "Пауза между продажами", 3, 60, settings.SellInterval, " c", function(value)
        settings.SellInterval = value
    end)

    self.UI:AddSection(autoTab, "Сервер и события")
    self.UI:AddToggle(autoTab, "Смена сервера при пустых целях", settings.AutoServerHop, function(value)
        settings.AutoServerHop = value
    end)
    self.UI:AddButton(autoTab, "Сменить сервер сейчас", function()
        self.Automation:ServerHop()
    end)
    self.UI:AddButton(autoTab, "Скормить яйцо монстру (событие)", function()
        local ok, info = self.Automation:FeedMonster()
        if not ok then self.StealStatus:Set("Монстр: " .. tostring(info or "не найден")) end
    end)

    -- ============================== ESP ==============================
    self.UI:AddHeading(espTab, "Неоновый Egg ESP")
    self.EspStatus = self.UI:AddText(espTab, "ESP", "Выключен")
    self.UI:AddToggle(espTab, "Показывать яйца", settings.EggESP, function(value)
        settings.EggESP = value
        self.ESP:SetEnabled(value)
        self.EspStatus:Set(value and "Включён • автообновление" or "Выключен")
        if value then pcall(function() self:UpdateEggs() end) end
    end)
    self.UI:AddToggle(espTab, "Цвет и редкость в подписи", settings.ShowRarity, function(value)
        settings.ShowRarity = value
    end)
    self.UI:AddToggle(espTab, "Показывать дистанцию", settings.ShowDistance, function(value)
        settings.ShowDistance = value
    end)
    self.UI:AddToggle(espTab, "ESP только по фильтру редкости", settings.EspFilterOnly, function(value)
        settings.EspFilterOnly = value
    end)
    self.UI:AddSlider(espTab, "Дальность ESP", 200, 5000, settings.EspMaxDistance, " st", function(value)
        settings.EspMaxDistance = value
    end)

    -- ============================== ИГРОК ==============================
    self.UI:AddHeading(playerTab, "Персонаж (стелс по умолчанию)")
    self.SpeedStatus = self.UI:AddText(playerTab, "Режим скорости", "Стелс: WalkSpeed остаётся 16, движение через CFrame")
    self.UI:AddToggle(playerTab, "СТЕЛС-скорость (не трогает WalkSpeed)", settings.StealthSpeed, function(value)
        settings.StealthSpeed = value
        self.SpeedStatus:Set(value and "Стелс: WalkSpeed = 16, движение через CFrame" or "Классика: прямой WalkSpeed (риск BAC)")
        if not value then self.Player:ApplySpeed() end
    end)
    self.UI:AddSlider(playerTab, "Стелс-скорость, ст/с (держи < 60)", 16, 90, settings.StealthSpeedValue, "", function(value)
        settings.StealthSpeedValue = value
    end)
    self.UI:AddSlider(playerTab, "Классическая скорость (WalkSpeed)", 16, 250, settings.WalkSpeed, "", function(value)
        settings.WalkSpeed = value
        self.Player:ApplySpeed()
        if self.Stealth and self.Stealth.AntiCheat and not settings.StealthSpeed then
            self.Stealth.AntiCheat.EnableSpeedLock(value)
        end
    end)
    self.UI:AddSlider(playerTab, "Прыжок (JumpPower)", 50, 250, settings.JumpPower, "", function(value)
        settings.JumpPower = value
        self.Player:ApplySpeed()
    end)
    self.UI:AddButton(playerTab, "Сбросить скорость и прыжок", function()
        self.Player:ResetSpeed()
    end)
    self.UI:AddToggle(playerTab, "Бесконечный прыжок", settings.InfiniteJump, function(value)
        self.Player:SetInfiniteJump(value)
    end)
    self.UI:AddToggle(playerTab, "Noclip (сквозь стены)", settings.Noclip, function(value)
        self.Player:SetNoclip(value)
    end)
    self.UI:AddToggle(playerTab, "Телепорт кликом (ЛКМ)", settings.ClickTP, function(value)
        self.Player:SetClickTP(value)
    end)
    self.UI:AddToggle(playerTab, "Anti-AFK (не кикать за простой)", settings.AntiAFK, function(value)
        self.Player:SetAntiAFK(value)
    end)

    -- ============================== ТОЧКИ ==============================
    self.UI:AddHeading(pointsTab, "Живые позиции карты")
    self.PointStatus = self.UI:AddText(pointsTab, "Результат", self.Positions:Summary())
    self.PointList = self.UI:AddText(pointsTab, "Первые точки", self.Positions:ListText(3))
    self.UI:AddButton(pointsTab, "Пересканировать точки", function()
        self.PointStatus:Set(self.Positions:Summary())
        self.PointList:Set(self.Positions:ListText(3))
    end)
    self.UI:AddButton(pointsTab, "Телепорт на базу", function()
        local home = self.Positions:GetHome()
        if home then
            self:GlideTo(home, 3)
        end
    end)

    -- ============================== СИСТЕМА ==============================
    self.UI:AddHeading(systemTab, "СТЕЛС GHOST (v0.6.0)")
    local mountKind = self.Stealth and tostring(self.Stealth.MountKind) or "неизвестно"
    local mountNote = (mountKind == "PlayerGui")
        and "Обычный PlayerGui, чистое имя — профиль проверенных хабов (кика нет)"
        or "Скрытый маунт (gethui/CoreGui)"
    self.StealthStatus = self.UI:AddText(systemTab, "Маунт GUI: " .. mountKind, mountNote)
    self.UI:AddToggle(systemTab, "Безопасные телепорты (glide)", settings.SafeTeleport, function(value)
        settings.SafeTeleport = value
        if self.Stealth then self.Stealth.SafeTeleport = value end
    end)
    self.UI:AddSlider(systemTab, "Скорость glide, ст/с (держи < 70)", 20, 100, settings.GlideSpeed, "", function(value)
        settings.GlideSpeed = value
        if self.Stealth then self.Stealth.GlideSpeed = value end
    end)
    self.UI:AddToggle(systemTab, "Человеческие задержки (джиттер)", settings.HumanizeDelays, function(value)
        settings.HumanizeDelays = value
    end)

    -- ================== ОБХОД АНТИЧИТА (BAC, opt-in) ==================
    -- Полеarm данные: v0.4.1 хук namecall -> BAC-4513, v0.5.0 freeze/masking -> BAC-2516.
    -- Рабочие хабы (boblo и др.) бегают ВООБЩЕ без хуков. Поэтому GHOST по умолчанию.
    local AC = self.Stealth and self.Stealth.AntiCheat or nil
    if AC then
        local function acStatusText()
            return AC:Summary()
        end
        self.ACStatus = self.UI:AddText(systemTab, "Режим BAC", acStatusText())
        self.UI:AddToggle(systemTab, "АГРЕССИВНЫЙ обход BAC (не рекомендуется: палятся хуки)", settings.BacAutoBypass, function(value)
            settings.BacAutoBypass = value
            task.spawn(function()
                AC:Init(self.Stealth, settings, value)
                if self.ACStatus then self.ACStatus:Set(acStatusText()) end
            end)
        end)
        self.UI:AddToggle(systemTab, "  [агрессивный] Блокировать клиентский Kick", settings.BlockKick, function(value)
            settings.BlockKick = value
            if self.Stealth then self.Stealth.BlockKick = value end
        end)
        self.UI:AddToggle(systemTab, "  [агрессивный] Заморозка состояний AC (getgc)", settings.FreezeACStates, function(value)
            settings.FreezeACStates = value
        end)
        self.UI:AddToggle(systemTab, "  [агрессивный] Ослепить сэмплер скорости", settings.BlindSamplers, function(value)
            settings.BlindSamplers = value
        end)
        self.UI:AddToggle(systemTab, "  [агрессивный] Маскировать Http-пробы (риск BAC-2516)", settings.MaskHttpProbes, function(value)
            settings.MaskHttpProbes = value
        end)
        self.UI:AddButton(systemTab, "Применить обход заново (переинициализация)", function()
            task.spawn(function()
                AC:Init(self.Stealth, settings, settings.BacAutoBypass == true)
                if self.ACStatus then self.ACStatus:Set(acStatusText()) end
            end)
        end)
    end

    -- ============ ИГРОВЫЕ ПОМОЩНИКИ (проверено сообществом) ============
    self.UI:AddHeading(systemTab, "Игровые помощники")
    self.UI:AddToggle(systemTab, "Быстрый перенос яйца (HoldDuration=0 у CarryAreaEgg)", settings.FastPrompt, function(value)
        settings.FastPrompt = value
        task.spawn(function() self:ApplyFastPrompt(value) end)
    end)
    self.UI:AddToggle(systemTab, "Отключить RigSync-ресеты (мягкий анти-ТП)", settings.RigSyncCut, function(value)
        settings.RigSyncCut = value
        task.spawn(function() self:ApplyRigSyncCut(value) end)
    end)
    self.UI:AddSlider(systemTab, "Лимит AskHatch за такт", 1, 8, settings.MaxHatchPerTick, "", function(value)
        settings.MaxHatchPerTick = value
    end)
    self.UI:AddButton(systemTab, "PANIC: убрать все следы (GUI, ESP, скорость)", function()
        local env = (getgenv and getgenv()) or _G
        if env.MilfaPanic then env.MilfaPanic() end
    end)
    self.UI:AddButton(systemTab, "Диагностика в консоль (F9)", function()
        local env = (getgenv and getgenv()) or _G
        if env.MilfaDiagnostics then
            env.MilfaDiagnostics()
            self.StealthStatus:Set("Диагностика выведена в консоль F9")
        end
    end)
    self.UI:AddText(systemTab, "Как не словить BAC", "Держи GHOST-режим (хуки ВЫКЛ) — рабочие хабы бегают без единого хука. Стелс-скорость ON + SafeTeleport ON + джиттер ON. Glide < 70, стелс-скорость < 60. Прямые TP с яйцом сервер отклоняет — только glide-ходьба.")

    self.UI:AddHeading(systemTab, "Диагностика MilfaCheatHUB")
    self.NetworkStatus = self.UI:AddText(systemTab, "Networking", self.Network:Summary())
    self.UI:AddButton(systemTab, "Проверить известные Remotes", function()
        self.NetworkStatus:Set(self.Network:Summary())
    end)
    self.UI:AddButton(systemTab, "Найти Sell-ремоуты", function()
        local remotes = self.Eggs:FindSellRemotes()
        local lines = {}
        for _, remote in ipairs(remotes) do
            lines[#lines + 1] = remote.ClassName .. " " .. remote.Name
        end
        self.NetworkStatus:Set(#lines > 0 and ("Найдено: " .. table.concat(lines, ", ")) or "Sell-ремоуты не найдены")
    end)
    self.UI:AddButton(systemTab, "Дамп всех Remotes в консоль (F9)", function()
        local folder = self.Network:GetFolder()
        local count = 0
        if folder then
            for _, instance in ipairs(folder:GetDescendants()) do
                if instance:IsA("RemoteFunction") or instance:IsA("RemoteEvent") then
                    print("[MilfaCheatHUB] " .. instance.ClassName .. " " .. instance.Name)
                    count = count + 1
                end
            end
        end
        print("[MilfaCheatHUB] Всего: " .. count)
    end)
    self.FpsStatus = self.UI:AddText(systemTab, "Производительность", "Обычный режим")
    self.UI:AddToggle(systemTab, "Лёгкий FPS-режим", false, function(value)
        self.Config.Settings.FpsMode = value
        self.FpsStatus:Set(value and "Применяем настройки..." or "Восстанавливаем настройки...")
        self:SetFpsMode(value)
        self.FpsStatus:Set(value and "Эффекты и тени временно выключены" or "Настройки восстановлены")
    end)
    self.UI:AddText(
        systemTab,
        "Сборка " .. self.Config.Version,
        "STEALTH: скрытый маунт GUI/ESP, случайные имена, glide-телепорты, стелс-скорость без WalkSpeed, джиттер задержек, PANIC (getgenv().MilfaPanic()). 50+ функций из 0.3.x сохранены."
    )
end

function Features:Start()
    if self.Running then return end
    self.Running = true

    task.spawn(function()
        task.wait(0.5)
        pcall(function() self:UpdateEggs() end)
        while self.Running and self.Alive() do
            local settings = self.Config.Settings
            if settings.EggESP or settings.EggListAutoRefresh then
                pcall(function() self:UpdateEggs() end)
            end
            pcall(function() self:RefreshStatuses() end)
            task.wait(math.max(1.5, settings.RefreshSeconds or 3))
        end
    end)

    self.Automation:Start(self.Alive)
end

function Features:Destroy()
    self.Running = false
    self.Automation:Destroy()
    self.ESP:SetEnabled(false)
    self.Player:Destroy()
    pcall(function() self:ApplyFastPrompt(false) end)
    pcall(function() self:ApplyRigSyncCut(false) end)
    if self.Config.Settings.FpsMode then
        self.Config.Settings.FpsMode = false
        self:SetFpsMode(false)
    end
end

return Features
