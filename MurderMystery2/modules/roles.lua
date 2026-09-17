-- MilfaCheatHUB • Murder Mystery 2
-- Role detection core v0.4.1 (FIXED against live scripts).
--
-- ПРИЧИНА КРАСНЫХ КРУГОВ v0.2.0: удалённый поиск был НЕ рекурсивным, а
-- GetPlayerData лежит НЕ в корне ReplicatedStorage (он под Remotes/Extras —
-- подтверждено рабочими скриптами R3TH/KittyHub). Из-за этого роли не
-- находились вообще -> «роль: ?», пустые алерты, мёртвые аимы и телепорты.
-- KittyHub: "MM2 moves these between updates, so resolve by recursive name
-- lookup and re-resolve if the cached instance gets reparented."
--
-- Каналы данных:
--   1) GetPlayerData (RemoteFunction, позиция в дереве НЕ важна):
--      InvokeServer() -> {[name] = {Role=..., Killed=..., Dead=...}};
--   2) пуш Remotes.Gameplay.PlayerDataChanged (RemoteEvent): сервер шлёт либо
--      ЦЕЛИКОМ таблицу, либо ОДНУ запись (name, entry) — обрабатываем оба
--      варианта (KittyHub);
--   3) фолбэк по тулзам: нож = маньяк, пистолет = шериф (мирный с пистолетом
--      = герой); чужой рюкзак не реплицируется, поэтому сканируем Character
--      (вынутое оружие) + Backpack (реплицируется только свой).
-- LocalRole защёлкивается на раунд (нож покидает руку при броске, данные
-- мигают — держим последнее известное значение).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Roles = {}

Roles.Cache = {}          -- [playerName] = "Murderer" | "Sheriff" | "Hero" | "Innocent" | "Unknown"
Roles.Alive = {}          -- [playerName] = boolean
Roles.LocalRole = nil
Roles.Debug = false
Roles.OnUpdate = nil
Roles.RemotesFound = ""   -- строка для диагностики

local dataRemote = nil
local pushEvent = nil
local connections = {}
local refreshThread = nil
local lastSearchAt = 0
local localPlayer = Players.LocalPlayer

local function note(...)
    if Roles.Debug then print("[mh roles]", ...) end
end

-- Рекурсивный резолвер с переподключением (ремоуты переезжают между апдейтами).
local function resolveRemote(name, expectClass)
    local found
    pcall(function() found = ReplicatedStorage:FindFirstChild(name, true) end)
    if found and (not expectClass or found:IsA(expectClass)) then
        return found
    end
    return nil
end

local function findRemotes(force)
    if not force and dataRemote and dataRemote.Parent and pushEvent and pushEvent.Parent then
        return
    end
    -- если что-то не найдено — полный рекурсивный обход не чаще раза в 15с
    if not force and os.clock() - lastSearchAt < 15 then return end
    lastSearchAt = os.clock()
    -- Ищем ТОЛЬКО если кэш умер (KittyHub): рекурсивный обход каждый рефреш
    -- дорого стоит на телефоне.
    local newData = resolveRemote("GetPlayerData", "RemoteFunction")
    if newData and newData ~= dataRemote then
        dataRemote = newData
    end
    local newPush = resolveRemote("PlayerDataChanged", "RemoteEvent")
    if newPush ~= pushEvent then
        pushEvent = newPush
        Roles._pushConnected = false  -- переподписаться на новый инстанс
    end
    Roles.RemotesFound = "data=" .. tostring(dataRemote ~= nil) ..
        " push=" .. tostring(pushEvent ~= nil)
    if Roles.Debug then note(Roles.RemotesFound) end
end

local function normalizeRole(value)
    if type(value) ~= "string" or value == "" then return "Unknown" end
    local lowered = string.lower(value)
    if string.find(lowered, "murder", 1, true) then return "Murderer" end
    if string.find(lowered, "sheriff", 1, true) then return "Sheriff" end
    if string.find(lowered, "hero", 1, true) then return "Hero" end
    if string.find(lowered, "inno", 1, true) then return "Innocent" end
    return "Unknown"
end

local function applyEntry(name, record)
    if type(name) ~= "string" or type(record) ~= "table" then return false end
    local role = normalizeRole(record.Role)
    -- Живость: единственное надёжное поле — Dead; поле Killed в живой игре
    -- означает «убил ли» (у маньяка становится truthy ПОСЛЕ первого убийства,
    -- и если считать его смертью — маньяк пропадает с ESP, как было в v0.3.1).
    -- Окончательную точку даёт Humanoid в Roles.IsAlive (персонаж авторитетен).
    Roles.Cache[name] = role
    Roles.Alive[name] = record.Dead ~= true
    if localPlayer and name == localPlayer.Name and role ~= "Unknown" then
        -- не даём случайному пушу сбить защёлкнутого маньяка на мирного
        if Roles.LocalRole ~= "Murderer" or role ~= "Innocent" then
            Roles.LocalRole = role
        end
    end
    return true
end

-- Политика KittyHub: заменять таблицу ТОЛЬКО если пуш реально несёт роли;
-- частичный мусор без ролей игнорируем (иначе wiping таблицы = «мы ничего не знаем»).
local function applyTable(payload)
    if type(payload) ~= "table" then return end
    local roleCount = 0
    for _, record in pairs(payload) do
        if type(record) == "table" and type(record.Role) == "string" and record.Role ~= "" then
            roleCount = roleCount + 1
        end
    end
    if roleCount == 0 then return end
    local seen = {}
    for name, record in pairs(payload) do
        if type(name) == "string" and type(record) == "table" then
            applyEntry(name, record)
            seen[name] = true
        end
    end
    -- игроки, пропавшие из таблицы: новый раунд или выход
    for name in pairs(Roles.Cache) do
        if not seen[name] then
            Roles.Cache[name] = nil
            Roles.Alive[name] = nil
            if localPlayer and name == localPlayer.Name then
                Roles.LocalRole = nil
            end
        end
    end
    if Roles.OnUpdate then pcall(Roles.OnUpdate, Roles.Cache) end
end

-- TOOL-фолбэк: вынутый нож/пистолет в Character виден всем; свой рюкзак тоже
-- реплицируется. Мирный с пистолетом = герой.
local function detectFromTools()
    for _, player in ipairs(Players:GetPlayers()) do
        local held = nil
        pcall(function()
            local character = player.Character
            local backpack = player:FindFirstChildOfClass("Backpack")
            local function has(container, toolName)
                return container and container:FindFirstChild(toolName) ~= nil
            end
            if has(character, "Knife") or (player == localPlayer and has(backpack, "Knife")) then
                held = "Murderer"
            elseif has(character, "Gun") or (player == localPlayer and has(backpack, "Gun")) then
                held = (player == localPlayer and Roles.LocalRole == "Innocent") and "Hero" or "Sheriff"
            end
        end)
        if held and held ~= Roles.Cache[player.Name] then
            Roles.Cache[player.Name] = held
            Roles.Alive[player.Name] = true
            if player == localPlayer then
                if held == "Hero" or Roles.LocalRole == nil then Roles.LocalRole = held end
            end
            note("tools: " .. player.Name .. " = " .. held)
        end
    end
end

function Roles.Refresh()
    -- findRemotes(false): перепоиск ТОЛЬКО если кэш умер (рекурсивный обход
    -- ReplicatedStorage каждый тик — дорого для телефона)
    findRemotes(false)
    Roles.Listen()

    if dataRemote then
        local ok, payload = pcall(function() return dataRemote:InvokeServer() end)
        if ok and type(payload) == "table" then
            applyTable(payload)
        else
            note("pull failed: " .. tostring(payload))
        end
    end
    detectFromTools()
    if Roles.OnUpdate then pcall(Roles.OnUpdate, Roles.Cache) end
end

function Roles.Get(playerName)
    return Roles.Cache[playerName or ""]
end

function Roles.IsAlive(playerName)
    local name = playerName or ""
    -- Персонаж авторитетен и реплицируется всем: если Humanoid жив — жив.
    local player = Players:FindFirstChild(name)
    local character = player and player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then return humanoid.Health > 0 end
    end
    local value = Roles.Alive[name]
    if value == nil then return true end
    return value and true or false
end

function Roles.ColorFor(role)
    local colors = {
        Murderer = Color3.fromRGB(255, 64, 64),
        Sheriff = Color3.fromRGB(64, 156, 255),
        Hero = Color3.fromRGB(255, 196, 47),
        Innocent = Color3.fromRGB(82, 255, 143),
    }
    return colors[role] or Color3.fromRGB(160, 160, 170)
end

function Roles.Label(role)
    local labels = {
        Murderer = "МАНЬЯК",
        Sheriff = "ШЕРИФ",
        Hero = "ГЕРОЙ",
        Innocent = "мирный",
        Unknown = "???",
    }
    return labels[role] or tostring(role)
end

function Roles.CountAliveByRole(role)
    local count = 0
    for name, cached in pairs(Roles.Cache) do
        if cached == role and Roles.IsAlive(name) then count = count + 1 end
    end
    return count
end

function Roles.FindByRole(role)
    local list = {}
    for name, cached in pairs(Roles.Cache) do
        if cached == role and Roles.IsAlive(name) then list[#list + 1] = name end
    end
    return list
end

function Roles.LocalIsMurderer()
    return Roles.LocalRole == "Murderer"
end

function Roles.LocalIsSheriff()
    return Roles.LocalRole == "Sheriff" or Roles.LocalRole == "Hero"
end

function Roles.Listen()
    if pushEvent and not Roles._pushConnected then
        Roles._pushConnected = true
        -- переподписка на новый инстанс: старый коннект гасим (ремоуты переезжают)
        if Roles._pushConnection then
            pcall(function() Roles._pushConnection:Disconnect() end)
            Roles._pushConnection = nil
        end
        local connection = pushEvent.OnClientEvent:Connect(function(first, second)
            if type(first) == "table" then
                applyTable(first)               -- форма 1: вся таблица
            elseif second ~= nil then
                -- форма 2: (имя ИЛИ Player-инстанс, запись) — KittyHub приводит
                -- Player к имени, иначе запись молча терялась
                local name = first
                if typeof(first) == "Instance" and first:IsA("Player") then
                    name = first.Name
                end
                if applyEntry(name, second) and Roles.OnUpdate then
                    pcall(Roles.OnUpdate, Roles.Cache)
                end
            end
        end)
        Roles._pushConnection = connection
        connections[#connections + 1] = connection
    end
end

-- Сброс на новом раунде (KittyHub clearRoles): протухшие роли прошлого
-- раунда хуже, чем их отсутствие. Триггеры: карта добавлена/удалена (ребёнок
-- workspace с CoinContainer, не Lobby) и собственный респавн.
function Roles.ResetRound()
    Roles.Cache = {}
    Roles.Alive = {}
    Roles.LocalRole = nil
    if Roles.OnUpdate then pcall(Roles.OnUpdate, Roles.Cache) end
    note("round reset")
end

function Roles.Start()
    if refreshThread then return end
    Roles._running = true  -- после Shutdown() цикл обязан стартовать заново
    refreshThread = task.spawn(function()
        while Roles._running ~= false do
            pcall(Roles.Refresh)
            task.wait(2.5)
        end
    end)
    if not Roles._roundBound then
        Roles._roundBound = true
        connections[#connections + 1] = workspace.ChildAdded:Connect(function(child)
            if child.Name ~= "Lobby" and child:IsA("Model") and child:FindFirstChild("CoinContainer") then
                Roles.ResetRound()
            end
        end)
        connections[#connections + 1] = workspace.ChildRemoved:Connect(function(child)
            -- FindFirstChild работает и на уже удалённом инстансе
            if child.Name ~= "Lobby" and child:IsA("Model") and child:FindFirstChild("CoinContainer") then
                Roles.ResetRound()
            end
        end)
        connections[#connections + 1] = localPlayer.CharacterAdded:Connect(function()
            Roles.ResetRound()
            task.delay(1.2, function()
                if Roles._running ~= false then pcall(Roles.Refresh) end
            end)
        end)
    end
end

function Roles.Shutdown()
    Roles._running = false
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
    Roles._pushConnected = false
    Roles._roundBound = false -- после рестарта триггеры раунда обязаны перепривязаться
    refreshThread = nil
end

Roles._running = true
Roles.Listen()
Roles.Start()

return Roles
