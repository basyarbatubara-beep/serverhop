--[[
    ========================================================================
    ⚡ ROBLOX NO-GIMMICK SMALL SERVER FINDER & AUTO-JOINER
    ========================================================================
    Fitur Utama:
    - Mencari server sepi (1-3 pemain) langsung dari API resmi Roblox.
    - Urutan ascending: Pemain paling sedikit diprioritaskan + Ping terendah.
    - AUTO-HOP DENGAN RETRY OTOMATIS (NO GIMMICK):
      Jika server tujuan tutup/ghost/penuh (Error 773), script OTOMATIS
      mencoba server sepi berikutnya sampai BERHASIL masuk!
    - 1-Click Join untuk memilih server tertentu langsung dari daftar.
    - Filter Maksimal Pemain secara real-time.
    - Draggable UI (Mouse & Touch screen untuk Mobile).
    - Tombol Toggle melayang & Hotkey RightControl.
    - Dukungan luas: Delta, Codex, Krnl, Solara, Wave, Fluxus, Arceus X, dll.
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
if getgenv and getgenv().NoGimmickServerFinderInstance then
    pcall(function()
        getgenv().NoGimmickServerFinderInstance:Destroy()
    end)
    getgenv().NoGimmickServerFinderInstance = nil
end

-- Notification Helper
local function notify(title, message, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Server Finder",
            Text = message or "",
            Duration = duration or 3
        })
    end)
end

-- Resolve GUI Container (gethui -> CoreGui -> PlayerGui)
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

-- URL Encode Helper
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

-- Robust HTTP Request Helper (Supports multiple executor methods)
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

-- Clipboard Helper
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

-- Draggable implementation (PC Mouse + Mobile Touch)
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

-- Executor Teleport Queue (Proof of arrival in new server)
local function setupQueueOnTeleport()
    local queueFunc = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    if queueFunc then
        pcall(function()
            queueFunc([[
                task.spawn(function()
                    repeat task.wait(0.5) until game:IsLoaded()
                    local StarterGui = game:GetService("StarterGui")
                    task.wait(1.5)
                    pcall(function()
                        StarterGui:SetCore("SendNotification", {
                            Title = "⚡ Server Sepi Berhasil!",
                            Text = "Kamu berhasil masuk ke server baru!",
                            Duration = 6
                        })
                    end)
                end)
            ]])
        end)
    end
end

-- Get Game Title
local gameTitle = "Place: " .. tostring(PlaceId)
task.spawn(function()
    local success, productInfo = pcall(function()
        return MarketplaceService:GetProductInfo(PlaceId)
    end)
    if success and productInfo and productInfo.Name then
        gameTitle = productInfo.Name
    end
end)

-- State Variables
local loadedServers = {}
local blacklistServers = {}
local nextPageCursor = ""
local isFetching = false
local isHopping = false
local currentHopIndex = 1
local hopCandidates = {}
local excludeCurrentActive = true

-- Forward references
local setStatus = nil
local renderServerList = nil
local stopHopping = nil
local executeHopAttempt = nil
-- ========================================================================
-- USER INTERFACE
-- ========================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RobloxNoGimmickServerFinder"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = getGuiContainer()

if getgenv then
    getgenv().NoGimmickServerFinderInstance = ScreenGui
end

-- Main Window
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 490)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -245)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(45, 50, 65)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame

-- Top Bar (Header)
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 48)
TopBar.BackgroundColor3 = Color3.fromRGB(27, 30, 40)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopBarCorner = Instance.new("UICorner")
TopBarCorner.CornerRadius = UDim.new(0, 10)
TopBarCorner.Parent = TopBar

local TopBarFix = Instance.new("Frame")
TopBarFix.Size = UDim2.new(1, 0, 0, 12)
TopBarFix.Position = UDim2.new(0, 0, 1, -12)
TopBarFix.BackgroundColor3 = Color3.fromRGB(27, 30, 40)
TopBarFix.BorderSizePixel = 0
TopBarFix.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(1, -110, 0, 24)
TitleLabel.Position = UDim2.new(0, 14, 0, 4)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "⚡ SERVER FINDER (NO GIMMICK)"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Name = "SubtitleLabel"
SubtitleLabel.Size = UDim2.new(1, -110, 0, 16)
SubtitleLabel.Position = UDim2.new(0, 14, 0, 26)
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Font = Enum.Font.Gotham
SubtitleLabel.Text = "Memuat data game..."
SubtitleLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
SubtitleLabel.TextSize = 11
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.Parent = TopBar

task.spawn(function()
    task.wait(0.5)
    local curPlayers = #Players:GetPlayers()
    SubtitleLabel.Text = string.format("%s • Saat ini: %d pemain", gameTitle, curPlayers)
end)

-- Window Controls
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -38, 0, 9)
CloseBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 56)
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseBtn.TextSize = 13
CloseBtn.Parent = TopBar

local CloseBtnCorner = Instance.new("UICorner")
CloseBtnCorner.CornerRadius = UDim.new(0, 6)
CloseBtnCorner.Parent = CloseBtn

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Name = "MinimizeBtn"
MinimizeBtn.Size = UDim2.new(0, 30, 0, 30)
MinimizeBtn.Position = UDim2.new(1, -74, 0, 9)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 56)
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
MinimizeBtn.TextSize = 13
MinimizeBtn.Parent = TopBar

local MinimizeBtnCorner = Instance.new("UICorner")
MinimizeBtnCorner.CornerRadius = UDim.new(0, 6)
MinimizeBtnCorner.Parent = MinimizeBtn

makeDraggable(TopBar, MainFrame)

-- Floating Toggle Button (Mobile Friendly)
local TogglePill = Instance.new("TextButton")
TogglePill.Name = "TogglePill"
TogglePill.Size = UDim2.new(0, 145, 0, 38)
TogglePill.Position = UDim2.new(0, 20, 0, 100)
TogglePill.BackgroundColor3 = Color3.fromRGB(27, 30, 40)
TogglePill.BorderSizePixel = 0
TogglePill.Font = Enum.Font.GothamBold
TogglePill.Text = "⚡ Server Sepi"
TogglePill.TextColor3 = Color3.fromRGB(255, 255, 255)
TogglePill.TextSize = 13
TogglePill.Visible = false
TogglePill.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 19)
PillCorner.Parent = TogglePill

local PillStroke = Instance.new("UIStroke")
PillStroke.Color = Color3.fromRGB(16, 185, 129)
PillStroke.Thickness = 1.5
PillStroke.Parent = TogglePill

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

-- Main Action Bar (Auto Hop & Refresh)
local ActionBar = Instance.new("Frame")
ActionBar.Name = "ActionBar"
ActionBar.Size = UDim2.new(1, -24, 0, 40)
ActionBar.Position = UDim2.new(0, 12, 0, 56)
ActionBar.BackgroundTransparency = 1
ActionBar.Parent = MainFrame

-- Auto Hop Button (The Core Feature)
local AutoHopBtn = Instance.new("TextButton")
AutoHopBtn.Name = "AutoHopBtn"
AutoHopBtn.Size = UDim2.new(0.52, -4, 1, 0)
AutoHopBtn.Position = UDim2.new(0, 0, 0, 0)
AutoHopBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
AutoHopBtn.BorderSizePixel = 0
AutoHopBtn.Font = Enum.Font.GothamBold
AutoHopBtn.Text = "🚀 JOIN SERVER SEPI (AUTO)"
AutoHopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoHopBtn.TextSize = 12
AutoHopBtn.Parent = ActionBar

local AutoHopCorner = Instance.new("UICorner")
AutoHopCorner.CornerRadius = UDim.new(0, 8)
AutoHopCorner.Parent = AutoHopBtn

-- Refresh Button
local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Name = "RefreshBtn"
RefreshBtn.Size = UDim2.new(0.24, -4, 1, 0)
RefreshBtn.Position = UDim2.new(0.52, 4, 0, 0)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
RefreshBtn.BorderSizePixel = 0
RefreshBtn.Font = Enum.Font.GothamMedium
RefreshBtn.Text = "🔄 Refresh"
RefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RefreshBtn.TextSize = 12
RefreshBtn.Parent = ActionBar

local RefreshCorner = Instance.new("UICorner")
RefreshCorner.CornerRadius = UDim.new(0, 8)
RefreshCorner.Parent = RefreshBtn

-- Load More Button
local LoadMoreBtn = Instance.new("TextButton")
LoadMoreBtn.Name = "LoadMoreBtn"
LoadMoreBtn.Size = UDim2.new(0.24, -4, 1, 0)
LoadMoreBtn.Position = UDim2.new(0.76, 4, 0, 0)
LoadMoreBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
LoadMoreBtn.BorderSizePixel = 0
LoadMoreBtn.Font = Enum.Font.GothamMedium
LoadMoreBtn.Text = "📥 Lebih Banyak"
LoadMoreBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
LoadMoreBtn.TextSize = 11
LoadMoreBtn.Parent = ActionBar

local LoadMoreCorner = Instance.new("UICorner")
LoadMoreCorner.CornerRadius = UDim.new(0, 8)
LoadMoreCorner.Parent = LoadMoreBtn

-- Filter & Status Bar
local FilterBar = Instance.new("Frame")
FilterBar.Name = "FilterBar"
FilterBar.Size = UDim2.new(1, -24, 0, 30)
FilterBar.Position = UDim2.new(0, 12, 0, 102)
FilterBar.BackgroundTransparency = 1
FilterBar.Parent = MainFrame

local MaxLabel = Instance.new("TextLabel")
MaxLabel.Name = "MaxLabel"
MaxLabel.Size = UDim2.new(0, 75, 1, 0)
MaxLabel.Position = UDim2.new(0, 0, 0, 0)
MaxLabel.BackgroundTransparency = 1
MaxLabel.Font = Enum.Font.Gotham
MaxLabel.Text = "Maks Pemain:"
MaxLabel.TextColor3 = Color3.fromRGB(180, 185, 195)
MaxLabel.TextSize = 11
MaxLabel.TextXAlignment = Enum.TextXAlignment.Left
MaxLabel.Parent = FilterBar

local MaxTextBox = Instance.new("TextBox")
MaxTextBox.Name = "MaxTextBox"
MaxTextBox.Size = UDim2.new(0, 45, 0, 26)
MaxTextBox.Position = UDim2.new(0, 78, 0, 2)
MaxTextBox.BackgroundColor3 = Color3.fromRGB(28, 31, 41)
MaxTextBox.BorderSizePixel = 0
MaxTextBox.Font = Enum.Font.GothamMedium
MaxTextBox.PlaceholderText = "Semua"
MaxTextBox.PlaceholderColor3 = Color3.fromRGB(110, 115, 130)
MaxTextBox.Text = ""
MaxTextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
MaxTextBox.TextSize = 12
MaxTextBox.ClearTextOnFocus = false
MaxTextBox.Parent = FilterBar

local MaxTextCorner = Instance.new("UICorner")
MaxTextCorner.CornerRadius = UDim.new(0, 6)
MaxTextCorner.Parent = MaxTextBox

local MaxTextStroke = Instance.new("UIStroke")
MaxTextStroke.Color = Color3.fromRGB(45, 50, 65)
MaxTextStroke.Thickness = 1
MaxTextStroke.Parent = MaxTextBox

-- Toggle Exclude Current Server
local ExcludeCurrentBtn = Instance.new("TextButton")
ExcludeCurrentBtn.Name = "ExcludeCurrentBtn"
ExcludeCurrentBtn.Size = UDim2.new(0, 125, 0, 26)
ExcludeCurrentBtn.Position = UDim2.new(0, 130, 0, 2)
ExcludeCurrentBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 41)
ExcludeCurrentBtn.BorderSizePixel = 0
ExcludeCurrentBtn.Font = Enum.Font.Gotham
ExcludeCurrentBtn.Text = "✔ Lewati Server Ini"
ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(96, 165, 250)
ExcludeCurrentBtn.TextSize = 10
ExcludeCurrentBtn.Parent = FilterBar

local ExcludeCorner = Instance.new("UICorner")
ExcludeCorner.CornerRadius = UDim.new(0, 6)
ExcludeCorner.Parent = ExcludeCurrentBtn

local ExcludeStroke = Instance.new("UIStroke")
ExcludeStroke.Color = Color3.fromRGB(45, 50, 65)
ExcludeStroke.Thickness = 1
ExcludeStroke.Parent = ExcludeCurrentBtn

ExcludeCurrentBtn.MouseButton1Click:Connect(function()
    excludeCurrentActive = not excludeCurrentActive
    if excludeCurrentActive then
        ExcludeCurrentBtn.Text = "✔ Lewati Server Ini"
        ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(96, 165, 250)
    else
        ExcludeCurrentBtn.Text = "✕ Tampilkan Semua"
        ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(156, 163, 175)
    end
    if renderServerList then
        renderServerList()
    end
end)

-- Status Text
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.Size = UDim2.new(1, -260, 1, 0)
StatusLabel.Position = UDim2.new(0, 260, 0, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Siap mencari server sepi..."
StatusLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
StatusLabel.Parent = FilterBar

setStatus = function(text, color)
    StatusLabel.Text = text
    StatusLabel.TextColor3 = color or Color3.fromRGB(156, 163, 175)
end

-- Server List Container
local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, -24, 1, -146)
ScrollContainer.Position = UDim2.new(0, 12, 0, 138)
ScrollContainer.BackgroundColor3 = Color3.fromRGB(16, 18, 23)
ScrollContainer.BorderSizePixel = 0
ScrollContainer.ScrollBarThickness = 5
ScrollContainer.ScrollBarImageColor3 = Color3.fromRGB(75, 85, 99)
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.Parent = MainFrame

local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 8)
ScrollCorner.Parent = ScrollContainer

local ScrollStroke = Instance.new("UIStroke")
ScrollStroke.Color = Color3.fromRGB(35, 38, 48)
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
EmptyLabel.Text = "Klik 'Refresh' atau 'JOIN SERVER SEPI' untuk memindai server."
EmptyLabel.TextColor3 = Color3.fromRGB(120, 125, 140)
EmptyLabel.TextSize = 12
EmptyLabel.Visible = true
EmptyLabel.Parent = ScrollContainer
-- ========================================================================
-- ROBUST SERVER CARD CREATION
-- ========================================================================

local function createServerCard(serverData, index)
    local isCurrent = (serverData.id == CurrentJobId)
    local isBlacklisted = (blacklistServers[serverData.id] == true)
    local playing = serverData.playing or 0
    local maxPlayers = serverData.maxPlayers or 0
    local ping = serverData.ping and string.format("%d ms", math.floor(serverData.ping)) or "N/A"
    local fps = serverData.fps and string.format("%.0f fps", serverData.fps) or "N/A"

    local Card = Instance.new("Frame")
    Card.Name = "ServerCard_" .. tostring(index)
    Card.Size = UDim2.new(1, 0, 0, 56)
    Card.BackgroundColor3 = isCurrent and Color3.fromRGB(28, 34, 46) or Color3.fromRGB(24, 27, 35)
    Card.BorderSizePixel = 0
    Card.LayoutOrder = index
    Card.Parent = ScrollContainer

    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 8)
    CardCorner.Parent = Card

    local CardStroke = Instance.new("UIStroke")
    CardStroke.Color = isCurrent and Color3.fromRGB(59, 130, 246) or (isBlacklisted and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(36, 40, 52))
    CardStroke.Thickness = 1
    CardStroke.Parent = Card

    -- Rank Badge
    local RankBadge = Instance.new("TextLabel")
    RankBadge.Size = UDim2.new(0, 28, 0, 22)
    RankBadge.Position = UDim2.new(0, 10, 0, 8)
    RankBadge.BackgroundColor3 = Color3.fromRGB(35, 41, 58)
    RankBadge.BorderSizePixel = 0
    RankBadge.Font = Enum.Font.GothamBold
    RankBadge.Text = "#" .. tostring(index)
    RankBadge.TextColor3 = Color3.fromRGB(96, 165, 250)
    RankBadge.TextSize = 11
    RankBadge.Parent = Card

    local RankCorner = Instance.new("UICorner")
    RankCorner.CornerRadius = UDim.new(0, 4)
    RankCorner.Parent = RankBadge

    -- Player Count Label
    local PlayerLabel = Instance.new("TextLabel")
    PlayerLabel.Size = UDim2.new(0, 160, 0, 22)
    PlayerLabel.Position = UDim2.new(0, 44, 0, 8)
    PlayerLabel.BackgroundTransparency = 1
    PlayerLabel.Font = Enum.Font.GothamBold
    PlayerLabel.Text = string.format("👥 %d / %d Pemain", playing, maxPlayers)
    PlayerLabel.TextColor3 = (playing <= 3) and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(245, 245, 245)
    PlayerLabel.TextSize = 13
    PlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
    PlayerLabel.Parent = Card

    -- Details (Ping, FPS, ID)
    local shortId = string.sub(serverData.id or "Unknown", 1, 8)
    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Size = UDim2.new(1, -210, 0, 18)
    InfoLabel.Position = UDim2.new(0, 10, 0, 32)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Font = Enum.Font.Gotham
    InfoLabel.Text = string.format("Ping: %s  •  FPS: %s  •  ID: %s...", ping, fps, shortId)
    InfoLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
    InfoLabel.TextSize = 11
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.Parent = Card

    -- Copy Button
    local CopyBtn = Instance.new("TextButton")
    CopyBtn.Name = "CopyBtn"
    CopyBtn.Size = UDim2.new(0, 64, 0, 30)
    CopyBtn.Position = UDim2.new(1, -156, 0, 13)
    CopyBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 56)
    CopyBtn.BorderSizePixel = 0
    CopyBtn.Font = Enum.Font.GothamMedium
    CopyBtn.Text = "📋 Copy"
    CopyBtn.TextColor3 = Color3.fromRGB(209, 213, 219)
    CopyBtn.TextSize = 11
    CopyBtn.Parent = Card

    local CopyCorner = Instance.new("UICorner")
    CopyCorner.CornerRadius = UDim.new(0, 6)
    CopyCorner.Parent = CopyBtn

    CopyBtn.MouseButton1Click:Connect(function()
        local copied = copyToClipboard(serverData.id)
        if copied then
            CopyBtn.Text = "✔ Disalin"
            CopyBtn.TextColor3 = Color3.fromRGB(52, 211, 153)
            task.delay(1.5, function()
                CopyBtn.Text = "📋 Copy"
                CopyBtn.TextColor3 = Color3.fromRGB(209, 213, 219)
            end)
        end
    end)

    -- Join Button
    local JoinBtn = Instance.new("TextButton")
    JoinBtn.Name = "JoinBtn"
    JoinBtn.Size = UDim2.new(0, 78, 0, 30)
    JoinBtn.Position = UDim2.new(1, -86, 0, 13)
    JoinBtn.BorderSizePixel = 0
    JoinBtn.Font = Enum.Font.GothamBold
    JoinBtn.TextSize = 12
    JoinBtn.Parent = Card

    local JoinCorner = Instance.new("UICorner")
    JoinCorner.CornerRadius = UDim.new(0, 6)
    JoinCorner.Parent = JoinBtn

    if isCurrent then
        JoinBtn.BackgroundColor3 = Color3.fromRGB(55, 65, 81)
        JoinBtn.Text = "Saat ini"
        JoinBtn.TextColor3 = Color3.fromRGB(156, 163, 175)
        JoinBtn.AutoButtonColor = false
    elseif isBlacklisted then
        JoinBtn.BackgroundColor3 = Color3.fromRGB(90, 35, 35)
        JoinBtn.Text = "Tutup"
        JoinBtn.TextColor3 = Color3.fromRGB(220, 120, 120)
    else
        JoinBtn.BackgroundColor3 = (playing <= 3) and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(37, 99, 235)
        JoinBtn.Text = "▶ JOIN"
        JoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

        JoinBtn.MouseButton1Click:Connect(function()
            if isHopping then return end
            JoinBtn.Text = "..."
            setStatus(string.format("Menghubungkan ke Server #%d (%d pemain)...", index, playing), Color3.fromRGB(245, 158, 11))
            notify("Server Finder", string.format("Menghubungkan ke server (%d pemain)...", playing), 3)

            setupQueueOnTeleport()

            local success, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(PlaceId, serverData.id, LocalPlayer)
            end)

            if not success then
                blacklistServers[serverData.id] = true
                JoinBtn.Text = "Gagal"
                JoinBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
                setStatus("Gagal masuk server: " .. tostring(err), Color3.fromRGB(239, 68, 68))
                notify("Gagal", "Server tidak dapat diakses!", 3)
                task.delay(2, function()
                    JoinBtn.Text = "▶ JOIN"
                    JoinBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
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
        local passMax = (not maxLimit) or ((srv.playing or 0) <= maxLimit)
        local passCurrent = (not excludeCurrentActive) or (srv.id ~= CurrentJobId)
        if passMax and passCurrent then
            table.insert(filtered, srv)
        end
    end

    -- Strict sort ascending: lowest players first; if equal, lower ping first
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
        EmptyLabel.Text = (isFetching and "Sedang memindai server Roblox..." or "Tidak ada server sepi yang cocok dengan filter.")
    else
        EmptyLabel.Visible = false
        for index, srv in ipairs(filtered) do
            createServerCard(srv, index)
        end
    end

    if not isHopping then
        setStatus(string.format("Ditemukan %d server sepi", #filtered), Color3.fromRGB(156, 163, 175))
    end
end

-- ========================================================================
-- FETCH SERVERS WITH 429 HANDLING & FALLBACK
-- ========================================================================

local function fetchRobloxServers(cursor)
    if isFetching then return end
    isFetching = true
    setStatus("Mengambil daftar server dari Roblox...", Color3.fromRGB(96, 165, 250))
    EmptyLabel.Text = "Sedang memindai server sepi..."
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
            setStatus("Gagal terhubung ke Roblox API.", Color3.fromRGB(239, 68, 68))
            EmptyLabel.Text = "Gagal mengambil server. Pastikan executor mendukung HTTP Request."
            return
        end

        local decodeSuccess, parsed = pcall(function()
            return HttpService:JSONDecode(body)
        end)

        if not decodeSuccess or not parsed or not parsed.data then
            setStatus("Respon server tidak valid.", Color3.fromRGB(239, 68, 68))
            EmptyLabel.Text = "Tidak dapat membaca format data dari Roblox API."
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
-- NO-GIMMICK AUTO-HOP WITH RESILIENT RETRY CHAIN
-- ========================================================================

stopHopping = function(reason)
    isHopping = false
    currentHopIndex = 1
    hopCandidates = {}
    AutoHopBtn.Text = "🚀 JOIN SERVER SEPI (AUTO)"
    AutoHopBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
    if reason then
        notify("Server Finder", reason, 4)
        setStatus(reason, Color3.fromRGB(239, 68, 68))
    end
end

executeHopAttempt = function()
    if not isHopping then return end

    -- Find next eligible server that is NOT blacklisted and NOT the current server
    while currentHopIndex <= #hopCandidates do
        local candidate = hopCandidates[currentHopIndex]
        if candidate and not blacklistServers[candidate.id] and candidate.id ~= CurrentJobId then
            break
        end
        currentHopIndex = currentHopIndex + 1
    end

    if currentHopIndex > #hopCandidates then
        stopHopping("Semua server sepi telah dicoba. Klik Refresh untuk memindai ulang.")
        return
    end

    local target = hopCandidates[currentHopIndex]
    local pCount = target.playing or 0
    local maxP = target.maxPlayers or 0

    local hopMsg = string.format("Mencoba Server #%d (%d/%d pemain)...", currentHopIndex, pCount, maxP)
    setStatus(hopMsg, Color3.fromRGB(245, 158, 11))
    notify("Auto Hop", hopMsg, 3)

    setupQueueOnTeleport()

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceId, target.id, LocalPlayer)
    end)

    if not success then
        blacklistServers[target.id] = true
        currentHopIndex = currentHopIndex + 1
        setStatus(string.format("Server #%d gagal. Mencoba server berikutnya...", currentHopIndex - 1), Color3.fromRGB(239, 68, 68))
        task.wait(1)
        executeHopAttempt()
    else
        -- Guard against hung connections (8-second watchdog)
        task.delay(8, function()
            if isHopping and currentHopIndex <= #hopCandidates and hopCandidates[currentHopIndex].id == target.id then
                setStatus("Teleport timeout. Mencoba server sepi lain...", Color3.fromRGB(245, 158, 11))
                blacklistServers[target.id] = true
                currentHopIndex = currentHopIndex + 1
                executeHopAttempt()
            end
        end)
    end
end

-- Teleport Failure Listener (Crucial for handling ghost / restricted servers)
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == LocalPlayer then
        local errStr = tostring(errorMessage or "Server tidak dapat diakses")
        if isHopping and currentHopIndex <= #hopCandidates then
            local failedServer = hopCandidates[currentHopIndex]
            if failedServer then
                blacklistServers[failedServer.id] = true
            end
            currentHopIndex = currentHopIndex + 1
            setStatus(string.format("Server tutup/penuh (%s). Beralih ke server lain...", errStr), Color3.fromRGB(239, 68, 68))
            notify("Pindah Server", "Server penuh/tutup. Mencoba server sepi lain...", 3)
            task.wait(0.5)
            executeHopAttempt()
        else
            setStatus("Teleport gagal: " .. errStr, Color3.fromRGB(239, 68, 68))
            notify("Teleport Gagal", errStr, 4)
        end
    end
end)

-- Start Auto Hop Sequence
local function startAutoHop()
    if isHopping then
        stopHopping("Auto Hop dibatalkan oleh pemain.")
        return
    end

    isHopping = true
    currentHopIndex = 1
    AutoHopBtn.Text = "🛑 BATALKAN AUTO HOP"
    AutoHopBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
    setStatus("Menyiapkan daftar server sepi...", Color3.fromRGB(16, 185, 129))

    -- Collect candidates from currently loaded servers
    local maxLimit = tonumber(MaxTextBox.Text)
    hopCandidates = {}

    for _, srv in ipairs(loadedServers) do
        local passMax = (not maxLimit) or ((srv.playing or 0) <= maxLimit)
        if srv.id ~= CurrentJobId and not blacklistServers[srv.id] and passMax and (srv.playing or 0) < (srv.maxPlayers or 999) then
            table.insert(hopCandidates, srv)
        end
    end

    -- Strict sort: lowest players first, lowest ping first
    table.sort(hopCandidates, function(a, b)
        local aP = a.playing or 0
        local bP = b.playing or 0
        if aP ~= bP then return aP < bP end
        return (a.ping or 9999) < (b.ping or 9999)
    end)

    if #hopCandidates > 0 then
        executeHopAttempt()
        return
    end

    -- If no candidates loaded yet, fetch directly from Roblox API
    task.spawn(function()
        setStatus("Mengambil server sepi langsung dari Roblox...", Color3.fromRGB(96, 165, 250))
        local url = string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100",
            tostring(PlaceId)
        )
        local body = httpRequest(url)
        if not body or not isHopping then
            if isHopping then stopHopping("Gagal mengambil server dari Roblox.") end
            return
        end

        local decodeSuccess, parsed = pcall(function()
            return HttpService:JSONDecode(body)
        end)

        if decodeSuccess and parsed and parsed.data and isHopping then
            for _, srv in ipairs(parsed.data) do
                local passMax = (not maxLimit) or ((srv.playing or 0) <= maxLimit)
                if srv.id ~= CurrentJobId and not blacklistServers[srv.id] and passMax and (srv.playing or 0) < (srv.maxPlayers or 999) then
                    table.insert(hopCandidates, srv)
                end
            end

            table.sort(hopCandidates, function(a, b)
                local aP = a.playing or 0
                local bP = b.playing or 0
                if aP ~= bP then return aP < bP end
                return (a.ping or 9999) < (b.ping or 9999)
            end)

            if #hopCandidates > 0 then
                executeHopAttempt()
            else
                stopHopping("Tidak ada server sepi yang tersedia saat ini.")
            end
        else
            if isHopping then stopHopping("Format respon Roblox tidak sesuai.") end
        end
    end)
end

-- ========================================================================
-- EVENT HOOKS
-- ========================================================================

AutoHopBtn.MouseButton1Click:Connect(function()
    startAutoHop()
end)

RefreshBtn.MouseButton1Click:Connect(function()
    if isHopping then
        stopHopping("Dihentikan karena refresh.")
    end
    fetchRobloxServers("")
end)

LoadMoreBtn.MouseButton1Click:Connect(function()
    if isFetching or isHopping then return end
    if nextPageCursor and nextPageCursor ~= "" then
        fetchRobloxServers(nextPageCursor)
    else
        setStatus("Halaman server sudah habis.", Color3.fromRGB(245, 158, 11))
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

print("[Server Finder] Siap digunakan! Tekan RightControl untuk buka/tutup menu.")
