-- MilfaCheatHUB • Steal An Egg
-- Shared branding, palette, paths and defaults.

return {
    Name = "MilfaCheatHUB",
    Game = "Steal An Egg",
    Version = "0.2.0",
    PlaceId = 107778070777162,

    RawBase = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/",
    IconUrl = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/icon.png",

    Window = {
        Width = 570,
        Height = 360,
        SidebarWidth = 148,
    },

    Colors = {
        Background = Color3.fromRGB(8, 7, 13),
        Overlay = Color3.fromRGB(12, 8, 18),
        Panel = Color3.fromRGB(21, 16, 32),
        Panel2 = Color3.fromRGB(32, 21, 47),
        Accent = Color3.fromRGB(168, 85, 247),
        Combat = Color3.fromRGB(255, 61, 129),
        Movement = Color3.fromRGB(41, 217, 255),
        ESP = Color3.fromRGB(192, 132, 252),
        Player = Color3.fromRGB(82, 255, 143),
        World = Color3.fromRGB(99, 102, 255),
        Misc = Color3.fromRGB(255, 228, 92),
        Text = Color3.fromRGB(231, 229, 236),
        Muted = Color3.fromRGB(145, 138, 158),
        Border = Color3.fromRGB(52, 36, 66),
        Danger = Color3.fromRGB(255, 82, 112),
        Success = Color3.fromRGB(82, 255, 143),
    },

    KnownEndpoints = {
        "RF/EggWorld/AskFieldEggCarry",
        "RF/EggWorld/AskPlaceEgg",
        "RF/EggWorld/AskHatch",
        "RF/EggWorld/AskFieldEggDrop",
        "RF/EggWorld/AskFieldEggSnapshot",
        "RF/EggWorld/AskFinishHatch",
        "RF/Treadmill/AskWearStill",
        "RF/Treadmill/AskDoff",
        "RF/Treadmill/AskTierRaise",
        "RE/Homestead/AskBaseTierRaise",
        "RF/PenRoster/AskWear",
        "RF/PenRoster/AskDoff",
        "RF/Haul/FetchWearBestStatus",
        "RF/AwayEarnings/AskCollect",
    },

    Settings = {
        EggESP = false,
        ShowDistance = true,
        RefreshSeconds = 3,
        FpsMode = false,
        ToggleKey = Enum.KeyCode.RightControl,
    },
}
