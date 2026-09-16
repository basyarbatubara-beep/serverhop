--[[
    ========================================================================
    HORIZON SERVER HOPPER • PRO EDITION
    ========================================================================
    Architecture:
    - High-performance Roblox Games API scanner with 429 adaptive backoff.
    - Ascending population indexing with latency-first tie breaking.
    - Resilient auto-hop watchdog & fallback chain (handles closed/ghost instances).
    - Modern glassmorphism UI with micro-interactions & fluid animations.
    ========================================================================
--]]

-- Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlaceId = game.PlaceId
local CurrentJobId = game.JobId

-- Wait for PlayerGui
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Prevent duplicate instances
if getgenv and getgenv().HorizonHopInstance then
    pcall(function()
        getgenv().HorizonHopInstance:Destroy()
    end)
    getgenv().HorizonHopInstance = nil
end

-- ========================================================================
-- UTILITIES & HELPERS
-- ========================================================================

local function tween(object, properties, duration, style, direction)
    style = style or Enum.EasingStyle.Quad
    direction = direction or Enum.EasingDirection.Out
    duration = duration or 0.16
    local t = TweenService:Create(object, TweenInfo.new(duration, style, direction), properties)
    t:Play()
    return t
end

local function setupHover(btn, normalColor, hoverColor)
    btn.MouseEnter:Connect(function()
        tween(btn, { BackgroundColor3 = hoverColor })
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, { BackgroundColor3 = normalColor })
    end)
end

local function notify(title, message, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Server Hop",
            Text = message or "",
            Duration = duration or 3
        })
    end)
end

-- Resolve GUI Container
local function getGuiContainer()
    if typeof(gethui) == "function" then
        local success, hui = pcall(gethui)
        if success and hui then return hui end
    end
    local coreGuiSuccess, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if coreGuiSuccess and coreGui then
        local testSuccess = pcall(function()
            local test = Instance.new("Folder")
            test.Parent = coreGui
            test:Destroy()
        end)
        if testSuccess then return coreGui end
    end
    return PlayerGui
end

-- Safe URL Encode
local function safeUrlEncode(str)
    if not str or str == "" then return "" end
    if HttpService and HttpService.UrlEncode then
        local s, res = pcall(function()
            return HttpService:UrlEncode(str)
        end)
        if s and res then return res end
    end
    str = string.gsub(str, "\r\n", "\n")
    str = string.gsub(str, "([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-- Robust HTTP Request
local function httpRequest(url)
    local requestFunc = nil
    if typeof(syn) == "table" and typeof(syn.request) == "function" then
        requestFunc = syn.request
    elseif typeof(request) == "function" then
        requestFunc = request
    elseif typeof(http_request) == "function" then
        requestFunc = http_request
    elseif typeof(fluxus) == "table" and typeof(fluxus.request) == "function" then
        requestFunc = fluxus.request
    end

    if requestFunc then
        local success, response = pcall(function()
            return requestFunc({
                Url = url,
                Method = "GET",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["User-Agent"] = "Roblox/WinInet"
                }
            })
        end)
        if success and response and response.Body then
            return response.Body
        end
    end

    if game and game.HttpGet then
        local success, result = pcall(function()
            return game:HttpGet(url)
        end)
        if success and result then
            return result
        end
    end

    return nil, "HTTP request failed"
end

-- Clipboard
local function copyToClipboard(text)
    if setclipboard then
        setclipboard(text)
        return true
    elseif toclipboard then
        toclipboard(text)
        return true
    elseif syn and syn.write_clipboard then
        syn.write_clipboard(text)
        return true
    elseif Clipboard and Clipboard.set then
        Clipboard.set(text)
        return true
    end
    return false
end

-- Drag with Spring feel
local function makeDraggable(dragHandle, targetFrame)
    local dragging = false
    local dragStart = nil
    local startPos = nil

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = targetFrame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                local delta = input.Position - dragStart
                targetFrame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end
    end)
end

-- Teleport confirmation queue
local function setupQueueOnTeleport()
    local queueFunc = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    if queueFunc then
        pcall(function()
            queueFunc([[
                task.spawn(function()
                    repeat task.wait(0.5) until game:IsLoaded()
                    local StarterGui = game:GetService("StarterGui")
                    task.wait(1.2)
                    pcall(function()
                        StarterGui:SetCore("SendNotification", {
                            Title = "Server Hop",
                            Text = "Successfully joined destination server!",
                            Duration = 5
                        })
                    end)
                end)
            ]])
        end)
    end
end

-- Game Info
local gameTitle = "Place " .. tostring(PlaceId)
task.spawn(function()
    local success, productInfo = pcall(function()
        return MarketplaceService:GetProductInfo(PlaceId)
    end)
    if success and productInfo and productInfo.Name then
        gameTitle = productInfo.Name
    end
end)

-- ========================================================================
-- PERSISTENT BLACKLIST (ACROSS TELEPORTS)
-- ========================================================================
if getgenv then
    getgenv().ServerHopBlacklist = getgenv().ServerHopBlacklist or {}
    getgenv().ServerHopBlacklist[CurrentJobId] = true
end

local localBlacklist = {}

local function isServerBlacklisted(id)
    if not id or id == "" or id == CurrentJobId then return true end
    if localBlacklist[id] then return true end
    if getgenv and getgenv().ServerHopBlacklist and getgenv().ServerHopBlacklist[id] then
        return true
    end
    return false
end

local function addServerToBlacklist(id)
    if not id or id == "" then return end
    localBlacklist[id] = true
    if getgenv and getgenv().ServerHopBlacklist then
        getgenv().ServerHopBlacklist[id] = true
    end
end

-- State Management
local loadedServers = {}
local blacklistServers = localBlacklist
local nextPageCursor = "" 
local isFetching = false
local isHopping = false
local currentHopIndex = 1
local hopCandidates = {}
local activeTab = "solo"
local excludeCurrentActive = true

-- Forward references
local setStatus = nil
local renderServerList = nil
local stopHopping = nil
local executeHopAttempt = nil
-- ========================================================================
-- USER INTERFACE (CLEAN GLASSMORPHISM THEME)
-- ========================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HorizonServerHopGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = getGuiContainer()

if getgenv then
    getgenv().HorizonHopInstance = ScreenGui
end

-- Main Viewport Window
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 510)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -255)
MainFrame.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(36, 40, 54)
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Header Bar
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 52)
Header.BackgroundColor3 = Color3.fromRGB(17, 19, 26)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local HeaderDivider = Instance.new("Frame")
HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
HeaderDivider.Position = UDim2.new(0, 0, 1, -1)
HeaderDivider.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
HeaderDivider.BorderSizePixel = 0
HeaderDivider.Parent = Header

local BrandDot = Instance.new("Frame")
BrandDot.Size = UDim2.new(0, 8, 0, 8)
BrandDot.Position = UDim2.new(0, 16, 0, 17)
BrandDot.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
BrandDot.BorderSizePixel = 0
BrandDot.Parent = Header

local BrandDotCorner = Instance.new("UICorner")
BrandDotCorner.CornerRadius = UDim.new(1, 0)
BrandDotCorner.Parent = BrandDot

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(0, 95, 0, 20)
TitleLabel.Position = UDim2.new(0, 32, 0, 10)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "ServerHop"
TitleLabel.TextColor3 = Color3.fromRGB(242, 244, 250)
TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header

local VersionBadge = Instance.new("TextLabel")
VersionBadge.Size = UDim2.new(0, 52, 0, 16)
VersionBadge.Position = UDim2.new(0, 130, 0, 12)
VersionBadge.BackgroundColor3 = Color3.fromRGB(28, 32, 46)
VersionBadge.BorderSizePixel = 0
VersionBadge.Font = Enum.Font.GothamBold
VersionBadge.Text = "ANTI-SWARM"
VersionBadge.TextColor3 = Color3.fromRGB(129, 140, 248)
VersionBadge.TextSize = 9
VersionBadge.Parent = Header

local BadgeCorner = Instance.new("UICorner")
BadgeCorner.CornerRadius = UDim.new(0, 4)
BadgeCorner.Parent = VersionBadge

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Name = "SubtitleLabel"
SubtitleLabel.Size = UDim2.new(1, -220, 0, 15)
SubtitleLabel.Position = UDim2.new(0, 32, 0, 30)
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Font = Enum.Font.Gotham
SubtitleLabel.Text = "Connecting to game universe..."
SubtitleLabel.TextColor3 = Color3.fromRGB(130, 137, 155)
SubtitleLabel.TextSize = 11
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
SubtitleLabel.Parent = Header

task.spawn(function()
    task.wait(0.4)
    local curPlayers = #Players:GetPlayers()
    SubtitleLabel.Text = string.format("%s  •  Current Server: %d players", gameTitle, curPlayers)
end)

-- Window Controls
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -38, 0, 12)
CloseBtn.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = Enum.Font.GothamMedium
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
CloseBtn.TextSize = 16
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

local CloseStroke = Instance.new("UIStroke")
CloseStroke.Color = Color3.fromRGB(36, 40, 56)
CloseStroke.Thickness = 1
CloseStroke.Parent = CloseBtn

setupHover(CloseBtn, Color3.fromRGB(24, 27, 38), Color3.fromRGB(45, 25, 30))
CloseBtn.MouseEnter:Connect(function()
    tween(CloseBtn, { TextColor3 = Color3.fromRGB(248, 113, 113) })
end)
CloseBtn.MouseLeave:Connect(function()
    tween(CloseBtn, { TextColor3 = Color3.fromRGB(160, 165, 180) })
end)

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Name = "MinimizeBtn"
MinimizeBtn.Size = UDim2.new(0, 28, 0, 28)
MinimizeBtn.Position = UDim2.new(1, -72, 0, 12)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Font = Enum.Font.GothamMedium
MinimizeBtn.Text = "−"
MinimizeBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
MinimizeBtn.TextSize = 16
MinimizeBtn.Parent = Header

local MinimizeCorner = Instance.new("UICorner")
MinimizeCorner.CornerRadius = UDim.new(0, 6)
MinimizeCorner.Parent = MinimizeBtn

local MinimizeStroke = Instance.new("UIStroke")
MinimizeStroke.Color = Color3.fromRGB(36, 40, 56)
MinimizeStroke.Thickness = 1
MinimizeStroke.Parent = MinimizeBtn

setupHover(MinimizeBtn, Color3.fromRGB(24, 27, 38), Color3.fromRGB(32, 36, 50))

makeDraggable(Header, MainFrame)

-- Floating Toggle Pill
local TogglePill = Instance.new("TextButton")
TogglePill.Name = "TogglePill"
TogglePill.Size = UDim2.new(0, 125, 0, 36)
TogglePill.Position = UDim2.new(0, 20, 0, 90)
TogglePill.BackgroundColor3 = Color3.fromRGB(17, 19, 26)
TogglePill.BorderSizePixel = 0
TogglePill.Font = Enum.Font.GothamBold
TogglePill.Text = "  ServerHop"
TogglePill.TextColor3 = Color3.fromRGB(240, 243, 250)
TogglePill.TextSize = 12
TogglePill.Visible = false
TogglePill.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 18)
PillCorner.Parent = TogglePill

local PillStroke = Instance.new("UIStroke")
PillStroke.Color = Color3.fromRGB(99, 102, 241)
PillStroke.Thickness = 1.2
PillStroke.Parent = TogglePill

local PillDot = Instance.new("Frame")
PillDot.Size = UDim2.new(0, 8, 0, 8)
PillDot.Position = UDim2.new(0, 14, 0.5, -4)
PillDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
PillDot.BorderSizePixel = 0
PillDot.Parent = TogglePill

local PillDotCorner = Instance.new("UICorner")
PillDotCorner.CornerRadius = UDim.new(1, 0)
PillDotCorner.Parent = PillDot

makeDraggable(TogglePill, TogglePill)

local function toggleMainWindow(visible)
    if visible == nil then
        MainFrame.Visible = not MainFrame.Visible
    else
        MainFrame.Visible = visible
    end
    TogglePill.Visible = not MainFrame.Visible
end

CloseBtn.MouseButton1Click:Connect(function()
    toggleMainWindow(false)
end)

MinimizeBtn.MouseButton1Click:Connect(function()
    toggleMainWindow(false)
end)

TogglePill.MouseButton1Click:Connect(function()
    toggleMainWindow(true)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightControl then
        toggleMainWindow()
    end
end)

-- Segmented Filter Tabs
local TabContainer = Instance.new("Frame")
TabContainer.Name = "TabContainer"
TabContainer.Size = UDim2.new(1, -28, 0, 34)
TabContainer.Position = UDim2.new(0, 14, 0, 62)
TabContainer.BackgroundColor3 = Color3.fromRGB(16, 18, 25)
TabContainer.BorderSizePixel = 0
TabContainer.Parent = MainFrame

local TabCorner = Instance.new("UICorner")
TabCorner.CornerRadius = UDim.new(0, 8)
TabCorner.Parent = TabContainer

local TabStroke = Instance.new("UIStroke")
TabStroke.Color = Color3.fromRGB(28, 32, 44)
TabStroke.Thickness = 1
TabStroke.Parent = TabContainer

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Padding = UDim.new(0, 4)
TabLayout.Parent = TabContainer

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingTop = UDim.new(0, 3)
TabPadding.PaddingBottom = UDim.new(0, 3)
TabPadding.PaddingLeft = UDim.new(0, 3)
TabPadding.PaddingRight = UDim.new(0, 3)
TabPadding.Parent = TabContainer

local tabs = {}

local function createTabButton(id, label, order)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Name = "Tab_" .. id
    TabBtn.Size = UDim2.new(0.333, -3, 1, 0)
    TabBtn.BackgroundColor3 = (id == activeTab) and Color3.fromRGB(32, 36, 52) or Color3.fromRGB(16, 18, 25)
    TabBtn.BackgroundTransparency = (id == activeTab) and 0 or 1
    TabBtn.BorderSizePixel = 0
    TabBtn.Font = Enum.Font.GothamBold
    TabBtn.Text = label
    TabBtn.TextColor3 = (id == activeTab) and Color3.fromRGB(240, 244, 255) or Color3.fromRGB(140, 146, 165)
    TabBtn.TextSize = 11
    TabBtn.LayoutOrder = order
    TabBtn.Parent = TabContainer

    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 6)
    BtnCorner.Parent = TabBtn

    tabs[id] = TabBtn
    return TabBtn
end

local TabSolo = createTabButton("solo", "Solo (1 Player)", 1)
local TabSmall = createTabButton("small", "Small (1-4 Players)", 2)
local TabAll = createTabButton("all", "All Servers", 3)

local updateActiveTab = nil

-- Primary Hero Action Bar
local HeroBar = Instance.new("Frame")
HeroBar.Name = "HeroBar"
HeroBar.Size = UDim2.new(1, -28, 0, 42)
HeroBar.Position = UDim2.new(0, 14, 0, 104)
HeroBar.BackgroundTransparency = 1
HeroBar.Parent = MainFrame

-- Hero Auto Hop Button
local AutoHopBtn = Instance.new("TextButton")
AutoHopBtn.Name = "AutoHopBtn"
AutoHopBtn.Size = UDim2.new(0.68, -4, 1, 0)
AutoHopBtn.Position = UDim2.new(0, 0, 0, 0)
AutoHopBtn.BackgroundColor3 = Color3.fromRGB(79, 70, 229)
AutoHopBtn.BorderSizePixel = 0
AutoHopBtn.Font = Enum.Font.GothamBold
AutoHopBtn.Text = "Auto Hop (Safe Solo)"
AutoHopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoHopBtn.TextSize = 12
AutoHopBtn.Parent = HeroBar

local AutoHopCorner = Instance.new("UICorner")
AutoHopCorner.CornerRadius = UDim.new(0, 8)
AutoHopCorner.Parent = AutoHopBtn

local AutoHopStroke = Instance.new("UIStroke")
AutoHopStroke.Color = Color3.fromRGB(99, 102, 241)
AutoHopStroke.Thickness = 1
AutoHopStroke.Parent = AutoHopBtn

setupHover(AutoHopBtn, Color3.fromRGB(79, 70, 229), Color3.fromRGB(99, 102, 241))

-- Refresh Button
local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Name = "RefreshBtn"
RefreshBtn.Size = UDim2.new(0.32, -4, 1, 0)
RefreshBtn.Position = UDim2.new(0.68, 4, 0, 0)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
RefreshBtn.BorderSizePixel = 0
RefreshBtn.Font = Enum.Font.GothamMedium
RefreshBtn.Text = "Refresh"
RefreshBtn.TextColor3 = Color3.fromRGB(220, 225, 238)
RefreshBtn.TextSize = 12
RefreshBtn.Parent = HeroBar

local RefreshCorner = Instance.new("UICorner")
RefreshCorner.CornerRadius = UDim.new(0, 8)
RefreshCorner.Parent = RefreshBtn

local RefreshStroke = Instance.new("UIStroke")
RefreshStroke.Color = Color3.fromRGB(36, 40, 56)
RefreshStroke.Thickness = 1
RefreshStroke.Parent = RefreshBtn

setupHover(RefreshBtn, Color3.fromRGB(22, 25, 34), Color3.fromRGB(30, 35, 48))

-- Secondary Filter Bar
local FilterBar = Instance.new("Frame")
FilterBar.Name = "FilterBar"
FilterBar.Size = UDim2.new(1, -28, 0, 30)
FilterBar.Position = UDim2.new(0, 14, 0, 154)
FilterBar.BackgroundTransparency = 1
FilterBar.Parent = MainFrame

local MaxPlayersLabel = Instance.new("TextLabel")
MaxPlayersLabel.Size = UDim2.new(0, 75, 1, 0)
MaxPlayersLabel.Position = UDim2.new(0, 0, 0, 0)
MaxPlayersLabel.BackgroundTransparency = 1
MaxPlayersLabel.Font = Enum.Font.Gotham
MaxPlayersLabel.Text = "Max Players:"
MaxPlayersLabel.TextColor3 = Color3.fromRGB(140, 146, 165)
MaxPlayersLabel.TextSize = 11
MaxPlayersLabel.TextXAlignment = Enum.TextXAlignment.Left
MaxPlayersLabel.Parent = FilterBar

local MaxTextBox = Instance.new("TextBox")
MaxTextBox.Name = "MaxTextBox"
MaxTextBox.Size = UDim2.new(0, 48, 0, 26)
MaxTextBox.Position = UDim2.new(0, 78, 0, 2)
MaxTextBox.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
MaxTextBox.BorderSizePixel = 0
MaxTextBox.Font = Enum.Font.GothamMedium
MaxTextBox.PlaceholderText = "Any"
MaxTextBox.PlaceholderColor3 = Color3.fromRGB(100, 106, 125)
MaxTextBox.Text = ""
MaxTextBox.TextColor3 = Color3.fromRGB(240, 244, 255)
MaxTextBox.TextSize = 11
MaxTextBox.ClearTextOnFocus = false
MaxTextBox.Parent = FilterBar

local MaxTextCorner = Instance.new("UICorner")
MaxTextCorner.CornerRadius = UDim.new(0, 6)
MaxTextCorner.Parent = MaxTextBox

local MaxTextStroke = Instance.new("UIStroke")
MaxTextStroke.Color = Color3.fromRGB(36, 40, 56)
MaxTextStroke.Thickness = 1
MaxTextStroke.Parent = MaxTextBox

local ExcludeCurrentBtn = Instance.new("TextButton")
ExcludeCurrentBtn.Name = "ExcludeCurrentBtn"
ExcludeCurrentBtn.Size = UDim2.new(0, 130, 0, 26)
ExcludeCurrentBtn.Position = UDim2.new(0, 134, 0, 2)
ExcludeCurrentBtn.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
ExcludeCurrentBtn.BorderSizePixel = 0
ExcludeCurrentBtn.Font = Enum.Font.Gotham
ExcludeCurrentBtn.Text = "● Hide Current Server"
ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(129, 140, 248)
ExcludeCurrentBtn.TextSize = 10
ExcludeCurrentBtn.Parent = FilterBar

local ExcludeCorner = Instance.new("UICorner")
ExcludeCorner.CornerRadius = UDim.new(0, 6)
ExcludeCorner.Parent = ExcludeCurrentBtn

local ExcludeStroke = Instance.new("UIStroke")
ExcludeStroke.Color = Color3.fromRGB(36, 40, 56)
ExcludeStroke.Thickness = 1
ExcludeStroke.Parent = ExcludeCurrentBtn

ExcludeCurrentBtn.MouseButton1Click:Connect(function()
    excludeCurrentActive = not excludeCurrentActive
    if excludeCurrentActive then
        ExcludeCurrentBtn.Text = "● Hide Current Server"
        ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(129, 140, 248)
    else
        ExcludeCurrentBtn.Text = "○ Show All Servers"
        ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(140, 146, 165)
    end
    if renderServerList then
        renderServerList()
    end
end)

local LoadMoreBtn = Instance.new("TextButton")
LoadMoreBtn.Name = "LoadMoreBtn"
LoadMoreBtn.Size = UDim2.new(0, 82, 0, 26)
LoadMoreBtn.Position = UDim2.new(1, -82, 0, 2)
LoadMoreBtn.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
LoadMoreBtn.BorderSizePixel = 0
LoadMoreBtn.Font = Enum.Font.GothamMedium
LoadMoreBtn.Text = "Load More"
LoadMoreBtn.TextColor3 = Color3.fromRGB(180, 186, 205)
LoadMoreBtn.TextSize = 10
LoadMoreBtn.Parent = FilterBar

local LoadMoreCorner = Instance.new("UICorner")
LoadMoreCorner.CornerRadius = UDim.new(0, 6)
LoadMoreCorner.Parent = LoadMoreBtn

local LoadMoreStroke = Instance.new("UIStroke")
LoadMoreStroke.Color = Color3.fromRGB(36, 40, 56)
LoadMoreStroke.Thickness = 1
LoadMoreStroke.Parent = LoadMoreBtn

setupHover(LoadMoreBtn, Color3.fromRGB(18, 20, 28), Color3.fromRGB(28, 32, 44))

-- Server Cards Container
local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, -28, 1, -225)
ScrollContainer.Position = UDim2.new(0, 14, 0, 192)
ScrollContainer.BackgroundColor3 = Color3.fromRGB(14, 15, 21)
ScrollContainer.BorderSizePixel = 0
ScrollContainer.ScrollBarThickness = 4
ScrollContainer.ScrollBarImageColor3 = Color3.fromRGB(60, 66, 85)
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.Parent = MainFrame

local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 8)
ScrollCorner.Parent = ScrollContainer

local ScrollStroke = Instance.new("UIStroke")
ScrollStroke.Color = Color3.fromRGB(26, 29, 40)
ScrollStroke.Thickness = 1
ScrollStroke.Parent = ScrollContainer

local ListLayout = Instance.new("UIListLayout")
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0, 6)
ListLayout.Parent = ScrollContainer

local ListPadding = Instance.new("UIPadding")
ListPadding.PaddingTop = UDim.new(0, 8)
ListPadding.PaddingBottom = UDim.new(0, 8)
ListPadding.PaddingLeft = UDim.new(0, 8)
ListPadding.PaddingRight = UDim.new(0, 8)
ListPadding.Parent = ScrollContainer

local EmptyLabel = Instance.new("TextLabel")
EmptyLabel.Name = "EmptyLabel"
EmptyLabel.Size = UDim2.new(1, 0, 0, 100)
EmptyLabel.BackgroundTransparency = 1
EmptyLabel.Font = Enum.Font.GothamMedium
EmptyLabel.Text = "Scanning active Roblox instances..."
EmptyLabel.TextColor3 = Color3.fromRGB(120, 126, 145)
EmptyLabel.TextSize = 12
EmptyLabel.Visible = true
EmptyLabel.Parent = ScrollContainer

-- Bottom Footer Status Bar
local FooterBar = Instance.new("Frame")
FooterBar.Name = "FooterBar"
FooterBar.Size = UDim2.new(1, 0, 0, 28)
FooterBar.Position = UDim2.new(0, 0, 1, -28)
FooterBar.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
FooterBar.BorderSizePixel = 0
FooterBar.Parent = MainFrame

local FooterTopLine = Instance.new("Frame")
FooterTopLine.Size = UDim2.new(1, 0, 0, 1)
FooterTopLine.Position = UDim2.new(0, 0, 0, 0)
FooterTopLine.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
FooterTopLine.BorderSizePixel = 0
FooterTopLine.Parent = FooterBar

local StatusDot = Instance.new("Frame")
StatusDot.Name = "StatusDot"
StatusDot.Size = UDim2.new(0, 6, 0, 6)
StatusDot.Position = UDim2.new(0, 16, 0.5, -3)
StatusDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
StatusDot.BorderSizePixel = 0
StatusDot.Parent = FooterBar

local StatusDotCorner = Instance.new("UICorner")
StatusDotCorner.CornerRadius = UDim.new(1, 0)
StatusDotCorner.Parent = StatusDot

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.Size = UDim2.new(1, -34, 1, 0)
StatusLabel.Position = UDim2.new(0, 28, 0, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Ready to discover servers"
StatusLabel.TextColor3 = Color3.fromRGB(140, 146, 165)
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
StatusLabel.Parent = FooterBar

setStatus = function(text, color)
    StatusLabel.Text = text
    StatusLabel.TextColor3 = color or Color3.fromRGB(140, 146, 165)
    if color == Color3.fromRGB(239, 68, 68) or color == Color3.fromRGB(248, 113, 113) then
        StatusDot.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
    elseif color == Color3.fromRGB(245, 158, 11) or color == Color3.fromRGB(251, 191, 36) then
        StatusDot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
    else
        StatusDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
    end
end

-- ========================================================================
-- ANTI-SWARM SELECTION ALGORITHM
-- ========================================================================
local function buildAntiSwarmCandidates(pool, mode, maxLimit)
    local eligible = {}
    for _, srv in ipairs(pool) do
        local p = srv.playing or 0
        local passMode = true
        if mode == "solo" then
            passMode = (p == 1)
        elseif mode == "small" then
            passMode = (p <= 4)
        end
        local passMax = (not maxLimit) or (p <= maxLimit)
        if not isServerBlacklisted(srv.id) and passMode and passMax and p < (srv.maxPlayers or 999) then
            table.insert(eligible, srv)
        end
    end
    if #eligible == 0 then return {} end

    table.sort(eligible, function(a, b)
        local aP = a.playing or 0
        local bP = b.playing or 0
        if aP ~= bP then return aP < bP end
        return (a.ping or 9999) < (b.ping or 9999)
    end)

    if mode == "solo" or (mode == "small" and (eligible[1].playing or 0) == 1) then
        local onePlayerList = {}
        local restList = {}
        for _, srv in ipairs(eligible) do
            if (srv.playing or 0) == 1 then
                table.insert(onePlayerList, srv)
            else
                table.insert(restList, srv)
            end
        end

        if #onePlayerList >= 5 then
            local safePool = {}
            for i = 3, math.min(#onePlayerList, 25) do
                table.insert(safePool, onePlayerList[i])
            end
            for i = #safePool, 2, -1 do
                local j = math.random(i)
                safePool[i], safePool[j] = safePool[j], safePool[i]
            end
            local finalResult = {}
            for _, s in ipairs(safePool) do
                table.insert(finalResult, s)
            end
            for i = 26, #onePlayerList do
                table.insert(finalResult, onePlayerList[i])
            end
            table.insert(finalResult, onePlayerList[1])
            table.insert(finalResult, onePlayerList[2])
            for _, s in ipairs(restList) do
                table.insert(finalResult, s)
            end
            return finalResult
        end
    end
    return eligible
end

updateActiveTab = function(newTab)
    activeTab = newTab
    for tabId, btn in pairs(tabs) do
        if tabId == activeTab then
            tween(btn, {
                BackgroundColor3 = Color3.fromRGB(32, 36, 52),
                BackgroundTransparency = 0,
                TextColor3 = Color3.fromRGB(240, 244, 255)
            })
        else
            tween(btn, {
                BackgroundTransparency = 1,
                TextColor3 = Color3.fromRGB(140, 146, 165)
            })
        end
    end

    if not isHopping then
        if activeTab == "solo" then
            AutoHopBtn.Text = "Auto Hop (Safe Solo)"
            AutoHopBtn.BackgroundColor3 = Color3.fromRGB(79, 70, 229)
        elseif activeTab == "small" then
            AutoHopBtn.Text = "Auto Hop (Small Server)"
            AutoHopBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
        else
            AutoHopBtn.Text = "Auto Hop to Smallest Server"
            AutoHopBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
        end
    end

    if renderServerList then
        renderServerList()
    end
end

TabSolo.MouseButton1Click:Connect(function() updateActiveTab("solo") end)
TabSmall.MouseButton1Click:Connect(function() updateActiveTab("small") end)
TabAll.MouseButton1Click:Connect(function() updateActiveTab("all") end)
-- ========================================================================
-- MODERN SERVER CARD CREATION
-- ========================================================================

local function createServerCard(serverData, index)
    local isCurrent = (serverData.id == CurrentJobId)
    local isBlacklisted = isServerBlacklisted(serverData.id)
    local playing = serverData.playing or 0
    local maxPlayers = serverData.maxPlayers or 0
    local isSolo = (playing == 1)
    local pingNum = serverData.ping and math.floor(serverData.ping) or nil
    local pingText = pingNum and string.format("%d ms", pingNum) or "N/A"
    local fpsText = serverData.fps and string.format("%.0f fps", serverData.fps) or "60 fps"
    local shortId = string.sub(serverData.id or "unknown", 1, 8)

    local Card = Instance.new("Frame")
    Card.Name = "ServerCard_" .. tostring(index)
    Card.Size = UDim2.new(1, 0, 0, 60)
    Card.BackgroundColor3 = isCurrent and Color3.fromRGB(24, 28, 40) or Color3.fromRGB(19, 21, 29)
    Card.BorderSizePixel = 0
    Card.LayoutOrder = index
    Card.Parent = ScrollContainer

    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 8)
    CardCorner.Parent = Card

    local CardStroke = Instance.new("UIStroke")
    if isCurrent then
        CardStroke.Color = Color3.fromRGB(99, 102, 241)
    elseif isBlacklisted then
        CardStroke.Color = Color3.fromRGB(120, 40, 45)
    elseif isSolo then
        CardStroke.Color = Color3.fromRGB(79, 70, 229)
    else
        CardStroke.Color = Color3.fromRGB(30, 34, 46)
    end
    CardStroke.Thickness = 1
    CardStroke.Parent = Card

    -- Interactive hover feedback
    Card.MouseEnter:Connect(function()
        if not isCurrent and not isBlacklisted then
            tween(Card, { BackgroundColor3 = Color3.fromRGB(23, 26, 36) })
            tween(CardStroke, { Color = Color3.fromRGB(48, 54, 74) })
        end
    end)
    Card.MouseLeave:Connect(function()
        if not isCurrent and not isBlacklisted then
            tween(Card, { BackgroundColor3 = Color3.fromRGB(19, 21, 29) })
            tween(CardStroke, { Color = isSolo and Color3.fromRGB(79, 70, 229) or Color3.fromRGB(30, 34, 46) })
        end
    end)

    -- Ping status indicator dot
    local PingDot = Instance.new("Frame")
    PingDot.Size = UDim2.new(0, 6, 0, 6)
    PingDot.Position = UDim2.new(0, 12, 0, 15)
    PingDot.BorderSizePixel = 0
    PingDot.Parent = Card

    if pingNum and pingNum <= 100 then
        PingDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
    elseif pingNum and pingNum <= 200 then
        PingDot.BackgroundColor3 = Color3.fromRGB(251, 191, 36)
    else
        PingDot.BackgroundColor3 = Color3.fromRGB(248, 113, 113)
    end

    local PingDotCorner = Instance.new("UICorner")
    PingDotCorner.CornerRadius = UDim.new(1, 0)
    PingDotCorner.Parent = PingDot

    -- Population Tag
    local PopTag = Instance.new("TextLabel")
    PopTag.Size = UDim2.new(0, isSolo and 74 or 62, 0, 18)
    PopTag.Position = UDim2.new(0, 24, 0, 9)
    PopTag.BackgroundColor3 = isSolo and Color3.fromRGB(45, 38, 85) or (playing <= 3 and Color3.fromRGB(20, 48, 38) or Color3.fromRGB(26, 30, 42))
    PopTag.BorderSizePixel = 0
    PopTag.Font = Enum.Font.GothamBold
    PopTag.Text = isSolo and "SOLO SERVER" or (playing <= 3 and "LOW POP" or "PUBLIC")
    PopTag.TextColor3 = isSolo and Color3.fromRGB(165, 180, 252) or (playing <= 3 and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(148, 163, 184))
    PopTag.TextSize = 9
    PopTag.Parent = Card

    local PopCorner = Instance.new("UICorner")
    PopCorner.CornerRadius = UDim.new(0, 4)
    PopCorner.Parent = PopTag

    -- Player Count Label
    local PlayerLabel = Instance.new("TextLabel")
    PlayerLabel.Size = UDim2.new(0, 140, 0, 18)
    PlayerLabel.Position = UDim2.new(0, isSolo and 104 or 92, 0, 9)
    PlayerLabel.BackgroundTransparency = 1
    PlayerLabel.Font = Enum.Font.GothamBold
    PlayerLabel.Text = string.format("%d / %d Players", playing, maxPlayers)
    PlayerLabel.TextColor3 = Color3.fromRGB(240, 243, 250)
    PlayerLabel.TextSize = 12
    PlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
    PlayerLabel.Parent = Card

    -- Metrics Subtitle
    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Size = UDim2.new(1, -210, 0, 16)
    InfoLabel.Position = UDim2.new(0, 12, 0, 34)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Font = Enum.Font.Gotham
    InfoLabel.Text = string.format("Ping: %s  •  FPS: %s  •  ID: %s", pingText, fpsText, shortId)
    InfoLabel.TextColor3 = Color3.fromRGB(120, 126, 145)
    InfoLabel.TextSize = 10
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.Parent = Card

    -- Copy GUID Button
    local CopyBtn = Instance.new("TextButton")
    CopyBtn.Name = "CopyBtn"
    CopyBtn.Size = UDim2.new(0, 56, 0, 28)
    CopyBtn.Position = UDim2.new(1, -142, 0, 16)
    CopyBtn.BackgroundColor3 = Color3.fromRGB(26, 29, 39)
    CopyBtn.BorderSizePixel = 0
    CopyBtn.Font = Enum.Font.GothamMedium
    CopyBtn.Text = "Copy"
    CopyBtn.TextColor3 = Color3.fromRGB(180, 185, 202)
    CopyBtn.TextSize = 11
    CopyBtn.Parent = Card

    local CopyCorner = Instance.new("UICorner")
    CopyCorner.CornerRadius = UDim.new(0, 6)
    CopyCorner.Parent = CopyBtn

    local CopyStroke = Instance.new("UIStroke")
    CopyStroke.Color = Color3.fromRGB(36, 40, 56)
    CopyStroke.Thickness = 1
    CopyStroke.Parent = CopyBtn

    setupHover(CopyBtn, Color3.fromRGB(26, 29, 39), Color3.fromRGB(36, 41, 56))

    CopyBtn.MouseButton1Click:Connect(function()
        local copied = copyToClipboard(serverData.id)
        if copied then
            CopyBtn.Text = "Done"
            CopyBtn.TextColor3 = Color3.fromRGB(52, 211, 153)
            task.delay(1.4, function()
                CopyBtn.Text = "Copy"
                CopyBtn.TextColor3 = Color3.fromRGB(180, 185, 202)
            end)
        end
    end)

    -- Join Button
    local JoinBtn = Instance.new("TextButton")
    JoinBtn.Name = "JoinBtn"
    JoinBtn.Size = UDim2.new(0, 72, 0, 28)
    JoinBtn.Position = UDim2.new(1, -80, 0, 16)
    JoinBtn.BorderSizePixel = 0
    JoinBtn.Font = Enum.Font.GothamBold
    JoinBtn.TextSize = 11
    JoinBtn.Parent = Card

    local JoinCorner = Instance.new("UICorner")
    JoinCorner.CornerRadius = UDim.new(0, 6)
    JoinCorner.Parent = JoinBtn

    if isCurrent then
        JoinBtn.BackgroundColor3 = Color3.fromRGB(34, 38, 50)
        JoinBtn.Text = "Current"
        JoinBtn.TextColor3 = Color3.fromRGB(130, 136, 155)
        JoinBtn.AutoButtonColor = false
    elseif isBlacklisted then
        JoinBtn.BackgroundColor3 = Color3.fromRGB(48, 25, 28)
        JoinBtn.Text = "Closed"
        JoinBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
        JoinBtn.AutoButtonColor = false
    else
        local btnBg = isSolo and Color3.fromRGB(79, 70, 229) or Color3.fromRGB(16, 185, 129)
        local btnHover = isSolo and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(5, 150, 105)
        JoinBtn.BackgroundColor3 = btnBg
        JoinBtn.Text = isSolo and "Join Solo" or "Join"
        JoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

        setupHover(JoinBtn, btnBg, btnHover)

        JoinBtn.MouseButton1Click:Connect(function()
            if isHopping then return end
            JoinBtn.Text = "..."
            setStatus(string.format("Connecting to instance (%d players)...", playing), Color3.fromRGB(245, 158, 11))
            notify("Server Hop", string.format("Connecting to server (%d players)...", playing), 3)

            setupQueueOnTeleport()

            local success, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(PlaceId, serverData.id, LocalPlayer)
            end)

            if not success then
                addServerToBlacklist(serverData.id)
                JoinBtn.Text = "Failed"
                JoinBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
                setStatus("Connection failed: " .. tostring(err), Color3.fromRGB(239, 68, 68))
                notify("Failed", "Server is inaccessible or closed.", 3)
                task.delay(2, function()
                    JoinBtn.Text = isSolo and "Join Solo" or "Join"
                    JoinBtn.BackgroundColor3 = btnBg
                end)
            end
        end)
    end

    return Card
end

-- Render Server Cards to ScrollContainer
renderServerList = function()
    for _, child in ipairs(ScrollContainer:GetChildren()) do
        if child:IsA("Frame") and child.Name:sub(1, 11) == "ServerCard_" then
            child:Destroy()
        end
    end

    local maxLimit = tonumber(MaxTextBox.Text)
    local filtered = {}

    for _, srv in ipairs(loadedServers) do
        local p = srv.playing or 0
        local passTab = true
        if activeTab == "solo" then
            passTab = (p == 1)
        elseif activeTab == "small" then
            passTab = (p <= 4)
        end

        local passMax = (not maxLimit) or (p <= maxLimit)
        local passCurrent = (not excludeCurrentActive) or (srv.id ~= CurrentJobId)

        if passTab and passMax and passCurrent then
            table.insert(filtered, srv)
        end
    end

    -- Sort ascending by player count, then latency
    table.sort(filtered, function(a, b)
        local aPlaying = a.playing or 0
        local bPlaying = b.playing or 0
        if aPlaying ~= bPlaying then
            return aPlaying < bPlaying
        end
        local aPing = a.ping or 9999
        local bPing = b.ping or 9999
        return aPing < bPing
    end)

    if #filtered == 0 then
        EmptyLabel.Visible = true
        EmptyLabel.Text = (isFetching and "Scanning active Roblox instances..." or "No servers match current filter settings.")
    else
        EmptyLabel.Visible = false
        for index, srv in ipairs(filtered) do
            createServerCard(srv, index)
        end
    end

    if not isHopping then
        local tabName = (activeTab == "solo" and "solo" or (activeTab == "small" and "small" or "public"))
        setStatus(string.format("%d %s servers available", #filtered, tabName), Color3.fromRGB(140, 146, 165))
    end
end

-- ========================================================================
-- ROBLOX API FETCHING WITH 429 ADAPTIVE BACKOFF
-- ========================================================================

local function fetchRobloxServers(cursor)
    if isFetching then return end
    isFetching = true
    setStatus("Querying official Roblox game instances...", Color3.fromRGB(129, 140, 248))
    EmptyLabel.Text = "Scanning active instances..."
    EmptyLabel.Visible = true

    task.spawn(function()
        local cursorParam = (cursor and cursor ~= "") and ("&cursor=" .. safeUrlEncode(cursor)) or ""
        local url = string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s",
            tostring(PlaceId),
            cursorParam
        )

        local body = nil
        for attempt = 1, 2 do
            body = httpRequest(url)
            if body and body ~= "" and not string.find(body, "Too Many Requests") then
                break
            end
            task.wait(1.5)
        end

        isFetching = false

        if not body then
            setStatus("Network request error. Verify executor capabilities.", Color3.fromRGB(239, 68, 68))
            EmptyLabel.Text = "Failed to query servers. Executor HTTP support required."
            return
        end

        local decodeSuccess, parsed = pcall(function()
            return HttpService:JSONDecode(body)
        end)

        if not decodeSuccess or not parsed or not parsed.data then
            setStatus("Malformed response payload from Roblox API.", Color3.fromRGB(239, 68, 68))
            EmptyLabel.Text = "Could not parse JSON response."
            return
        end

        nextPageCursor = parsed.nextPageCursor or ""

        if not cursor or cursor == "" then
            loadedServers = {}
        end

        for _, srv in ipairs(parsed.data) do
            local exists = false
            for _, existing in ipairs(loadedServers) do
                if existing.id == srv.id then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(loadedServers, srv)
            end
        end

        renderServerList()
    end)
end

-- ========================================================================
-- RESILIENT HOP WATCHDOG & FALLBACK ENGINE
-- ========================================================================

stopHopping = function(reason)
    isHopping = false
    currentHopIndex = 1
    hopCandidates = {}
    if activeTab == "solo" then
        AutoHopBtn.Text = "Auto Hop (Safe Solo)"
        AutoHopBtn.BackgroundColor3 = Color3.fromRGB(79, 70, 229)
    elseif activeTab == "small" then
        AutoHopBtn.Text = "Auto Hop (Small Server)"
        AutoHopBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
    else
        AutoHopBtn.Text = "Auto Hop to Smallest Server"
        AutoHopBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
    end

    if reason then
        notify("Server Hop", reason, 4)
        setStatus(reason, Color3.fromRGB(239, 68, 68))
    end
end

executeHopAttempt = function()
    if not isHopping then return end

    -- Find next candidate that isn't blacklisted and isn't the current server
    while currentHopIndex <= #hopCandidates do
        local candidate = hopCandidates[currentHopIndex]
        if candidate and not isServerBlacklisted(candidate.id) and candidate.id ~= CurrentJobId then
            break
        end
        currentHopIndex = currentHopIndex + 1
    end

    if currentHopIndex > #hopCandidates then
        stopHopping("All available candidate instances attempted. Refresh to rescan.")
        return
    end

    local target = hopCandidates[currentHopIndex]
    local pCount = target.playing or 0
    local maxP = target.maxPlayers or 0

    local hopMsg = string.format("Attempting Instance #%d (%d/%d players)...", currentHopIndex, pCount, maxP)
    setStatus(hopMsg, Color3.fromRGB(245, 158, 11))
    notify("Server Hop", hopMsg, 3)

    setupQueueOnTeleport()

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceId, target.id, LocalPlayer)
    end)

    if not success then
        addServerToBlacklist(target.id)
        currentHopIndex = currentHopIndex + 1
        setStatus(string.format("Instance #%d failed. Trying next candidate...", currentHopIndex - 1), Color3.fromRGB(239, 68, 68))
        task.wait(1)
        executeHopAttempt()
    else
        -- 8-second watchdog for hanging connections
        task.delay(15, function()
            if isHopping and currentHopIndex <= #hopCandidates and hopCandidates[currentHopIndex].id == target.id then
                setStatus("Connection timeout. Trying next candidate...", Color3.fromRGB(245, 158, 11))
                addServerToBlacklist(target.id)
                currentHopIndex = currentHopIndex + 1
                executeHopAttempt()
            end
        end)
    end
end

-- Teleport Failure Listener (Crucial for handling ghost / restricted servers)
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == LocalPlayer then
        local errStr = tostring(errorMessage or "Inaccessible server")
        if isHopping and currentHopIndex <= #hopCandidates then
            local failedServer = hopCandidates[currentHopIndex]
            if failedServer then
                addServerToBlacklist(failedServer.id)
            end
            currentHopIndex = currentHopIndex + 1
            setStatus(string.format("Instance closed (%s). Advancing to next candidate...", errStr), Color3.fromRGB(239, 68, 68))
            notify("Server Hop", "Instance was closed or full. Retrying next...", 3)
            task.wait(0.5)
            executeHopAttempt()
        else
            setStatus("Teleport failed: " .. errStr, Color3.fromRGB(239, 68, 68))
            notify("Teleport Failed", errStr, 4)
        end
    end
end)

-- Start Hop Sequence based on active tab
local function startHopSequence()
    if isHopping then
        stopHopping("Auto hop canceled by user.")
        return
    end

    isHopping = true
    currentHopIndex = 1
    AutoHopBtn.Text = "Cancel Auto Hop"
    AutoHopBtn.BackgroundColor3 = Color3.fromRGB(225, 29, 72)
    setStatus("Building sorted candidate list...", Color3.fromRGB(99, 102, 241))

    local maxLimit = tonumber(MaxTextBox.Text)
    hopCandidates = buildAntiSwarmCandidates(loadedServers, activeTab, maxLimit)

    if #hopCandidates > 0 then
        executeHopAttempt()
        return
    end

    -- Fetch direct if none loaded yet
    task.spawn(function()
        setStatus("Fetching candidate instances from Roblox...", Color3.fromRGB(99, 102, 241))
        local url = string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100",
            tostring(PlaceId)
        )
        local body = httpRequest(url)
        if not body or not isHopping then
            if isHopping then stopHopping("Failed to fetch instances from Roblox API.") end
            return
        end

        local decodeSuccess, parsed = pcall(function()
            return HttpService:JSONDecode(body)
        end)

        if decodeSuccess and parsed and parsed.data and isHopping then
            hopCandidates = buildAntiSwarmCandidates(parsed.data, activeTab, maxLimit)

            if #hopCandidates > 0 then
                executeHopAttempt()
            else
                local emptyMsg = (activeTab == "solo")
                    and "No 1-player instances found. Try Small or All tab."
                    or "No eligible servers found."
                stopHopping(emptyMsg)
            end
        else
            if isHopping then stopHopping("Invalid API response.") end
        end
    end)
end

-- ========================================================================
-- EVENT HOOKS
-- ========================================================================

AutoHopBtn.MouseButton1Click:Connect(function()
    startHopSequence()
end)

RefreshBtn.MouseButton1Click:Connect(function()
    if isHopping then
        stopHopping("Stopped for rescan.")
    end
    fetchRobloxServers("")
end)

LoadMoreBtn.MouseButton1Click:Connect(function()
    if isFetching or isHopping then return end
    if nextPageCursor and nextPageCursor ~= "" then
        fetchRobloxServers(nextPageCursor)
    else
        setStatus("No further server pages available.", Color3.fromRGB(245, 158, 11))
    end
end)

MaxTextBox:GetPropertyChangedSignal("Text"):Connect(function()
    renderServerList()
end)

-- Initial Auto-Search
task.spawn(function()
    task.wait(0.2)
    fetchRobloxServers("")
end)

print("[ServerHop] Initialized successfully. Press RightControl to toggle.")
