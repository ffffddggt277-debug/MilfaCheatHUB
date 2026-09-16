-- MilfaCheatHUB • Steal An Egg
-- Shared branding, palette, paths and defaults. v0.4.0 (stealth)

return {
    Name = "MilfaCheatHUB",
    Game = "Steal An Egg",
    Version = "0.4.0",
    PlaceId = 107778070777162,

    RawBase = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/",
    IconUrl = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/icon.png",

    Window = {
        Width = 570,
        Height = 380,
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
        "RF/EggWorld/AskWearTool",
        "RE/PetSatchel/SellPet",
        "RE/ToolTrigger/Trigger",
        "RF/Treadmill/AskWearStill",
        "RF/Treadmill/AskDoff",
        "RF/Treadmill/AskTierRaise",
        "RE/Homestead/AskBaseTierRaise",
        "RF/PenRoster/AskWear",
        "RF/PenRoster/AskDoff",
        "RF/Haul/FetchWearBestStatus",
        "RF/AwayEarnings/AskCollect",
        "RF/MonsterParasite/AskFeed",
        "RF/MonsterParasite/AskChestTake",
        "RF/MonsterParasite/AskChestRevealComplete",
        "RF/MonsterParasite/AskChestClaim",
    },

    -- Sell remote confirmed by community scripts: RE/PetSatchel/SellPet
    -- (egg: AskWearTool(uid) then SellPet({uid}); pet: SellPet(uid))
    SellCandidates = {
        "RE/PetSatchel/SellPet",
        "RF/PetSatchel/SellPet",
        "RF/EggWorld/AskSellEgg",
        "RF/Shop/AskSell",
        "RF/Economy/AskSell",
    },

    Settings = {
        -- ESP
        EggESP = false,
        ShowDistance = true,
        ShowRarity = true,
        EspMaxDistance = 1500,
        EspFilterOnly = false,
        RefreshSeconds = 3,

        -- Rarity filter (shared by list / steal / ESP-filter)
        RarityFilter = {"Legendary", "Mythic", "Giant", "Godly", "Brainrot", "Monster", "Mecha", "Cosmic", "Secret", "Eternal", "Divine"},

        -- Egg list
        EggListAutoRefresh = true,
        MaxListDistance = 0,
        SortMode = "rarity",

        -- Auto steal
        AutoSteal = false,
        StealPriority = "rarity",
        StealRadius = 300,
        StealDelay = 2,
        StealTeleport = true,
        AutoReturn = true,
        AutoDrop = false,

        -- Automation
        AutoHatch = false,
        AutoCollect = false,
        AutoTreadmill = false,
        TreadmillInterval = 60,
        AutoDoff = false,
        AutoPlace = true,
        AutoTreadmillUpgrade = false,
        AutoBaseUpgrade = false,
        UpgradeInterval = 90,

        -- Best pets
        AutoPetsBest = false,
        PetSlots = 3,

        -- Safety
        NeutralizeTraps = false,

        -- Auto sell
        AutoSellEggs = false,
        AutoSellPets = false,
        KeepRarities = {"Legendary", "Mythic", "Godly", "Brainrot", "Monster", "Mecha", "Cosmic", "Secret", "Eternal", "Divine"},
        SellInterval = 10,
        SellPerTick = 8,
        SellPerDelay = 0.15,

        -- Server
        AutoServerHop = false,
        HopEmptyRuns = 12,

        -- Stealth (anti BAC-75110)
        SafeTeleport = true,       -- glide вместо мгновенных CFrame-прыжков
        GlideSpeed = 48,           -- скорость glide, ст/с (держи < 70)
        HumanizeDelays = true,     -- случайный джиттер всех задержек
        StealthSpeed = false,      -- скорость через CFrame, WalkSpeed не трогаем
        StealthSpeedValue = 32,    -- ст/с для стелс-скорости (держи < 60)
        MaxHatchPerTick = 4,       -- лимит AskHatch за такт (было 8)

        -- Player
        WalkSpeed = 16,
        JumpPower = 50,
        InfiniteJump = false,
        Noclip = false,
        ClickTP = false,
        AntiAFK = false,

        -- Misc
        FpsMode = false,
        ToggleKey = Enum.KeyCode.RightControl,
    },
}
