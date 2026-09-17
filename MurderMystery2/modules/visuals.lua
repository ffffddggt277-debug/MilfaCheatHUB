-- MilfaCheatHUB • Murder Mystery 2
-- Visuals: fullbright, no fog, corpse/barrier cleanup, FPS mode v0.1.0.
--
-- All client-side Lighting tweaks (zero server footprint):
--   * Fullbright: brightness 3, clock 14, ambient light gray, no color shift;
--   * NoFog: FogEnd 100000, FogStart 0, expose desaturated fog color;
--   * corpses: MM2 ragdolls are workspace children named "Raggy";
--   * barriers: Model "GlitchProof" (map edge walls) — removal is client-side
--     only and harmless to the server;
--   * FPS mode: kill particles/sparkles/shadows for weak phones.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Visuals = {}

Visuals.Debug = false

local ConfigRef = nil
local connections = {}
local savedLighting = nil
local fullbrightOn = false
local noFogOn = false

local function note(...)
    if Visuals.Debug then print("[mh vis]", ...) end
end

local function snapshotLighting()
    if savedLighting then return end
    savedLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        FogColor = Lighting.FogColor,
    }
end

function Visuals.SetFullbright(value)
    fullbrightOn = value and true or false
    if value then
        snapshotLighting()
        pcall(function()
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
            Lighting.GlobalShadows = false
        end)
    else
        if savedLighting then
            pcall(function()
                Lighting.Brightness = savedLighting.Brightness
                Lighting.ClockTime = savedLighting.ClockTime
                Lighting.Ambient = savedLighting.Ambient
                Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
                Lighting.GlobalShadows = savedLighting.GlobalShadows
            end)
        end
    end
end

function Visuals.SetNoFog(value)
    noFogOn = value and true or false
    if value then
        snapshotLighting()
        pcall(function()
            Lighting.FogEnd = 100000
            Lighting.FogStart = 0
        end)
    else
        if savedLighting then
            pcall(function()
                Lighting.FogEnd = savedLighting.FogEnd
                Lighting.FogStart = savedLighting.FogStart
                Lighting.FogColor = savedLighting.FogColor
            end)
        end
    end
end

---------------------------------------------------------------------
-- Corpse & barrier cleanup
---------------------------------------------------------------------

local function sweepNamed(parent, name)
    local count = 0
    pcall(function()
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == name then
                child:Destroy()
                count = count + 1
            end
        end
    end)
    return count
end

function Visuals.SetRemoveRagdolls(value)
    ConfigRef.Settings.RemoveRagdolls = value and true or false
    if value then
        sweepNamed(Workspace, "Raggy")
        connections[#connections + 1] = Workspace.ChildAdded:Connect(function(child)
            if ConfigRef.Settings.RemoveRagdolls and child.Name == "Raggy" then
                task.wait(0.5)
                pcall(function() child:Destroy() end)
            end
        end)
    else
        for _, connection in ipairs(connections) do connection:Disconnect() end
        connections = {}
    end
end

function Visuals.SetRemoveBarriers(value)
    ConfigRef.Settings.RemoveBarriers = value and true or false
    if value then
        pcall(function()
            for _, descendant in ipairs(Workspace:GetDescendants()) do
                if descendant.Name == "GlitchProof" then
                    descendant:Destroy()
                end
            end
        end)
        note("barriers removed")
    end
end

---------------------------------------------------------------------
-- FPS mode
---------------------------------------------------------------------

function Visuals.SetFpsMode(value)
    pcall(function()
        if value then
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 950
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        else
            if savedLighting then
                Lighting.GlobalShadows = savedLighting.GlobalShadows
                Lighting.FogEnd = savedLighting.FogEnd
            end
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        end
    end)
end

---------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------

function Visuals.Configure(config)
    ConfigRef = config
    Visuals.Debug = config.Settings.DebugLogs == true
end

function Visuals.Destroy()
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
    Visuals.SetFullbright(false)
    Visuals.SetNoFog(false)
    Visuals.SetFpsMode(false)
end

return Visuals
