-- MilfaCheatHUB • Murder Mystery 2
-- BETA: round outcome prediction v0.2.0.
--
-- Honest heuristic (no magic): MM2 gives us roles, alive flags and positions.
-- The estimate weighs the factors that actually decide public rounds:
--   * is the sheriff/hero still alive (biggest single factor);
--   * murderer <-> sheriff distance (far = sheriff can safely snipe,
--     point blank = murderer usually stabs first);
--   * number of alive innocents (extra shields/time for the murderer to burn);
--   * timer pressure (under 20s a murderer cannot clear the map);
--   * whether YOU are the sheriff/hero (your skill changes the odds).
-- Output: probability split for the LAW side (sheriff/innocents surviving)
-- vs the MURDERER, plus the factor breakdown so the user sees the "why".

local Players = game:GetService("Players")

local Beta = {}

Beta.Debug = false
Beta.Last = nil   -- последний расчёт {Sheriff, Murderer, Text, Factors}

local ConfigRef = nil
local RolesRef = nil
local WorldRef = nil
local localPlayer = Players.LocalPlayer

local function note(...)
    if Beta.Debug then print("[mh beta]", ...) end
end

local function rootOf(playerName)
    local player = Players:FindFirstChild(playerName)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and root then return root end
    return nil
end

local function myRoot()
    local character = localPlayer and localPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

---------------------------------------------------------------------
-- Core computation
---------------------------------------------------------------------

-- Возвращает: {Sheriff = 0..100, Murderer = 0..100, Text = "...", Factors = {...}, Ready = bool}
function Beta.Compute()
    local murdererNames = RolesRef.FindByRole("Murderer")
    local sheriffNames = RolesRef.FindByRole("Sheriff")
    local heroNames = RolesRef.FindByRole("Hero")

    if #murdererNames == 0 then
        Beta.Last = {
            Ready = false,
            Sheriff = 50,
            Murderer = 50,
            Text = "маньяк неизвестен — обнови роли",
            Factors = {},
        }
        return Beta.Last
    end

    local lawAlive = #sheriffNames + #heroNames
    local innocentsAlive = 0
    for name, role in pairs(RolesRef.Cache) do
        if RolesRef.IsAlive(name) and (role == "Innocent" or role == "Unknown") then
            if Players:FindFirstChild(name) then
                innocentsAlive = innocentsAlive + 1
            end
        end
    end

    local murdererRoot = rootOf(murdererNames[1])
    local lawRoot = nil
    for _, name in ipairs(sheriffNames) do
        lawRoot = lawRoot or rootOf(name)
    end
    for _, name in ipairs(heroNames) do
        lawRoot = lawRoot or rootOf(name)
    end

    local factors = {}
    local score = 50  -- вероятность победы стороны ЗАКОНА (шериф/выжившие)

    local timer = nil
    pcall(function() timer = WorldRef.GetTimer() end)

    if lawAlive == 0 then
        -- шерифа нет: мирные спасаются только таймером
        score = 28
        factors[#factors + 1] = "шериф/герой мёртв — исход решает таймер"
        if timer and timer <= 20 then
            score = score + 34
            factors[#factors + 1] = "меньше 20 сек — маньяк не успеет перебить всех"
        else
            score = score - math.min(10, innocentsAlive)
            factors[#factors + 1] = "времени много, мирных мало (" .. tostring(innocentsAlive) .. ")"
        end
    else
        -- дистанция маньяк <-> закон
        if murdererRoot and lawRoot then
            local distMS = (murdererRoot.Position - lawRoot.Position).Magnitude
            if distMS > 60 then
                score = score + 16
                factors[#factors + 1] = string.format("шериф далеко от маньяка (%.0fм) — безопасная позиция", distMS)
            elseif distMS < 18 then
                score = score - 14
                factors[#factors + 1] = string.format("маньяк вплотную к шерифу (%.0fм) — нож быстрее пистолета", distMS)
            else
                score = score + 4
                factors[#factors + 1] = string.format("средняя дистанция маньяк/шериф (%.0fм)", distMS)
            end
        else
            score = score - 6
            factors[#factors + 1] = "позиции неизвестны (не видно персонажей)"
        end
        -- давление на мирных
        if murdererRoot and myRoot() then
            local closest = math.huge
            for _, name in ipairs(RolesRef.FindByRole("Innocent")) do
                local root = rootOf(name)
                if root then
                    local d = (root.Position - murdererRoot.Position).Magnitude
                    if d < closest then closest = d end
                end
            end
            if closest ~= math.huge and closest < 25 then
                score = score - 5
                factors[#factors + 1] = string.format("маньяк уже прижал мирных (%.0fм до ближайшего)", closest)
            end
        end
        -- мирные = запас времени
        if innocentsAlive > 0 then
            local bonus = math.min(12, innocentsAlive * 3)
            score = score + bonus
            factors[#factors + 1] = "живых мирных: " .. tostring(innocentsAlive) .. " — маньяку нужно время"
        end
        -- ты сам
        if RolesRef.LocalIsSheriff() then
            score = score + 9
            factors[#factors + 1] = "ты шериф/герой — исход частично в твоих руках"
        elseif RolesRef.LocalIsMurderer() then
            score = score - 9
            factors[#factors + 1] = "ты маньяк — действуй, и прогноз изменится"
        end
        -- таймер
        if timer and timer <= 20 then
            score = score + 8
            factors[#factors + 1] = "меньше 20 сек — маньяку некогда"
        end
    end

    if score > 100 then score = 100 end
    if score < 0 then score = 0 end

    local lawRounded = math.floor(score + 0.5)
    local verdict
    if lawRounded >= 70 then
        verdict = "склоняется к ШЕРИФУ/мирным"
    elseif lawRounded <= 30 then
        verdict = "склоняется к МАНЬЯКУ"
    else
        verdict = "шансы примерно равны"
    end

    Beta.Last = {
        Ready = true,
        Sheriff = lawRounded,
        Murderer = 100 - lawRounded,
        Text = string.format("шериф/мирные %d%% • маньяк %d%% — %s", lawRounded, 100 - lawRounded, verdict),
        Factors = factors,
    }
    note("prediction: " .. Beta.Last.Text)
    return Beta.Last
end

function Beta.Summary()
    local result = Beta.Last or Beta.Compute()
    return result.Text
end

function Beta.Configure(config, roles, world)
    ConfigRef = config
    RolesRef = roles
    WorldRef = world
    Beta.Debug = config.Settings.DebugLogs == true
end

return Beta
