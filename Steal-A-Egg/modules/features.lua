-- MilfaCheatHUB • feature controller

local Features = {}
Features.__index = Features

function Features.new(config, ui, scanner, network, positions, esp, alive)
    local self = setmetatable({}, Features)
    self.Config = config
    self.UI = ui
    self.Scanner = scanner
    self.Network = network
    self.Positions = positions
    self.ESP = esp
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
    local eggs = self.Scanner:GetEggs()
    if self.EggStatus then self.EggStatus:Set("Найдено объектов яиц: " .. tostring(#eggs)) end
    if self.ESP.Enabled then self.ESP:Refresh(eggs, self.Scanner) end
    return eggs
end

function Features:Build()
    local colors = self.Config.Colors
    local eggsTab = self.UI:CreateTab("Яйца", "EGG", colors.World)
    local espTab = self.UI:CreateTab("ESP", "ESP", colors.ESP)
    local pointsTab = self.UI:CreateTab("Точки", "POS", colors.Movement)
    local diagnosticsTab = self.UI:CreateTab("Система", "SYS", colors.Misc)

    self.UI:AddHeading(eggsTab, "Динамический сканер яиц")
    self.EggStatus = self.UI:AddText(eggsTab, "Состояние", "Первый скан запускается после открытия GUI")
    self.UI:AddButton(eggsTab, "Обновить список яиц", function()
        local ok, result = pcall(function() return self:UpdateEggs() end)
        if not ok then self.EggStatus:Set("Ошибка сканера: " .. tostring(result)) end
    end)
    self.UI:AddText(
        eggsTab,
        "Источник данных",
        "EggState/EggCmds и AreaEggSlotsClient. UID и координаты всегда читаются заново."
    )

    self.UI:AddHeading(espTab, "Неоновый Egg ESP")
    self.EspStatus = self.UI:AddText(espTab, "ESP", "Выключен")
    self.UI:AddToggle(espTab, "Показывать яйца", self.Config.Settings.EggESP, function(value)
        self.Config.Settings.EggESP = value
        self.ESP:SetEnabled(value)
        self.EspStatus:Set(value and "Включён • автообновление каждые 3 секунды" or "Выключен")
        if value then pcall(function() self:UpdateEggs() end) end
    end)
    self.UI:AddText(
        espTab,
        "Отображение",
        "Название, биом и расстояние. При закрытии все Highlights и подписи удаляются."
    )

    self.UI:AddHeading(pointsTab, "Живые позиции карты")
    self.PointStatus = self.UI:AddText(pointsTab, "Результат", self.Positions:Summary())
    self.PointList = self.UI:AddText(pointsTab, "Первые точки", self.Positions:ListText(3))
    self.UI:AddButton(pointsTab, "Пересканировать точки", function()
        self.PointStatus:Set(self.Positions:Summary())
        self.PointList:Set(self.Positions:ListText(3))
    end)

    self.UI:AddHeading(diagnosticsTab, "Диагностика MilfaCheatHUB")
    self.NetworkStatus = self.UI:AddText(diagnosticsTab, "Networking", self.Network:Summary())
    self.UI:AddButton(diagnosticsTab, "Проверить известные Remotes", function()
        self.NetworkStatus:Set(self.Network:Summary())
    end)
    self.FpsStatus = self.UI:AddText(diagnosticsTab, "Производительность", "Обычный режим")
    self.UI:AddToggle(diagnosticsTab, "Лёгкий FPS-режим", false, function(value)
        self.Config.Settings.FpsMode = value
        self.FpsStatus:Set(value and "Применяем настройки..." or "Восстанавливаем настройки...")
        self:SetFpsMode(value)
        self.FpsStatus:Set(value and "Эффекты и тени временно выключены" or "Настройки восстановлены")
    end)
    self.UI:AddText(
        diagnosticsTab,
        "Сборка " .. self.Config.Version,
        "Компактный UI, асинхронная icon.png, безопасная загрузка, точки, ESP и полный cleanup."
    )
end

function Features:Start()
    if self.Running then return end
    self.Running = true

    task.spawn(function()
        task.wait(0.5)
        while self.Running and self.Alive() do
            if self.ESP.Enabled then
                pcall(function() self:UpdateEggs() end)
            end
            task.wait(self.Config.Settings.RefreshSeconds)
        end
    end)
end

function Features:Destroy()
    self.Running = false
    self.ESP:SetEnabled(false)
    if self.Config.Settings.FpsMode then
        self.Config.Settings.FpsMode = false
        self:SetFpsMode(false)
    end
end

return Features
