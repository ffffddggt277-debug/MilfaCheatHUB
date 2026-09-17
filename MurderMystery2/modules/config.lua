-- MilfaCheatHUB • Murder Mystery 2
-- Shared branding, palette, paths and defaults. v0.3.1
--
-- CALM-доктрина наследуется из Steal-A-Egg v0.6.2:
--   * при загрузке печатается ТОЛЬКО голый номер версии (LogService читается
--     игровыми скриптами — слов в логе быть не должно)
--   * GUI появляется сразу и маунтится скрыто (gethui/CoreGui)
--   * ноль хуков при загрузке; всё агрессивное — только opt-in
-- Данные ресёрча v0.3.0 (рабочие скрипты KittyHub/W-Azeox/R3TH/MM2 Mods):
--   роли = Remotes.Extras.GetPlayerData (рекурсивный поиск!) + пуш
--          PlayerDataChanged (2 формы); убийство = Knife.Stab("Down"/"Up")
--          + ТП-стаб; выстрел = Gun.KnifeLocal.CreateBeam(1,pos,"AH2");
--          фейк нож = спрей SprayPaint на руку; эмоции = Remotes.PlayEmote.

return {
    Name = "MilfaCheatHUB",
    Game = "Murder Mystery 2",
    Version = "0.4.1",
    PlaceId = 142823291,

    RawBase = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/MurderMystery2/",

    -- Иконка хаба из корня репозитория (логотип в загрузчике/сайдбаре/
    -- лупе-свертывании/квадратной кнопке). Качается один раз, кэшируется.
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

    -- Цвета ролей для ESP/списков (не настраиваются в UI v1)
    RoleColors = {
        Murderer = Color3.fromRGB(255, 64, 64),
        Sheriff = Color3.fromRGB(64, 156, 255),
        Hero = Color3.fromRGB(255, 196, 47),
        Innocent = Color3.fromRGB(82, 255, 143),
        Unknown = Color3.fromRGB(160, 160, 170),
    },

    KnownEndpoints = {
        "RF/Remotes.Extras.GetPlayerData (рекурсивно)",
        "RF/Remotes.Extras.GetTimer",
        "RE/Remotes.Gameplay.PlayerDataChanged (2 формы)",
        "RE/Remotes.Gameplay.CoinCollected",
        "RE/Remotes.Gameplay.FakeGun",
        "RE/Remotes.Gameplay.Stealth (невидимка)",
        "RE/Remotes.PlayEmote",
        "RF/Remotes.Extras.ReplicateToy (SprayPaint)",
        "RE/Character.Knife.Stab (Down/Up)",
        "RE/Character.Knife.Events.KnifeThrown",
        "RF/Character.Gun.KnifeLocal.CreateBeam.RemoteFunction (AH2/AH)",
        "RF/Character.Gun.KnifeServer.ShootGun (фолбэк)",
    },

    Settings = {
        -- ESP игроков
        PlayerESP = false,
        EspShowRole = true,
        EspShowDistance = true,
        EspMaxDistance = 1000,
        EspOnlyTargets = false,   -- скрывать мирных (показывать только маньяк/шериф/хиро)
        EspHighlight = true,      -- Highlight (сквозь стены), иначе только подпись
        RefreshSeconds = 1,       -- роли меняются быстро, опрос раз в секунду

        -- Алерты
        MurderAlert = true,       -- уведомление «маньяк рядом»
        MurderAlertDistance = 70,
        GunDropAlert = true,      -- уведомление о выпавшем пистолете
        GunDropESP = true,        -- подсветка GunDrop (не зависит от PlayerESP)

        -- Фарм монет
        CoinMagnet = false,       -- магнит: тач монет в радиусе без движения
        MagnetRadius = 24,
        CoinFarm = false,         -- обход монет по карте
        FarmMode = "Smooth",      -- Teleport | Smooth | Walk
        FarmDelay = 0.8,
        StopOnFull = true,        -- стоп при полной сумке
        LobbyOnFull = false,      -- уйти в лобби при полной сумке
        FarmLobbyCoins = false,   -- собирать монеты и в лобби

        -- Автоматика
        GunGrabber = false,       -- ЛЕГАСИ: автоподбор глайдом (см. AutoPistolMode)
        AntiAFK = false,

        -- Бой (только у своей роли; повышенный риск репортов)
        KnifeAura = false,        -- ТП-стаб по ближайшим (маньяк)
        AuraRadius = 14,
        AuraDelay = 1.0,
        KillAllRadius = 60,       -- радиус KILL ALL
        SheriffAuto = false,      -- авто-выстрел в видимого маньяка (шериф/хиро)
        SheriffRange = 300,

        -- Тихий аим (одиночное действие по кнопке/клавише, без циклов)
        SheriffAimButton = true,  -- плавающая кнопка «ВЫСТРЕЛ» (шериф/герой)
        MurderAimButton = true,   -- плавающая кнопка «НОЖ» (маньяк)
        AimMaxDistance = 260,     -- макс. дистанция тихих прицелов
        ShowFloatingButtons = true,
        KeySheriffAim = "G",      -- клавиша выстрела (ПК)
        KeyMurderAim = "H",       -- клавиша броска ножа (ПК)
        KeyGrabGun = "J",         -- клавиша ТП к пистолету (ПК)
        KeyFakeDeath = "K",       -- клавиша фейк-смерти по кругу (ПК)

        -- AutoDodge (резкий стрейф от ножей и стрелков)
        -- профили: 1 Осторожно / 2 Баланс / 3 Агрессивно (радиус/сила/кулдаун
        -- пересчитываются в features.lua:ApplyDodgeProfile)
        AutoDodge = false,
        DodgeProfile = 2,
        DodgeRadius = 45,         -- радиус обнаружения снарядов (из профиля)
        DodgePower = 12,          -- сила рывка в сторону (из профиля)
        DodgeCooldown = 1.2,      -- пауза между уклонениями (из профиля)

        -- AutoPistol: ТП к выпавшему пистолету и обратно
        AutoPistolMode = "Кнопка", -- Выключено | Кнопка | Авто
        PistolSpeed = 110,         -- скорость глайда к пистолету
        PistolReturnDelay = 0.8,   -- пауза перед возвратом

        -- Бета
        PredictionRefresh = 4,     -- период пересчёта прогноза (сек)

        -- HUD и мелочи
        LoadIcon = true,           -- тянуть иконку репо (1 HttpGet + getcustomasset, кэш на диске)
        ShowTimerHud = true,       -- плавающий таймер раунда
        ShowQuickMenu = true,      -- квадратная быстрая кнопка на экране
        Tracers = false,           -- лучи к игрокам (роли)
        AlertBeep = false,         -- звук при «маньяк рядом»
        CoinESP = false,           -- подсветка монет на карте
        FOV = 70,                  -- поле зрения камеры
        WideZoom = false,          -- отдалить макс. зум (обзор карты)

        -- Троллинг
        FakeGlitch = false,        -- спид-глитч (глитч-бег, видно всем)
        GlitchForce = 40,          -- сила глитч-бега (fogyhub: 45)
        Invisible = false,         -- родная невидимость игры (Stealth remote)

        -- Персонаж
        WalkSpeed = 16,
        JumpPower = 50,
        InfiniteJump = false,
        Noclip = false,
        ClickTP = false,

        -- Визуал
        Fullbright = false,
        NoFog = false,
        RemoveRagdolls = false,   -- трупы Raggy
        RemoveBarriers = false,   -- GlitchProof-барьеры
        FpsMode = false,

        -- Стелс (CALM)
        SafeTeleport = true,      -- glide вместо мгновенных CFrame-прыжков
        GlideSpeed = 48,
        HumanizeDelays = true,
        HeadlessLoad = false,     -- false = GUI сразу; true = 3 пальца / RightControl / чат
        DebugLogs = false,
        GuiMount = "Hidden",
        ChatCommand = "/e mh",
        ToggleKey = Enum.KeyCode.RightControl,
    },
}
