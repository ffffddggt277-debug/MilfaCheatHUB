-- MilfaCheatHUB • feature controller v0.3

local Features = {}
Features.__index = Features

function Features.new(config, ui, scanner, network, positions, esp, eggs, automation, player, rarity, alive)
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
    self.Running = false
    self.FpsOriginal = {}
    return self
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
                    local root = self.Eggs:GetRoot()
                    if root then root.CFrame = CFrame.new(record.Position + Vector3.new(0, 2.5, 0)) end
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
    self.UI:AddToggle(autoTab, "Дорожка: вставать каждые 60с", settings.AutoTreadmill, function(value)
        settings.AutoTreadmill = value
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
    self.UI:AddHeading(playerTab, "Персонаж")
    self.UI:AddSlider(playerTab, "Скорость (WalkSpeed)", 16, 250, settings.WalkSpeed, "", function(value)
        settings.WalkSpeed = value
        self.Player:ApplySpeed()
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
            local root = self.Eggs:GetRoot()
            if root then root.CFrame = CFrame.new(home + Vector3.new(0, 3, 0)) end
        end
    end)

    -- ============================== СИСТЕМА ==============================
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
        "40+ функций: автокража, автопродажа с фильтром, ESP редкостей, скорость, noclip, автохатч, автосбор, сервер-хоп."
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
    if self.Config.Settings.FpsMode then
        self.Config.Settings.FpsMode = false
        self:SetFpsMode(false)
    end
end

return Features
