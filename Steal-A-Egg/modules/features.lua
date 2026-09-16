-- MilfaCheatHUB • feature controller
-- Connects the scanner, positions, ESP and interface.

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
        for _, object in ipairs(workspace:GetDescendants()) do
            if effectClasses[object.ClassName] then
                self.FpsOriginal[object] = object.Enabled
                object.Enabled = false
            elseif object:IsA("BasePart") then
                self.FpsOriginal[object] = object.CastShadow
                object.CastShadow = false
            end
        end
    else
        for object, value in pairs(self.FpsOriginal) do
            if object and object.Parent then
                pcall(function()
                    if object:IsA("BasePart") then object.CastShadow = value
                    else object.Enabled = value end
                end)
            end
        end
        self.FpsOriginal = {}
    end
end

function Features:Build()
    local colors = self.Config.Colors
    local eggsTab = self.UI:CreateTab("Яйца", "◇", colors.World)
    local espTab = self.UI:CreateTab("ESP", "◈", colors.ESP)
    local pointsTab = self.UI:CreateTab("Точки", "⌖", colors.Movement)
    local diagnosticsTab = self.UI:CreateTab("Система", "⚙", colors.Misc)

    self.UI:AddHeading(eggsTab, "Динамический сканер яиц")
    self.EggStatus = self.UI:AddText(eggsTab, "Состояние", "Ожидание первого сканирования...")
    self.UI:AddButton(eggsTab, "Обновить список яиц", function()
        local eggs = self.Scanner:GetEggs()
        self.EggStatus:Set(self.Scanner:Diagnostics())
        if self.ESP.Enabled then self.ESP:Refresh(eggs, self.Scanner) end
    end)
    self.UI:AddText(
        eggsTab,
        "Источник данных",
        "EggState/EggCmds и Workspace.AreaEggSlotsClient. UID и позиции не записываются постоянно."
    )

    self.UI:AddHeading(espTab, "Неоновый Egg ESP")
    self.EspStatus = self.UI:AddText(espTab, "ESP", "Выключен")
    self.UI:AddToggle(espTab, "Показывать яйца", self.Config.Settings.EggESP, function(value)
        self.Config.Settings.EggESP = value
        self.ESP:SetEnabled(value)
        self.EspStatus:Set(value and "Включён — обновляется автоматически" or "Выключен")
        if value then self.ESP:Refresh(self.Scanner:GetEggs(), self.Scanner) end
    end)
    self.UI:AddText(
        espTab,
        "Что отображается",
        "Название, биом и расстояние. Все элементы создаются только на клиенте и удаляются при закрытии GUI."
    )

    self.UI:AddHeading(pointsTab, "Живые позиции карты")
    self.PointStatus = self.UI:AddText(pointsTab, "Результат", self.Positions:Summary())
    self.PointList = self.UI:AddText(pointsTab, "Первые найденные точки", self.Positions:ListText(3))
    self.UI:AddButton(pointsTab, "Пересканировать точки", function()
        self.PointStatus:Set(self.Positions:Summary())
        self.PointList:Set(self.Positions:ListText(3))
    end)
    self.UI:AddText(
        pointsTab,
        "Принцип",
        "База, биомы и граница берутся из живых объектов. Статические координаты используются только как ориентиры."
    )

    self.UI:AddHeading(diagnosticsTab, "Диагностика MilfaCheatHUB")
    self.NetworkStatus = self.UI:AddText(diagnosticsTab, "Networking", self.Network:Summary())
    self.UI:AddButton(diagnosticsTab, "Проверить известные Remotes", function()
        self.NetworkStatus:Set(self.Network:Summary())
    end)
    self.FpsStatus = self.UI:AddText(diagnosticsTab, "Производительность", "Обычный режим")
    self.UI:AddToggle(diagnosticsTab, "Лёгкий FPS-режим", false, function(value)
        self.Config.Settings.FpsMode = value
        self:SetFpsMode(value)
        self.FpsStatus:Set(value and "Эффекты и тени временно выключены" or "Настройки восстановлены")
    end)
    self.UI:AddText(
        diagnosticsTab,
        "Сборка 0.1.0",
        "Первая версия: красивый UI, загрузка icon.png, сканер, точки, диагностика и Egg ESP."
    )
end

function Features:Start()
    if self.Running then return end
    self.Running = true

    task.spawn(function()
        while self.Running and self.Alive() do
            local ok, eggs = pcall(function() return self.Scanner:GetEggs() end)
            if ok then
                if self.EggStatus then self.EggStatus:Set(self.Scanner:Diagnostics()) end
                if self.ESP.Enabled then self.ESP:Refresh(eggs, self.Scanner) end
            end
            task.wait(self.Config.Settings.RefreshSeconds)
        end
    end)
end

function Features:Destroy()
    self.Running = false
    if self.Config.Settings.FpsMode then self:SetFpsMode(false) end
end

return Features
