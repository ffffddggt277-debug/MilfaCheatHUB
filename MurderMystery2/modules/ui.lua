-- MilfaCheatHUB • compact neon interface v0.6.1-m (MUTE: hidden-first mount)

local UI = {}
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

math.randomseed(os.time() + math.floor(os.clock() * 100000))

-- Active stealth module (set by ShowLoader/UI.new).
local StealthRef = nil

-- Local icon cache. NO getgenv writes here: every key we publish is a trace
-- readable by keyword scans (LogService/_G bridges on some executors).
local IconAsset = nil
local IconLoading = false

local function randomGuiName()
    if StealthRef and StealthRef.RandomName then return StealthRef.RandomName(18) end
    return "UI_" .. tostring(math.random(100000, 999999))
end

local function mount(gui)
    -- Preferred: stealth module (Hidden-first per v0.6.1 MUTE doctrine:
    -- gethui/CoreGui are not enumerable by game scripts at all).
    if StealthRef and StealthRef.MountScreenGui then
        local ok, kind = pcall(StealthRef.MountScreenGui, gui)
        if ok and kind then return true end
    end

    -- Legacy fallback: hidden roots first, PlayerGui last (game scripts can
    -- enumerate PlayerGui freely).
    local targets = {}
    if gethui then
        local ok, value = pcall(gethui)
        if ok and value then targets[#targets + 1] = value end
    end
    targets[#targets + 1] = CoreGui
    local player = Players.LocalPlayer
    if player then targets[#targets + 1] = player:FindFirstChildOfClass("PlayerGui") end

    for _, target in ipairs(targets) do
        if target then
            local ok = pcall(function() gui.Parent = target end)
            if ok and gui.Parent then return true end
        end
    end
    return false
end

local function corner(parent, radius)
    local object = Instance.new("UICorner")
    object.CornerRadius = UDim.new(0, radius or 8)
    object.Parent = parent
    return object
end

local function stroke(parent, color, thickness, transparency)
    local object = Instance.new("UIStroke")
    object.Color = color
    object.Thickness = thickness or 1
    object.Transparency = transparency or 0
    object.Parent = parent
    return object
end

local function gradient(parent, first, second, rotation)
    local object = Instance.new("UIGradient")
    object.Color = ColorSequence.new(first, second)
    object.Rotation = rotation or 0
    object.Parent = parent
    return object
end

local function loadIconAsync(url, callback)
    if IconAsset then
        callback(IconAsset)
        return
    end

    if IconLoading then
        task.spawn(function()
            for _ = 1, 80 do
                if IconAsset then
                    callback(IconAsset)
                    return
                end
                if not IconLoading then return end
                task.wait(0.1)
            end
        end)
        return
    end

    IconLoading = true
    task.spawn(function()
        if writefile and getcustomasset then
            local requestFn = request or http_request or (syn and syn.request)
            if requestFn then
                local folder = "mh_cache"
                local path = folder .. "/icon.png"
                pcall(function()
                    if makefolder and not (isfolder and isfolder(folder)) then makefolder(folder) end
                end)

                -- Резервный CDN: raw иногда режется провайдером (мобильные сети).
                local mirror = string.gsub(url,
                    "^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/",
                    "https://cdn.jsdelivr.net/gh/%1/%2@")

                -- PNG-сигнатура: защита от записи HTML-ошибки/JSON в кэш
                -- (после этого getcustomasset умирает до ручной чистки файла).
                local function looksPng(body)
                    return type(body) == "string" and #body > 8 and body:sub(1, 4) == "\137PNG"
                end

                local function fetch()
                    for _, candidate in ipairs({ url, mirror }) do
                        local ok, response = pcall(requestFn, { Url = candidate, Method = "GET" })
                        local code = ok and response and
                            (response.StatusCode or response.statusCode or response.code or response.status)
                        local body = ok and response and (response.Body or response.body)
                        if body and looksPng(body) and (code == nil or tonumber(code) == 200) then
                            return body
                        end
                    end
                    return nil
                end

                -- Кэш с прошлого запуска может быть мусором: если движок его не
                -- принял — один раз перекачиваем и пробуем снова.
                local ok, result = pcall(getcustomasset, path)
                if not (ok and result) then
                    local body = fetch()
                    if body then
                        pcall(writefile, path, body)
                        ok, result = pcall(getcustomasset, path)
                    end
                end
                if ok and result then IconAsset = result end
            end
        end
        IconLoading = false
        if IconAsset then callback(IconAsset) end
    end)
end

local function createLogo(parent, config, size, position, circular)
    local holder = Instance.new("Frame")
    holder.Size = size
    holder.Position = position
    holder.BackgroundColor3 = config.Colors.Panel2
    holder.BorderSizePixel = 0
    holder.ClipsDescendants = true
    holder.Parent = parent
    corner(holder, circular and 999 or 10)
    stroke(holder, config.Colors.Accent, 1.4, 0.18)
    gradient(holder, config.Colors.Panel2, config.Colors.Background, 35)

    local fallback = Instance.new("TextLabel")
    fallback.Size = UDim2.fromScale(1, 1)
    fallback.BackgroundTransparency = 1
    fallback.Text = "M"
    fallback.TextColor3 = config.Colors.Accent
    fallback.Font = Enum.Font.Code
    fallback.TextSize = math.max(16, math.floor(size.X.Offset * 0.5))
    fallback.Parent = holder

    -- Иконка тянется ТОЛЬКО по флагу LoadIcon: writefile/getcustomasset/
    -- лишний HttpGet — дополнительные следы. По умолчанию выключена (логотип "M").
    if config.Settings and config.Settings.LoadIcon then
        loadIconAsync(config.IconUrl, function(asset)
            if not holder.Parent then return end
            fallback.Visible = false
            local image = Instance.new("ImageLabel")
            image.Size = UDim2.new(1, -6, 1, -6)
            image.Position = UDim2.fromOffset(3, 3)
            image.BackgroundTransparency = 1
            image.Image = asset
            image.ScaleType = Enum.ScaleType.Fit
            image.Parent = holder
            corner(image, circular and 999 or 8)
        end)
    end
    return holder
end

function UI.ShowLoader(config, stealth)
    StealthRef = stealth or StealthRef
    local gui = Instance.new("ScreenGui")
    gui.Name = randomGuiName()
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    if not mount(gui) then error("MilfaCheatHUB: GUI mount failed") end

    local card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(360, 142)
    card.Position = UDim2.new(0.5, -180, 0.5, -71)
    card.BackgroundColor3 = config.Colors.Background
    card.BackgroundTransparency = 0.025
    card.BorderSizePixel = 0
    card.Parent = gui
    corner(card, 15)
    stroke(card, config.Colors.Accent, 1.4, 0.18)
    gradient(card, config.Colors.Panel, config.Colors.Background, 120)

    createLogo(card, config, UDim2.fromOffset(54, 54), UDim2.fromOffset(20, 18), false)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -102, 0, 26)
    title.Position = UDim2.fromOffset(88, 20)
    title.BackgroundTransparency = 1
    title.Text = config.Name
    title.TextColor3 = config.Colors.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.Code
    title.TextSize = 19
    title.Parent = card

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -102, 0, 18)
    subtitle.Position = UDim2.fromOffset(88, 47)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = config.Game .. "  •  v" .. config.Version
    subtitle.TextColor3 = config.Colors.Muted
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 10
    subtitle.Parent = card

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -40, 0, 6)
    bar.Position = UDim2.new(0, 20, 1, -38)
    bar.BackgroundColor3 = config.Colors.Panel2
    bar.BorderSizePixel = 0
    bar.ClipsDescendants = true
    bar.Parent = card
    corner(bar, 6)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = config.Colors.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bar
    corner(fill, 6)
    gradient(fill, config.Colors.Movement, config.Colors.Accent, 0)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -40, 0, 16)
    status.Position = UDim2.new(0, 20, 1, -27)
    status.BackgroundTransparency = 1
    status.Text = "Запуск..."
    status.TextColor3 = config.Colors.Muted
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Font = Enum.Font.Code
    status.TextSize = 9
    status.Parent = card

    local controller = {}
    function controller:Set(progress, text)
        if not gui.Parent then return end
        status.Text = text or status.Text
        TweenService:Create(fill, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
            Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
        }):Play()
    end
    function controller:Destroy()
        if gui then gui:Destroy() end
    end
    return controller
end

function UI.new(config, stealth)
    StealthRef = stealth or StealthRef
    local self = {Config = config, Tabs = {}, Connections = {}, Active = nil, CloseCallback = nil}
    local colors = config.Colors
    local width = config.Window.Width
    local height = config.Window.Height
    local sidebarWidth = config.Window.SidebarWidth

    local gui = Instance.new("ScreenGui")
    gui.Name = randomGuiName()
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 99999
    if not mount(gui) then error("MilfaCheatHUB: GUI mount failed") end
    self.Gui = gui

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(width, height)
    main.Position = UDim2.new(0.5, -math.floor(width / 2), 0.5, -math.floor(height / 2))
    main.BackgroundColor3 = colors.Background
    main.BackgroundTransparency = 0.02
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    corner(main, 14)
    stroke(main, colors.Border, 1.2, 0.08)
    gradient(main, colors.Panel, colors.Background, 120)
    self.Main = main

    local scale = Instance.new("UIScale")
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    scale.Scale = math.min(1, (viewport.X - 30) / width, (viewport.Y - 30) / height)
    scale.Parent = main

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, sidebarWidth, 1, 0)
    sidebar.BackgroundColor3 = colors.Panel
    sidebar.BackgroundTransparency = 0.08
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main
    corner(sidebar, 14)

    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(0, 2, 1, -20)
    accentLine.Position = UDim2.new(1, -1, 0, 10)
    accentLine.BackgroundColor3 = colors.Accent
    accentLine.BackgroundTransparency = 0.35
    accentLine.BorderSizePixel = 0
    accentLine.Parent = sidebar
    gradient(accentLine, colors.Movement, colors.Accent, 90)

    createLogo(sidebar, config, UDim2.fromOffset(38, 38), UDim2.fromOffset(12, 12), false)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -60, 0, 22)
    title.Position = UDim2.fromOffset(58, 12)
    title.BackgroundTransparency = 1
    title.Text = "MilfaCheatHUB"
    title.TextColor3 = colors.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.Code
    title.TextSize = 11
    title.Parent = sidebar

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -60, 0, 15)
    subtitle.Position = UDim2.fromOffset(58, 33)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "MURDER MYSTERY 2"
    subtitle.TextColor3 = colors.Muted
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Font = Enum.Font.Code
    subtitle.TextSize = 8
    subtitle.Parent = sidebar

    local nav = Instance.new("Frame")
    nav.Size = UDim2.new(1, -16, 1, -78)
    nav.Position = UDim2.fromOffset(8, 64)
    nav.BackgroundTransparency = 1
    nav.Parent = sidebar
    local navList = Instance.new("UIListLayout")
    navList.Padding = UDim.new(0, 5)
    navList.Parent = nav

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, -sidebarWidth - 14, 0, 40)
    header.Position = UDim2.fromOffset(sidebarWidth + 8, 6)
    header.BackgroundTransparency = 1
    header.Parent = main

    local pageTitle = Instance.new("TextLabel")
    pageTitle.Size = UDim2.new(1, -78, 1, 0)
    pageTitle.BackgroundTransparency = 1
    pageTitle.Text = "MM2"
    pageTitle.TextColor3 = colors.Text
    pageTitle.TextXAlignment = Enum.TextXAlignment.Left
    pageTitle.Font = Enum.Font.Code
    pageTitle.TextSize = 15
    pageTitle.Parent = header

    local function topButton(text, offset, color)
        local button = Instance.new("TextButton")
        button.Size = UDim2.fromOffset(28, 26)
        button.Position = UDim2.new(1, offset, 0, 5)
        button.BackgroundColor3 = colors.Panel2
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = color
        button.Font = Enum.Font.GothamBold
        button.TextSize = 15
        button.Parent = header
        corner(button, 7)
        stroke(button, color, 1, 0.55)
        return button
    end

    local hideButton = topButton("–", -66, colors.Misc)
    local closeButton = topButton("×", -32, colors.Danger)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -sidebarWidth - 18, 1, -58)
    content.Position = UDim2.fromOffset(sidebarWidth + 10, 46)
    content.BackgroundTransparency = 1
    content.Parent = main

    local bubble = Instance.new("TextButton")
    bubble.Name = randomGuiName()
    bubble.Size = UDim2.fromOffset(54, 54)
    bubble.Position = UDim2.new(0, 18, 0.5, -27)
    bubble.BackgroundColor3 = colors.Background
    bubble.BorderSizePixel = 0
    bubble.Text = ""
    bubble.Visible = false
    bubble.Active = true
    bubble.Draggable = true
    bubble.Parent = gui
    corner(bubble, 999)
    stroke(bubble, colors.Accent, 2, 0.08)
    gradient(bubble, colors.Panel2, colors.Background, 45)
    createLogo(bubble, config, UDim2.fromOffset(44, 44), UDim2.fromOffset(5, 5), true)
    self.Bubble = bubble

    function self:Hide()
        main.Visible = false
        bubble.Visible = true
    end

    function self:Show()
        bubble.Visible = false
        main.Visible = true
    end

    function self:ToggleVisibility()
        if main.Visible then self:Hide() else self:Show() end
    end

    function self:SetCloseCallback(callback)
        self.CloseCallback = callback
    end

    hideButton.MouseButton1Click:Connect(function() self:Hide() end)
    bubble.MouseButton1Click:Connect(function() self:Show() end)
    closeButton.MouseButton1Click:Connect(function()
        if self.CloseCallback then self.CloseCallback() else self:Destroy() end
    end)

    self.Connections[#self.Connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == config.Settings.ToggleKey then self:ToggleVisibility() end
    end)

    function self:CreateTab(name, badgeText, accent)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 0, 34)
        button.BackgroundColor3 = colors.Panel2
        button.BackgroundTransparency = 0.52
        button.BorderSizePixel = 0
        button.Text = ""
        button.Parent = nav
        corner(button, 8)

        local badge = Instance.new("Frame")
        badge.Size = UDim2.fromOffset(34, 22)
        badge.Position = UDim2.fromOffset(6, 6)
        badge.BackgroundColor3 = accent or colors.Accent
        badge.BackgroundTransparency = 0.78
        badge.BorderSizePixel = 0
        badge.Parent = button
        corner(badge, 6)
        stroke(badge, accent or colors.Accent, 1, 0.35)

        local badgeLabel = Instance.new("TextLabel")
        badgeLabel.Size = UDim2.fromScale(1, 1)
        badgeLabel.BackgroundTransparency = 1
        badgeLabel.Text = string.upper(badgeText or "TAB")
        badgeLabel.TextColor3 = accent or colors.Accent
        badgeLabel.Font = Enum.Font.Code
        badgeLabel.TextSize = 8
        badgeLabel.Parent = badge

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, -48, 1, 0)
        textLabel.Position = UDim2.fromOffset(47, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = name
        textLabel.TextColor3 = colors.Muted
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.Font = Enum.Font.Code
        textLabel.TextSize = 10
        textLabel.Parent = button

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.fromScale(1, 1)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 2
        page.ScrollBarImageColor3 = accent or colors.Accent
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.CanvasSize = UDim2.new()
        page.Visible = false
        page.Parent = content
        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 6)
        list.Parent = page
        local padding = Instance.new("UIPadding")
        padding.PaddingRight = UDim.new(0, 4)
        padding.Parent = page

        local tab = {
            Name = name,
            Button = button,
            Label = textLabel,
            Page = page,
            Accent = accent or colors.Accent,
        }
        self.Tabs[#self.Tabs + 1] = tab

        local function selectTab()
            for _, item in ipairs(self.Tabs) do
                item.Page.Visible = false
                item.Label.TextColor3 = colors.Muted
                item.Button.BackgroundTransparency = 0.52
            end
            page.Visible = true
            textLabel.TextColor3 = tab.Accent
            button.BackgroundTransparency = 0.1
            pageTitle.Text = string.upper(name)
            pageTitle.TextColor3 = tab.Accent
            self.Active = tab
        end
        button.MouseButton1Click:Connect(selectTab)
        if #self.Tabs == 1 then selectTab() end
        return tab
    end

    function self:AddHeading(tab, text)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -2, 0, 24)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = tab.Accent
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Code
        label.TextSize = 13
        label.Parent = tab.Page
        return label
    end

    function self:AddText(tab, titleText, bodyText)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, -2, 0, 58)
        card.BackgroundColor3 = colors.Panel
        card.BackgroundTransparency = 0.08
        card.BorderSizePixel = 0
        card.Parent = tab.Page
        corner(card, 8)
        stroke(card, colors.Border, 1, 0.38)
        gradient(card, colors.Panel2, colors.Panel, 15)

        local marker = Instance.new("Frame")
        marker.Size = UDim2.fromOffset(2, 38)
        marker.Position = UDim2.fromOffset(7, 10)
        marker.BackgroundColor3 = tab.Accent
        marker.BorderSizePixel = 0
        marker.Parent = card
        corner(marker, 2)

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -24, 0, 20)
        titleLabel.Position = UDim2.fromOffset(16, 5)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = titleText
        titleLabel.TextColor3 = colors.Text
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Font = Enum.Font.Code
        titleLabel.TextSize = 10
        titleLabel.Parent = card

        local body = Instance.new("TextLabel")
        body.Size = UDim2.new(1, -24, 0, 28)
        body.Position = UDim2.fromOffset(16, 25)
        body.BackgroundTransparency = 1
        body.Text = bodyText or ""
        body.TextColor3 = colors.Muted
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.TextWrapped = true
        body.Font = Enum.Font.Gotham
        body.TextSize = 9
        body.Parent = card

        return {
            Set = function(_, value) body.Text = tostring(value) end,
            SetTitle = function(_, value) titleLabel.Text = tostring(value) end,
        }
    end

    function self:AddButton(tab, text, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -2, 0, 34)
        button.BackgroundColor3 = colors.Panel2
        button.BorderSizePixel = 0
        button.Text = "  ◆  " .. text
        button.TextColor3 = colors.Text
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.Font = Enum.Font.Code
        button.TextSize = 10
        button.Parent = tab.Page
        corner(button, 8)
        stroke(button, tab.Accent, 1, 0.52)
        button.MouseButton1Click:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.1), {BackgroundColor3 = tab.Accent}):Play()
            task.delay(0.14, function()
                if button.Parent then
                    TweenService:Create(button, TweenInfo.new(0.16), {BackgroundColor3 = colors.Panel2}):Play()
                end
            end)
            task.spawn(callback)
        end)
        return button
    end

    function self:AddToggle(tab, text, default, callback)
        local state = default == true
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -2, 0, 34)
        button.BackgroundColor3 = colors.Panel
        button.BorderSizePixel = 0
        button.Text = ""
        button.Parent = tab.Page
        corner(button, 8)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -58, 1, 0)
        label.Position = UDim2.fromOffset(11, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = colors.Text
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Code
        label.TextSize = 10
        label.Parent = button

        local track = Instance.new("Frame")
        track.Size = UDim2.fromOffset(34, 18)
        track.Position = UDim2.new(1, -44, 0.5, -9)
        track.BorderSizePixel = 0
        track.Parent = button
        corner(track, 999)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(14, 14)
        knob.Position = UDim2.fromOffset(2, 2)
        knob.BackgroundColor3 = colors.Text
        knob.BorderSizePixel = 0
        knob.Parent = track
        corner(knob, 999)

        local function render(animated)
            local info = TweenInfo.new(animated and 0.16 or 0)
            TweenService:Create(track, info, {BackgroundColor3 = state and tab.Accent or colors.Panel2}):Play()
            TweenService:Create(knob, info, {Position = state and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2)}):Play()
            label.TextColor3 = state and tab.Accent or colors.Text
        end
        button.MouseButton1Click:Connect(function()
            state = not state
            render(true)
            callback(state)
        end)
        render(false)
        return button
    end

    function self:AddSection(tab, text)
        local holder = Instance.new("Frame")
        holder.Size = UDim2.new(1, -2, 0, 20)
        holder.BackgroundTransparency = 1
        holder.Parent = tab.Page

        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, 0, 0, 1)
        line.Position = UDim2.fromOffset(0, 10)
        line.BackgroundColor3 = colors.Border
        line.BorderSizePixel = 0
        line.Parent = holder

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromOffset(160, 20)
        label.BackgroundTransparency = 1
        label.Text = string.upper(text or "")
        label.TextColor3 = tab.Accent
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Code
        label.TextSize = 9
        label.Parent = holder
        return label
    end

    function self:AddSlider(tab, text, min, max, default, suffix, callback)
        local value = math.clamp(tonumber(default) or min, min, max)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -2, 0, 34)
        row.BackgroundColor3 = colors.Panel
        row.BackgroundTransparency = 0.08
        row.BorderSizePixel = 0
        row.Parent = tab.Page
        corner(row, 8)
        stroke(row, colors.Border, 1, 0.38)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -136, 1, 0)
        label.Position = UDim2.fromOffset(11, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = colors.Text
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Font = Enum.Font.Code
        label.TextSize = 10
        label.Parent = row

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.fromOffset(44, 34)
        valueLabel.Position = UDim2.new(1, -48, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.TextColor3 = tab.Accent
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.Font = Enum.Font.Code
        valueLabel.TextSize = 10
        valueLabel.Parent = row

        local track = Instance.new("Frame")
        track.Size = UDim2.fromOffset(76, 6)
        track.Position = UDim2.new(1, -130, 0.5, -3)
        track.BackgroundColor3 = colors.Panel2
        track.BorderSizePixel = 0
        track.Parent = row
        corner(track, 4)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(0, 1)
        fill.BackgroundColor3 = tab.Accent
        fill.BorderSizePixel = 0
        fill.Parent = track
        corner(fill, 4)

        local dragging = false
        local function render()
            local scale = (max > min) and ((value - min) / (max - min)) or 0
            fill.Size = UDim2.fromScale(scale, 1)
            valueLabel.Text = tostring(math.floor(value * 10 + 0.5) / 10) .. (suffix or "")
        end
        local function fromX(x, fire)
            local scale = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
            value = min + (max - min) * scale
            value = math.floor(value * 10 + 0.5) / 10
            render()
            if fire and callback then callback(value) end
        end

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                fromX(input.Position.X, true)
            end
        end)
        fill.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                fromX(input.Position.X, true)
            end
        end)
        self.Connections[#self.Connections + 1] = UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                fromX(input.Position.X, true)
            end
        end)
        self.Connections[#self.Connections + 1] = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if dragging then dragging = false end
            end
        end)
        render()
        return {Set = function(_, v) value = math.clamp(tonumber(v) or min, min, max); render() end, Get = function() return value end}
    end

    function self:AddChips(tab, text, options, defaults, onChange)
        local heading = Instance.new("TextLabel")
        heading.Size = UDim2.new(1, -2, 0, 16)
        heading.BackgroundTransparency = 1
        heading.Text = text or ""
        heading.TextColor3 = colors.Muted
        heading.TextXAlignment = Enum.TextXAlignment.Left
        heading.Font = Enum.Font.Code
        heading.TextSize = 9
        heading.Parent = tab.Page

        local selected = {}
        for _, id in ipairs(defaults or {}) do selected[tostring(id)] = true end

        local perRow = 4
        local chipW, chipH, gapX, gapY = 68, 22, 4, 4
        local rows = math.max(1, math.ceil(#options / perRow))
        local grid = Instance.new("Frame")
        grid.Size = UDim2.new(1, -2, 0, rows * (chipH + gapY))
        grid.BackgroundTransparency = 1
        grid.Parent = tab.Page

        local function currentList()
            local out = {}
            for _, id in ipairs(options) do
                if selected[tostring(id)] then out[#out + 1] = id end
            end
            return out
        end

        for index, id in ipairs(options) do
            local col = (index - 1) % perRow
            local row = math.floor((index - 1) / perRow)
            local chip = Instance.new("TextButton")
            chip.Size = UDim2.fromOffset(chipW, chipH)
            chip.Position = UDim2.fromOffset(col * (chipW + gapX), row * (chipH + gapY))
            chip.BackgroundColor3 = colors.Panel2
            chip.BorderSizePixel = 0
            chip.Text = tostring(id)
            chip.TextColor3 = colors.Muted
            chip.Font = Enum.Font.Code
            chip.TextSize = 8
            chip.Parent = grid
            corner(chip, 6)

            local function render()
                local on = selected[tostring(id)] == true
                chip.BackgroundColor3 = on and tab.Accent or colors.Panel2
                chip.BackgroundTransparency = on and 0.3 or 0.5
                chip.TextColor3 = on and colors.Background or colors.Muted
            end
            chip.MouseButton1Click:Connect(function()
                if selected[tostring(id)] then selected[tostring(id)] = nil else selected[tostring(id)] = true end
                render()
                if onChange then onChange(currentList()) end
            end)
            render()
        end
        return {Get = currentList}
    end

    function self:AddDropdown(tab, text, options, default, onSelect)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, -2, 0, 34)
        container.BackgroundTransparency = 1
        container.Parent = tab.Page

        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundColor3 = colors.Panel
        row.BackgroundTransparency = 0.08
        row.BorderSizePixel = 0
        row.Text = ""
        row.Parent = container
        corner(row, 8)
        stroke(row, colors.Border, 1, 0.38)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -130, 1, 0)
        label.Position = UDim2.fromOffset(11, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = colors.Text
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Font = Enum.Font.Code
        label.TextSize = 10
        label.Parent = row

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.fromOffset(90, 34)
        valueLabel.Position = UDim2.new(1, -106, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text = tostring(default or options[1] or "")
        valueLabel.TextColor3 = tab.Accent
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
        valueLabel.Font = Enum.Font.Code
        valueLabel.TextSize = 9
        valueLabel.Parent = row

        local arrow = Instance.new("TextLabel")
        arrow.Size = UDim2.fromOffset(16, 34)
        arrow.Position = UDim2.new(1, -20, 0, 0)
        arrow.BackgroundTransparency = 1
        arrow.Text = "▾"
        arrow.TextColor3 = colors.Muted
        arrow.Font = Enum.Font.Code
        arrow.TextSize = 10
        arrow.Parent = row

        local listFrame = Instance.new("Frame")
        listFrame.Position = UDim2.fromOffset(0, 36)
        listFrame.Size = UDim2.new(1, 0, 0, #options * 26 + 4)
        listFrame.BackgroundColor3 = colors.Panel2
        listFrame.BorderSizePixel = 0
        listFrame.Visible = false
        listFrame.ZIndex = 5
        listFrame.Parent = container
        corner(listFrame, 8)
        stroke(listFrame, colors.Accent, 1, 0.4)

        for index, option in ipairs(options) do
            local optionButton = Instance.new("TextButton")
            optionButton.Size = UDim2.new(1, -8, 0, 24)
            optionButton.Position = UDim2.fromOffset(4, (index - 1) * 26 + 2)
            optionButton.BackgroundColor3 = colors.Panel2
            optionButton.BorderSizePixel = 0
            optionButton.Text = tostring(option)
            optionButton.TextColor3 = colors.Text
            optionButton.Font = Enum.Font.Code
            optionButton.TextSize = 9
            optionButton.ZIndex = 6
            optionButton.Parent = listFrame
            corner(optionButton, 6)
            optionButton.MouseButton1Click:Connect(function()
                valueLabel.Text = tostring(option)
                listFrame.Visible = false
                arrow.Text = "▾"
                if onSelect then onSelect(option) end
            end)
        end

        row.MouseButton1Click:Connect(function()
            listFrame.Visible = not listFrame.Visible
            arrow.Text = listFrame.Visible and "▴" or "▾"
        end)
        return {Set = function(_, option) valueLabel.Text = tostring(option) end}
    end

    function self:CreateEggList(tab, rarity)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, -2, 0, 150)
        container.BackgroundTransparency = 1
        container.Parent = tab.Page
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 4)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = container
        local handles = {}

        local controller = {}

        function controller:Clear()
            for key, handle in pairs(handles) do
                pcall(function() handle.Frame:Destroy() end)
                handles[key] = nil
            end
        end

        function controller:Rebuild(records, callbacks)
            local seen = {}
            for index, record in ipairs(records) do
                local key = tostring(record.Uid)
                seen[key] = true
                local handle = handles[key]
                if not handle then
                    local card = Instance.new("Frame")
                    card.Size = UDim2.new(1, -2, 0, 36)
                    card.BackgroundColor3 = colors.Panel
                    card.BackgroundTransparency = 0.08
                    card.BorderSizePixel = 0
                    card.Parent = container
                    corner(card, 8)
                    stroke(card, colors.Border, 1, 0.38)

                    local marker = Instance.new("Frame")
                    marker.Size = UDim2.fromOffset(2, 24)
                    marker.Position = UDim2.fromOffset(6, 6)
                    marker.BackgroundColor3 = rarity.Color(record.Rarity)
                    marker.BorderSizePixel = 0
                    marker.Parent = card
                    corner(marker, 2)

                    local nameLabel = Instance.new("TextLabel")
                    nameLabel.Size = UDim2.new(1, -150, 0, 16)
                    nameLabel.Position = UDim2.fromOffset(14, 3)
                    nameLabel.BackgroundTransparency = 1
                    nameLabel.Text = tostring(record.Name or "Egg")
                    nameLabel.TextColor3 = colors.Text
                    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                    nameLabel.Font = Enum.Font.Code
                    nameLabel.TextSize = 10
                    nameLabel.Parent = card

                    local subLabel = Instance.new("TextLabel")
                    subLabel.Size = UDim2.new(1, -150, 0, 13)
                    subLabel.Position = UDim2.fromOffset(14, 19)
                    subLabel.BackgroundTransparency = 1
                    subLabel.Text = ""
                    subLabel.TextColor3 = rarity.Color(record.Rarity)
                    subLabel.TextXAlignment = Enum.TextXAlignment.Left
                    subLabel.TextTruncate = Enum.TextTruncate.AtEnd
                    subLabel.Font = Enum.Font.Code
                    subLabel.TextSize = 8
                    subLabel.Parent = card

                    local stealButton = Instance.new("TextButton")
                    stealButton.Size = UDim2.fromOffset(46, 24)
                    stealButton.Position = UDim2.new(1, -104, 0.5, -12)
                    stealButton.BackgroundColor3 = colors.Panel2
                    stealButton.BorderSizePixel = 0
                    stealButton.Text = "СТЛ"
                    stealButton.TextColor3 = colors.Combat
                    stealButton.Font = Enum.Font.Code
                    stealButton.TextSize = 9
                    stealButton.Parent = card
                    corner(stealButton, 6)
                    stroke(stealButton, colors.Combat, 1, 0.45)

                    local tpButton = Instance.new("TextButton")
                    tpButton.Size = UDim2.fromOffset(40, 24)
                    tpButton.Position = UDim2.new(1, -58, 0.5, -12)
                    tpButton.BackgroundColor3 = colors.Panel2
                    tpButton.BorderSizePixel = 0
                    tpButton.Text = "TP"
                    tpButton.TextColor3 = colors.Movement
                    tpButton.Font = Enum.Font.Code
                    tpButton.TextSize = 9
                    tpButton.Parent = card
                    corner(tpButton, 6)
                    stroke(tpButton, colors.Movement, 1, 0.45)

                    handle = {Frame = card, Name = nameLabel, Sub = subLabel, Record = record}
                    handles[key] = handle

                    tpButton.MouseButton1Click:Connect(function()
                        if callbacks and callbacks.OnTeleport then task.spawn(callbacks.OnTeleport, handle.Record) end
                    end)
                    stealButton.MouseButton1Click:Connect(function()
                        if callbacks and callbacks.OnSteal then task.spawn(callbacks.OnSteal, handle.Record) end
                    end)
                end

                handle.Record = record
                handle.Frame.LayoutOrder = index
                handle.Name.Text = tostring(record.Name or "Egg")
                local distanceText = (record.Distance and record.Distance ~= math.huge) and (tostring(record.Distance) .. " st") or "?"
                handle.Sub.Text = string.format("[%s] • %s", tostring(record.Rarity), distanceText)
                handle.Sub.TextColor3 = rarity.Color(record.Rarity)
            end

            for key, handle in pairs(handles) do
                if not seen[key] then
                    pcall(function() handle.Frame:Destroy() end)
                    handles[key] = nil
                end
            end
        end

        return controller
    end

    -----------------------------------------------------------------
    -- Floating action buttons (телефон: кнопки под палец; ПК: клавиши).
    -- Живут на самом ScreenGui — видны и при скрытом окне.
    -----------------------------------------------------------------
    local fabHost = Instance.new("Frame")
    fabHost.Name = randomGuiName()
    fabHost.Size = UDim2.new(0, 64, 0, 320)
    fabHost.Position = UDim2.new(1, -62, 0.5, -140)
    fabHost.BackgroundTransparency = 1
    fabHost.Parent = gui
    local fabList = Instance.new("UIListLayout")
    fabList.Padding = UDim.new(0, 8)
    fabList.HorizontalAlignment = Enum.HorizontalAlignment.Right
    fabList.VerticalAlignment = Enum.VerticalAlignment.Center
    fabList.SortOrder = Enum.SortOrder.LayoutOrder
    fabList.Parent = fabHost

    local fabCount = 0
    function self:AddFloatingButton(text, color, callback)
        fabCount = fabCount + 1
        local button = Instance.new("TextButton")
        button.Name = randomGuiName()
        button.LayoutOrder = fabCount
        button.Size = UDim2.fromOffset(56, 40)
        button.BackgroundColor3 = colors.Background
        button.BackgroundTransparency = 0.12
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = color
        button.Font = Enum.Font.Code
        button.TextSize = 10
        button.Active = true
        button.Visible = false
        button.Parent = fabHost
        corner(button, 10)
        stroke(button, color, 1.4, 0.15)
        gradient(button, colors.Panel2, colors.Background, 90)
        button.MouseButton1Click:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.08), { BackgroundTransparency = 0.55 }):Play()
            task.delay(0.16, function()
                if button.Parent then
                    TweenService:Create(button, TweenInfo.new(0.15), { BackgroundTransparency = 0.12 }):Play()
                end
            end)
            task.spawn(callback)
        end)
        return {
            Frame = button,
            SetVisible = function(_, value) button.Visible = value == true end,
            SetText = function(_, value) button.Text = tostring(value) end,
            Destroy = function() pcall(function() button:Destroy() end) end,
        }
    end

    function self:SetFloatingHostVisible(value)
        fabHost.Visible = value ~= false
    end

    -----------------------------------------------------------------
    -- Квадратная плавающая кнопка быстрых действий (телефон+ПК).
    -- Одна кнопка на экране; тап открывает панель действий.
    -- Перетаскивается пальцем; панель следует за кнопкой.
    -----------------------------------------------------------------
    function self:AddQuickMenu(actions)
        local quick = Instance.new("Frame")
        quick.Name = randomGuiName()
        quick.Size = UDim2.fromOffset(54, 54)
        quick.Position = UDim2.new(1, -70, 0.5, -27)
        quick.BackgroundColor3 = colors.Background
        quick.BackgroundTransparency = 0.08
        quick.BorderSizePixel = 0
        quick.Active = true
        quick.Parent = gui
        corner(quick, 12)
        stroke(quick, colors.Accent, 1.6, 0.1)
        gradient(quick, colors.Panel2, colors.Background, 90)

        local icon = Instance.new("TextLabel")
        icon.Size = UDim2.new(1, 0, 1, 0)
        icon.BackgroundTransparency = 1
        icon.Text = "М"
        icon.TextColor3 = colors.Accent
        icon.Font = Enum.Font.GothamBold
        icon.TextSize = 22
        icon.Parent = quick

        -- Тот же icon.png из корня репо (тянется один раз на все логотипы).
        if config.Settings and config.Settings.LoadIcon and config.IconUrl then
            loadIconAsync(config.IconUrl, function(asset)
                if not quick.Parent then return end
                icon.Visible = false
                local image = Instance.new("ImageLabel")
                image.Size = UDim2.new(1, -10, 1, -10)
                image.Position = UDim2.fromOffset(5, 5)
                image.BackgroundTransparency = 1
                image.Image = asset
                image.ScaleType = Enum.ScaleType.Fit
                image.Parent = quick
                corner(image, 9)
            end)
        end

        -- панель действий
        local panel = Instance.new("Frame")
        panel.Name = randomGuiName()
        panel.Size = UDim2.fromOffset(128, 8 + math.max(1, #actions) * 42)
        panel.Position = UDim2.new(1, -70, 0.5, -27 - (8 + math.max(1, #actions) * 42) - 8)
        panel.BackgroundColor3 = colors.Background
        panel.BackgroundTransparency = 0.06
        panel.BorderSizePixel = 0
        panel.Visible = false
        panel.Active = true
        panel.Parent = gui
        corner(panel, 12)
        stroke(panel, colors.Border, 1.2, 0.12)

        local panelList = Instance.new("UIListLayout")
        panelList.Padding = UDim.new(0, 6)
        panelList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        panelList.VerticalAlignment = Enum.VerticalAlignment.Center
        panelList.SortOrder = Enum.SortOrder.LayoutOrder
        panelList.Parent = panel

        local open = false
        local function place()
            panel.Position = UDim2.new(
                quick.Position.X.Scale, quick.Position.X.Offset,
                quick.Position.Y.Scale, quick.Position.Y.Offset - panel.Size.Y.Offset - 8)
        end

        for index, action in ipairs(actions or {}) do
            local item = Instance.new("TextButton")
            item.Name = randomGuiName()
            item.LayoutOrder = index
            item.Size = UDim2.fromOffset(114, 36)
            item.BackgroundColor3 = colors.Panel
            item.BackgroundTransparency = 0.1
            item.BorderSizePixel = 0
            item.Text = tostring(action.Text or "?")
            item.TextColor3 = action.Color or colors.Text
            item.Font = Enum.Font.Code
            item.TextSize = 12
            item.Parent = panel
            corner(item, 9)
            stroke(item, action.Color or colors.Border, 1, 0.2)
            item.MouseButton1Click:Connect(function()
                task.spawn(function()
                    if action.Callback then action.Callback() end
                end)
            end)
        end

        -- перетаскивание квадратной кнопки (мышь + палец)
        local dragging = false
        local dragMoved = false
        local dragStart, startPos
        quick.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragMoved = false
                dragStart = input.Position
                startPos = quick.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if not dragMoved then
                            open = not open
                            panel.Visible = open
                            if open then place() end
                        end
                    end
                end)
            end
        end)
        quick.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                if math.abs(delta.X) + math.abs(delta.Y) > 6 then dragMoved = true end
                if dragMoved then
                    quick.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                    if open then place() end
                end
            end
        end)

        return {
            Frame = quick,
            Panel = panel,
            SetVisible = function(_, value)
                quick.Visible = value == true
                if not value then panel.Visible = false; open = false end
            end,
            Destroy = function()
                pcall(function() panel:Destroy() end)
                pcall(function() quick:Destroy() end)
            end,
        }
    end

    -----------------------------------------------------------------
    -- Плавающий HUD: таймер раунда + строка ролей (перетаскивается).
    -----------------------------------------------------------------
    function self:AddFloatingHud()
        local hud = Instance.new("Frame")
        hud.Name = randomGuiName()
        hud.Size = UDim2.fromOffset(158, 54)
        hud.Position = UDim2.new(0.5, -79, 0, 10)
        hud.BackgroundColor3 = colors.Background
        hud.BackgroundTransparency = 0.25
        hud.BorderSizePixel = 0
        hud.Active = true
        hud.Draggable = true
        hud.Parent = gui
        corner(hud, 10)
        stroke(hud, colors.Border, 1, 0.3)

        local line1 = Instance.new("TextLabel")
        line1.Size = UDim2.new(1, -10, 0, 26)
        line1.Position = UDim2.fromOffset(5, 2)
        line1.BackgroundTransparency = 1
        line1.Text = "—:—"
        line1.TextColor3 = colors.Movement
        line1.Font = Enum.Font.Code
        line1.TextSize = 17
        line1.Parent = hud

        local line2 = Instance.new("TextLabel")
        line2.Size = UDim2.new(1, -10, 0, 18)
        line2.Position = UDim2.fromOffset(5, 30)
        line2.BackgroundTransparency = 1
        line2.Text = "роль: ?"
        line2.TextColor3 = colors.Muted
        line2.Font = Enum.Font.Code
        line2.TextSize = 9
        line2.Parent = hud

        return {
            Frame = hud,
            SetTime = function(_, value) line1.Text = tostring(value) end,
            SetInfo = function(_, value) line2.Text = tostring(value) end,
            SetVisible = function(_, value) hud.Visible = value == true end,
        }
    end

    return self
end

function UI:Destroy()
    for _, connection in ipairs(self.Connections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    if self.Gui then self.Gui:Destroy() end
end

return UI
