-- MilfaCheatHUB • reusable neon interface

local UI = {}
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")

local function guiParent()
    if gethui then
        local ok, value = pcall(gethui)
        if ok and value then return value end
    end
    return CoreGui or Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function addCorner(parent, radius)
    local object = Instance.new("UICorner")
    object.CornerRadius = UDim.new(0, radius or 8)
    object.Parent = parent
    return object
end

local function addStroke(parent, color, thickness, transparency)
    local object = Instance.new("UIStroke")
    object.Color = color
    object.Thickness = thickness or 1
    object.Transparency = transparency or 0
    object.Parent = parent
    return object
end

local function resolveIcon(url)
    if not (writefile and getcustomasset) then return nil end
    local requestFn = request or http_request or (syn and syn.request)
    if not requestFn then return nil end

    local folder = "MilfaCheatHUB"
    local path = folder .. "/icon.png"
    pcall(function()
        if makefolder and not (isfolder and isfolder(folder)) then makefolder(folder) end
    end)

    if not (isfile and isfile(path)) then
        local ok, response = pcall(requestFn, {Url = url, Method = "GET"})
        local body = ok and response and (response.Body or response.body)
        if body then pcall(writefile, path, body) end
    end

    local ok, asset = pcall(getcustomasset, path)
    return ok and asset or nil
end

local function createLogo(parent, config, size, position)
    local holder = Instance.new("Frame")
    holder.Size = size
    holder.Position = position
    holder.BackgroundColor3 = config.Colors.Panel2
    holder.BorderSizePixel = 0
    holder.Parent = parent
    addCorner(holder, 11)
    addStroke(holder, config.Colors.Accent, 1.4, 0.2)

    local asset = resolveIcon(config.IconUrl)
    if asset then
        local image = Instance.new("ImageLabel")
        image.Size = UDim2.new(1, -6, 1, -6)
        image.Position = UDim2.fromOffset(3, 3)
        image.BackgroundTransparency = 1
        image.Image = asset
        image.ScaleType = Enum.ScaleType.Fit
        image.Parent = holder
        addCorner(image, 9)
    else
        local fallback = Instance.new("TextLabel")
        fallback.Size = UDim2.fromScale(1, 1)
        fallback.BackgroundTransparency = 1
        fallback.Text = "M"
        fallback.TextColor3 = config.Colors.Accent
        fallback.Font = Enum.Font.Code
        fallback.TextSize = math.max(18, math.floor(size.X.Offset * 0.55))
        fallback.Parent = holder
    end
    return holder
end

function UI.ShowLoader(config)
    local gui = Instance.new("ScreenGui")
    gui.Name = "MilfaCheatHUB_Loading"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    gui.Parent = guiParent()

    local card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(410, 174)
    card.Position = UDim2.new(0.5, -205, 0.5, -87)
    card.BackgroundColor3 = config.Colors.Background
    card.BackgroundTransparency = 0.04
    card.BorderSizePixel = 0
    card.Parent = gui
    addCorner(card, 16)
    addStroke(card, config.Colors.Accent, 1.6, 0.2)

    local glow = Instance.new("ImageLabel")
    glow.Size = UDim2.new(1, 70, 1, 70)
    glow.Position = UDim2.fromOffset(-35, -35)
    glow.BackgroundTransparency = 1
    glow.Image = "rbxassetid://5028857084"
    glow.ImageColor3 = config.Colors.Accent
    glow.ImageTransparency = 0.72
    glow.ScaleType = Enum.ScaleType.Slice
    glow.SliceCenter = Rect.new(24, 24, 276, 276)
    glow.ZIndex = 0
    glow.Parent = card

    createLogo(card, config, UDim2.fromOffset(64, 64), UDim2.fromOffset(24, 22))

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -120, 0, 30)
    title.Position = UDim2.fromOffset(104, 25)
    title.BackgroundTransparency = 1
    title.Text = config.Name
    title.TextColor3 = config.Colors.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.Code
    title.TextSize = 22
    title.Parent = card

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -120, 0, 20)
    subtitle.Position = UDim2.fromOffset(104, 56)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = config.Game .. "  •  v" .. config.Version
    subtitle.TextColor3 = config.Colors.Muted
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 12
    subtitle.Parent = card

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -48, 0, 8)
    bar.Position = UDim2.new(0, 24, 1, -49)
    bar.BackgroundColor3 = config.Colors.Panel2
    bar.BorderSizePixel = 0
    bar.ClipsDescendants = true
    bar.Parent = card
    addCorner(bar, 8)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = config.Colors.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bar
    addCorner(fill, 8)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -48, 0, 18)
    status.Position = UDim2.new(0, 24, 1, -34)
    status.BackgroundTransparency = 1
    status.Text = "Запуск..."
    status.TextColor3 = config.Colors.Muted
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.Parent = card

    local controller = {}
    function controller:Set(progress, text)
        status.Text = text or status.Text
        TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
            Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
        }):Play()
    end
    function controller:Destroy() if gui then gui:Destroy() end end
    return controller
end

function UI.new(config)
    local self = {Config = config, Tabs = {}, Active = nil, Connections = {}}
    local colors = config.Colors

    local gui = Instance.new("ScreenGui")
    gui.Name = "MilfaCheatHUB_StealAnEgg"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 99999
    gui.Parent = guiParent()
    self.Gui = gui

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(660, 438)
    main.Position = UDim2.new(0.5, -330, 0.5, -219)
    main.BackgroundColor3 = colors.Background
    main.BackgroundTransparency = 0.035
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    addCorner(main, 15)
    addStroke(main, colors.Border, 1.3, 0.05)
    self.Main = main

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 182, 1, 0)
    sidebar.BackgroundColor3 = colors.Panel
    sidebar.BackgroundTransparency = 0.08
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main
    addCorner(sidebar, 15)

    createLogo(sidebar, config, UDim2.fromOffset(46, 46), UDim2.fromOffset(16, 14))

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -76, 0, 25)
    title.Position = UDim2.fromOffset(72, 14)
    title.BackgroundTransparency = 1
    title.Text = config.Name
    title.TextColor3 = colors.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.Parent = sidebar

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -76, 0, 18)
    subtitle.Position = UDim2.fromOffset(72, 39)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = config.Game
    subtitle.TextColor3 = colors.Muted
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 10
    subtitle.Parent = sidebar

    local nav = Instance.new("Frame")
    nav.Size = UDim2.new(1, -20, 1, -98)
    nav.Position = UDim2.fromOffset(10, 76)
    nav.BackgroundTransparency = 1
    nav.Parent = sidebar
    local navList = Instance.new("UIListLayout")
    navList.Padding = UDim.new(0, 6)
    navList.Parent = nav

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -202, 1, -62)
    content.Position = UDim2.fromOffset(196, 16)
    content.BackgroundTransparency = 1
    content.Parent = main

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, -210, 0, 20)
    footer.Position = UDim2.new(0, 196, 1, -27)
    footer.BackgroundTransparency = 1
    footer.Text = "● v" .. config.Version .. "  •  RightControl — скрыть/показать"
    footer.TextColor3 = colors.Muted
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.Font = Enum.Font.Code
    footer.TextSize = 10
    footer.Parent = main

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(28, 28)
    close.Position = UDim2.new(1, -38, 0, 10)
    close.BackgroundColor3 = colors.Panel2
    close.BorderSizePixel = 0
    close.Text = "×"
    close.TextColor3 = colors.Text
    close.Font = Enum.Font.GothamBold
    close.TextSize = 18
    close.Parent = main
    addCorner(close, 8)
    close.MouseButton1Click:Connect(function()
        local env = (getgenv and getgenv()) or _G
        if env.MilfaCheatHUBCleanup then env.MilfaCheatHUBCleanup() end
    end)

    self.Connections[#self.Connections + 1] = game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == config.Settings.ToggleKey then
            main.Visible = not main.Visible
        end
    end)

    function self:CreateTab(name, glyph, accent)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 0, 38)
        button.BackgroundColor3 = colors.Panel2
        button.BackgroundTransparency = 0.5
        button.BorderSizePixel = 0
        button.Text = (glyph or "◆") .. "  " .. name
        button.TextColor3 = colors.Muted
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.Font = Enum.Font.Code
        button.TextSize = 12
        button.Parent = nav
        addCorner(button, 8)
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 12)
        pad.Parent = button

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.fromScale(1, 1)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = accent or colors.Accent
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.CanvasSize = UDim2.new()
        page.Visible = false
        page.Parent = content
        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 8)
        list.Parent = page
        local padding = Instance.new("UIPadding")
        padding.PaddingRight = UDim.new(0, 5)
        padding.Parent = page

        local tab = {Button = button, Page = page, Accent = accent or colors.Accent}
        self.Tabs[#self.Tabs + 1] = tab

        local function selectTab()
            for _, item in ipairs(self.Tabs) do
                item.Page.Visible = false
                item.Button.TextColor3 = colors.Muted
                item.Button.BackgroundTransparency = 0.5
            end
            page.Visible = true
            button.TextColor3 = tab.Accent
            button.BackgroundTransparency = 0.08
            self.Active = tab
        end
        button.MouseButton1Click:Connect(selectTab)
        if #self.Tabs == 1 then selectTab() end
        return tab
    end

    function self:AddHeading(tab, text)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -2, 0, 30)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = tab.Accent
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Code
        label.TextSize = 17
        label.Parent = tab.Page
        return label
    end

    function self:AddText(tab, titleText, bodyText)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, -2, 0, 66)
        card.BackgroundColor3 = colors.Panel
        card.BackgroundTransparency = 0.1
        card.BorderSizePixel = 0
        card.Parent = tab.Page
        addCorner(card, 9)
        addStroke(card, colors.Border, 1, 0.35)

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -20, 0, 24)
        titleLabel.Position = UDim2.fromOffset(10, 7)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = titleText
        titleLabel.TextColor3 = colors.Text
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Font = Enum.Font.Code
        titleLabel.TextSize = 12
        titleLabel.Parent = card

        local body = Instance.new("TextLabel")
        body.Size = UDim2.new(1, -20, 0, 30)
        body.Position = UDim2.fromOffset(10, 30)
        body.BackgroundTransparency = 1
        body.Text = bodyText or ""
        body.TextColor3 = colors.Muted
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.TextWrapped = true
        body.Font = Enum.Font.Gotham
        body.TextSize = 10
        body.Parent = card

        return {
            Set = function(_, value) body.Text = tostring(value) end,
            SetTitle = function(_, value) titleLabel.Text = tostring(value) end,
        }
    end

    function self:AddButton(tab, text, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -2, 0, 38)
        button.BackgroundColor3 = colors.Panel2
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = colors.Text
        button.Font = Enum.Font.Code
        button.TextSize = 12
        button.Parent = tab.Page
        addCorner(button, 8)
        addStroke(button, tab.Accent, 1, 0.5)
        button.MouseButton1Click:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.12), {BackgroundColor3 = tab.Accent}):Play()
            task.delay(0.16, function()
                if button.Parent then TweenService:Create(button, TweenInfo.new(0.18), {BackgroundColor3 = colors.Panel2}):Play() end
            end)
            task.spawn(callback)
        end)
        return button
    end

    function self:AddToggle(tab, text, default, callback)
        local state = default == true
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -2, 0, 38)
        button.BackgroundColor3 = colors.Panel
        button.BorderSizePixel = 0
        button.TextColor3 = colors.Text
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.Font = Enum.Font.Code
        button.TextSize = 12
        button.Parent = tab.Page
        addCorner(button, 8)
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 12)
        pad.Parent = button

        local function render()
            button.Text = text .. (state and "    [ ON ]" or "    [ OFF ]")
            button.TextColor3 = state and tab.Accent or colors.Text
        end
        button.MouseButton1Click:Connect(function()
            state = not state
            render()
            callback(state)
        end)
        render()
        return button
    end

    return self
end

function UI:Destroy()
    for _, connection in ipairs(self.Connections or {}) do pcall(function() connection:Disconnect() end) end
    if self.Gui then self.Gui:Destroy() end
end

return UI
