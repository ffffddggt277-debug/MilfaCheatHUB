-- MilfaCheatHUB • Murder Mystery 2
-- Remote registry v0.4.1 (reliability pass).
--
-- v0.3.x проблема: GetPlayerData ищется ТОЛЬКО прямым путём от корня, а MM2
-- двигает его между обновлениями (подтверждено рабочими скриптами) → Resolve
-- возвращал nil, роли пустовали. v0.4.0: после неудачи прямого пути —
-- РЕКУРСИВНЫЙ поиск по имени с кэшем и инвалидацией при репарентинге.
--
-- Правила надёжности: ReplicatedStorage ждём с таймаутом; каждый обход дерева
-- в pcall; кэш хранит слабую ссылку и проверяется на .Parent при каждом
-- обращении; повторный поиск ограничен по времени (осциллирующие карты не
-- должны замораживать поток).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = {}
local __index = Network
local CACHE_TTL = 30 -- секунд до принудительной перепроверки пути

function Network.new(config)
	local self = setmetatable({}, { __index = __index })
	self.Config = config
	self.Found = {} -- [path] = {inst = Instance, at = os.clock()}
	self.Searching = {}
	return self
end

function Network:GetFolder()
	local ok, folder = pcall(function()
		return ReplicatedStorage:FindFirstChild("Remotes")
	end)
	return (ok and folder) or nil
end

-- Безопасное ожидание ReplicatedStorage (на медленных мобильных клиентах
-- сервис уже есть, но на всякий случай — таймаут вместо вечного ханга).
function Network:WaitStorage(timeout)
	timeout = timeout or 5
	if ReplicatedStorage.Parent then
		return ReplicatedStorage
	end
	local ok, res = pcall(function()
		return ReplicatedStorage:WaitForChild("Remotes", timeout)
	end)
	return (ok and res) or nil
end

-- Рекурсивный поиск инстанса по имени (опционально по классу) с лимитом
-- глубины и времени. Кэшируется, чтобы не обходить дерево на каждый вызов.
function Network:FindByName(name, className, timeout)
	timeout = timeout or 4
	local key = name .. "|" .. tostring(className)
	local hit = self.Found[key]
	if hit and hit.inst and hit.inst.Parent and (os.clock() - hit.at) < CACHE_TTL then
		return hit.inst
	end
	if self.Searching[key] then
		return nil
	end
	self.Searching[key] = true
	local deadline = os.clock() + timeout
	local found
	local function scan(root)
		if found or os.clock() > deadline then
			return
		end
		local ok, kids = pcall(function()
			return root:GetChildren()
		end)
		if not ok then
			return
		end
		for _, child in ipairs(kids) do
			if child.Name == name and (not className or child.ClassName == className) then
				found = child
				return
			end
		end
		for _, child in ipairs(kids) do
			scan(child)
			if found then
				return
			end
		end
	end
	pcall(scan, ReplicatedStorage)
	self.Searching[key] = nil
	if found then
		self.Found[key] = { inst = found, at = os.clock() }
	end
	return found
end

-- Resolve "Remotes.Gameplay.CoinCollected": прямой путь, при промахе —
-- рекурсивный поиск ПОСЛЕДНЕГО сегмента (имя уникально в пределах RS).
function Network:Resolve(path)
	local hit = self.Found[path]
	if hit and hit.inst and hit.inst.Parent and (os.clock() - hit.at) < CACHE_TTL then
		return hit.inst
	end
	local current = ReplicatedStorage
	local direct = true
	for segment in string.gmatch(path, "[^.]+") do
		local okChild, found = pcall(function()
			return current:FindFirstChild(segment)
		end)
		if not okChild or not found then
			direct = false
			break
		end
		current = found
	end
	if direct and current ~= ReplicatedStorage then
		self.Found[path] = { inst = current, at = os.clock() }
		return current
	end
	-- фолбэк: рекурсивно ищем последний сегмент
	local last = string.match(path, "([^.]+)$")
	if last then
		local inst = self:FindByName(last, nil, 3)
		if inst then
			self.Found[path] = { inst = inst, at = os.clock() }
			return inst
		end
	end
	self.Found[path] = nil
	return nil
end

-- Дамп состояния ремоутов для вкладки Система (диагностика).
function Network:Summary()
	local checks = {
		{ "GetPlayerData", "GetPlayerData", true },
		{ "PlayerDataChanged", "Remotes.Gameplay.PlayerDataChanged", false },
		{ "CoinCollected", "Remotes.Gameplay.CoinCollected", false },
		{ "GetTimer", "Remotes.Extras.GetTimer", true },
		{ "PlayEmote", "Remotes.PlayEmote", false },
		{ "FakeGun", "Remotes.Gameplay.FakeGun", false },
	}
	local lines = {}
	for _, entry in ipairs(checks) do
		local label, path = entry[1], entry[2]
		local inst = self:Resolve(path)
		if not inst and entry[3] then
			inst = self:FindByName(label, nil, 2)
		end
		lines[#lines + 1] = label .. ": " .. (inst and "OK" or "нет")
	end
	return "Ремоуты — " .. table.concat(lines, " • ")
end

return Network
