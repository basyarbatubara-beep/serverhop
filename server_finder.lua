--[[
  ========================================================================
   ROBLOX SERVER FINDER & AUTO-JOINER
  ========================================================================
  Author: Assistant
  Purpose: Finds the smallest public servers for the current game and
       allows 1-click teleporting to any selected server.
  Compatibility: Synapse X, Delta, Codex, Krnl, Fluxus, Solara, Wave,
          Arceus X, Hydrogen, and all standard Luau executors.
  Toggle Key: Right Control (or tap the floating toggle button on Mobile)
  ========================================================================
--]]

-- Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlaceId = game.PlaceId
local CurrentJobId = game.JobId

-- Wait for PlayerGui
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Prevent duplicate script instances
if getgenv and getgenv().ServerFinderGuiInstance then
  pcall(function()
    getgenv().ServerFinderGuiInstance:Destroy()
  end)
  getgenv().ServerFinderGuiInstance = nil
end

-- Resolve GUI Container (supports gethui, CoreGui, or PlayerGui)
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

-- Safe URL Encode Helper
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

-- Universal HTTP Request Helper (Compatible with all executors)
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
  elseif typeof(http) == "table" and typeof(http.request) == "function" then
    requestFunc = http.request
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
    if success and response then
      local statusCode = response.StatusCode or response.Status or response.status or response.statusCode or 200
      if statusCode == 429 then
        return nil, "Rate limited by Roblox (Too Many Requests). Please wait a few seconds."
      end
      local body = response.Body or response.body or response.data or response.Response
      if body then
        return body
      end
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

  return nil, "HTTP request failed. Please check executor capabilities."
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

-- Make GUI Draggable (Supports Mouse and Touch for Mobile)
-- Smooth Draggable Window (No slipping or dropping on fast movement)
local function makeDraggable(dragHandle, targetFrame)
  local dragging = false
  local dragStart = nil
  local startPos = nil

  dragHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = true
      dragStart = input.Position
      startPos = targetFrame.Position
    end
  end)

  UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
      local delta = input.Position - dragStart
      targetFrame.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
      )
    end
  end)

  UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = false
    end
  end)
end

-- Fetch Game Name
local gameTitle = "Game: " .. tostring(PlaceId)
task.spawn(function()
  local success, productInfo = pcall(function()
    return MarketplaceService:GetProductInfo(PlaceId)
  end)
  if success and productInfo and productInfo.Name then
    gameTitle = productInfo.Name
  end
end)

-- ========================================================================
-- BUILD USER INTERFACE
-- ========================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RobloxServerFinder"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = getGuiContainer()

if getgenv then
  getgenv().ServerFinderGuiInstance = ScreenGui
end

-- Main Window Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 480)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -240)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(45, 50, 64)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame

-- Top Bar (Header & Drag Handle)
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 46)
TopBar.BackgroundColor3 = Color3.fromRGB(27, 30, 39)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopBarCorner = Instance.new("UICorner")
TopBarCorner.CornerRadius = UDim.new(0, 10)
TopBarCorner.Parent = TopBar

local TopBarBottomFix = Instance.new("Frame")
TopBarBottomFix.Size = UDim2.new(1, 0, 0, 10)
TopBarBottomFix.Position = UDim2.new(0, 0, 1, -10)
TopBarBottomFix.BackgroundColor3 = Color3.fromRGB(27, 30, 39)
TopBarBottomFix.BorderSizePixel = 0
TopBarBottomFix.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(1, -100, 0, 24)
TitleLabel.Position = UDim2.new(0, 14, 0, 4)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "Server Finder"
TitleLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
TitleLabel.TextSize = 15
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Name = "SubtitleLabel"
SubtitleLabel.Size = UDim2.new(1, -100, 0, 16)
SubtitleLabel.Position = UDim2.new(0, 14, 0, 26)
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Font = Enum.Font.Gotham
SubtitleLabel.Text = "Loading game details..."
SubtitleLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
SubtitleLabel.TextSize = 11
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.Parent = TopBar

task.spawn(function()
  task.wait(0.5)
  local curCount = #Players:GetPlayers()
  SubtitleLabel.Text = string.format("%s | Current: %d players", gameTitle, curCount)
end)

-- Window Control Buttons (Minimize & Close)
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -38, 0, 8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseBtn.TextSize = 13
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TopBar

local CloseBtnCorner = Instance.new("UICorner")
CloseBtnCorner.CornerRadius = UDim.new(0, 6)
CloseBtnCorner.Parent = CloseBtn

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Name = "MinimizeBtn"
MinimizeBtn.Size = UDim2.new(0, 30, 0, 30)
MinimizeBtn.Position = UDim2.new(1, -74, 0, 8)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
MinimizeBtn.TextSize = 13
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Parent = TopBar

local MinimizeBtnCorner = Instance.new("UICorner")
MinimizeBtnCorner.CornerRadius = UDim.new(0, 6)
MinimizeBtnCorner.Parent = MinimizeBtn

makeDraggable(TopBar, MainFrame)

-- Floating Toggle Pill (Mobile & Minimize fallback)
local TogglePill = Instance.new("TextButton")
TogglePill.Name = "TogglePill"
TogglePill.Size = UDim2.new(0, 140, 0, 36)
TogglePill.Position = UDim2.new(0, 20, 0, 80)
TogglePill.BackgroundColor3 = Color3.fromRGB(27, 30, 39)
TogglePill.BorderSizePixel = 0
TogglePill.Font = Enum.Font.GothamBold
TogglePill.Text = "Server Finder"
TogglePill.TextColor3 = Color3.fromRGB(255, 255, 255)
TogglePill.TextSize = 13
TogglePill.Visible = false
TogglePill.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 18)
PillCorner.Parent = TogglePill

local PillStroke = Instance.new("UIStroke")
PillStroke.Color = Color3.fromRGB(59, 130, 246)
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

-- Keybind toggle (RightControl)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
  if not gameProcessed and input.KeyCode == Enum.KeyCode.RightControl then
    toggleMainWindow()
  end
end)

-- Action Bar (Quick Join, Refresh, Load More)
local ActionBar = Instance.new("Frame")
ActionBar.Name = "ActionBar"
ActionBar.Size = UDim2.new(1, -24, 0, 38)
ActionBar.Position = UDim2.new(0, 12, 0, 54)
ActionBar.BackgroundTransparency = 1
ActionBar.Parent = MainFrame

-- Quick Join Smallest Button
local QuickJoinBtn = Instance.new("TextButton")
QuickJoinBtn.Name = "QuickJoinBtn"
QuickJoinBtn.Size = UDim2.new(0.48, -4, 1, 0)
QuickJoinBtn.Position = UDim2.new(0, 0, 0, 0)
QuickJoinBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
QuickJoinBtn.BorderSizePixel = 0
QuickJoinBtn.Font = Enum.Font.GothamBold
QuickJoinBtn.Text = "Quick Join Smallest"
QuickJoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
QuickJoinBtn.TextSize = 13
QuickJoinBtn.Parent = ActionBar

local QuickJoinCorner = Instance.new("UICorner")
QuickJoinCorner.CornerRadius = UDim.new(0, 8)
QuickJoinCorner.Parent = QuickJoinBtn

-- Refresh Button
local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Name = "RefreshBtn"
RefreshBtn.Size = UDim2.new(0.26, -4, 1, 0)
RefreshBtn.Position = UDim2.new(0.48, 4, 0, 0)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
RefreshBtn.BorderSizePixel = 0
RefreshBtn.Font = Enum.Font.GothamMedium
RefreshBtn.Text = "Refresh"
RefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RefreshBtn.TextSize = 13
RefreshBtn.Parent = ActionBar

local RefreshCorner = Instance.new("UICorner")
RefreshCorner.CornerRadius = UDim.new(0, 8)
RefreshCorner.Parent = RefreshBtn

-- Load More Button
local LoadMoreBtn = Instance.new("TextButton")
LoadMoreBtn.Name = "LoadMoreBtn"
LoadMoreBtn.Size = UDim2.new(0.26, -4, 1, 0)
LoadMoreBtn.Position = UDim2.new(0.74, 4, 0, 0)
LoadMoreBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
LoadMoreBtn.BorderSizePixel = 0
LoadMoreBtn.Font = Enum.Font.GothamMedium
LoadMoreBtn.Text = "Load More"
LoadMoreBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
LoadMoreBtn.TextSize = 12
LoadMoreBtn.Parent = ActionBar

local LoadMoreCorner = Instance.new("UICorner")
LoadMoreCorner.CornerRadius = UDim.new(0, 8)
LoadMoreCorner.Parent = LoadMoreBtn

-- Filter & Status Bar
local FilterBar = Instance.new("Frame")
FilterBar.Name = "FilterBar"
FilterBar.Size = UDim2.new(1, -24, 0, 30)
FilterBar.Position = UDim2.new(0, 12, 0, 98)
FilterBar.BackgroundTransparency = 1
FilterBar.Parent = MainFrame

local MaxLabel = Instance.new("TextLabel")
MaxLabel.Name = "MaxLabel"
MaxLabel.Size = UDim2.new(0, 85, 1, 0)
MaxLabel.Position = UDim2.new(0, 0, 0, 0)
MaxLabel.BackgroundTransparency = 1
MaxLabel.Font = Enum.Font.Gotham
MaxLabel.Text = "Max Players:"
MaxLabel.TextColor3 = Color3.fromRGB(180, 185, 195)
MaxLabel.TextSize = 12
MaxLabel.TextXAlignment = Enum.TextXAlignment.Left
MaxLabel.Parent = FilterBar

local MaxTextBox = Instance.new("TextBox")
MaxTextBox.Name = "MaxTextBox"
MaxTextBox.Size = UDim2.new(0, 50, 0, 26)
MaxTextBox.Position = UDim2.new(0, 88, 0, 2)
MaxTextBox.BackgroundColor3 = Color3.fromRGB(28, 31, 41)
MaxTextBox.BorderSizePixel = 0
MaxTextBox.Font = Enum.Font.GothamMedium
MaxTextBox.PlaceholderText = "All"
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

-- Exclude Current Server Button
local ExcludeCurrentBtn = Instance.new("TextButton")
ExcludeCurrentBtn.Name = "ExcludeCurrentBtn"
ExcludeCurrentBtn.Size = UDim2.new(0, 135, 0, 26)
ExcludeCurrentBtn.Position = UDim2.new(0, 146, 0, 2)
ExcludeCurrentBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 41)
ExcludeCurrentBtn.BorderSizePixel = 0
ExcludeCurrentBtn.Font = Enum.Font.Gotham
ExcludeCurrentBtn.Text = "Hide Current"
ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(96, 165, 250)
ExcludeCurrentBtn.TextSize = 11
ExcludeCurrentBtn.Parent = FilterBar

local ExcludeCorner = Instance.new("UICorner")
ExcludeCorner.CornerRadius = UDim.new(0, 6)
ExcludeCorner.Parent = ExcludeCurrentBtn

local ExcludeStroke = Instance.new("UIStroke")
ExcludeStroke.Color = Color3.fromRGB(45, 50, 65)
ExcludeStroke.Thickness = 1
ExcludeStroke.Parent = ExcludeCurrentBtn

local excludeCurrentActive = true

-- Forward declaration of renderServerList
local renderServerList = nil

ExcludeCurrentBtn.MouseButton1Click:Connect(function()
  excludeCurrentActive = not excludeCurrentActive
  if excludeCurrentActive then
    ExcludeCurrentBtn.Text = "Hide Current"
    ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(96, 165, 250)
  else
    ExcludeCurrentBtn.Text = "X Show Current"
    ExcludeCurrentBtn.TextColor3 = Color3.fromRGB(156, 163, 175)
  end
  if renderServerList then
    renderServerList()
  end
end)

-- Status Label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.Size = UDim2.new(1, -290, 1, 0)
StatusLabel.Position = UDim2.new(0, 290, 0, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Ready to search"
StatusLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
StatusLabel.Parent = FilterBar

-- Server List Container
local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, -24, 1, -142)
ScrollContainer.Position = UDim2.new(0, 12, 0, 134)
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

-- Empty State Label
local EmptyLabel = Instance.new("TextLabel")
EmptyLabel.Name = "EmptyLabel"
EmptyLabel.Size = UDim2.new(1, 0, 0, 100)
EmptyLabel.BackgroundTransparency = 1
EmptyLabel.Font = Enum.Font.GothamMedium
EmptyLabel.Text = "Press 'Refresh' or 'Quick Join' to scan for small servers."
EmptyLabel.TextColor3 = Color3.fromRGB(120, 125, 140)
EmptyLabel.TextSize = 13
EmptyLabel.Visible = true
EmptyLabel.Parent = ScrollContainer

-- ========================================================================
-- LOGIC & SERVER DISCOVERY
-- ========================================================================

local loadedServers = {}
local nextPageCursor = ""
local isFetching = false
local isTeleporting = false
local currentAttemptServerId = nil
local failedServerIds = {}

local function setStatus(text, color)
    StatusLabel.Text = text
    StatusLabel.TextColor3 = color or Color3.fromRGB(156, 163, 175)
end

-- Teleport Handler with Debounce, Timeout, and Status Feedback
local function teleportToServer(serverId, serverPlayerCount, isAutoRetry)
    if isTeleporting and not isAutoRetry then
        setStatus("Teleport already in progress...", Color3.fromRGB(245, 158, 11))
        return
    end

    if failedServerIds[serverId] then
        setStatus("Skipping known full or closed server...", Color3.fromRGB(245, 158, 11))
        return
    end

    isTeleporting = true
    currentAttemptServerId = serverId
    setStatus(string.format("Teleporting to server (%d players)...", serverPlayerCount or 0), Color3.fromRGB(245, 158, 11))
    
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceId, serverId, LocalPlayer)
    end)
    
    if not success then
        isTeleporting = false
        currentAttemptServerId = nil
        setStatus("Teleport failed: " .. tostring(err), Color3.fromRGB(239, 68, 68))
    else
        -- Timeout protection: If Roblox teleport hangs, reset debounce after 15 seconds
        task.delay(15, function()
            if isTeleporting and currentAttemptServerId == serverId then
                isTeleporting = false
                currentAttemptServerId = nil
                setStatus("Teleport timed out. You may try another server.", Color3.fromRGB(245, 158, 11))
            end
        end)
    end
end

-- Teleport Failure Listener with Smart Auto-Retry
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == LocalPlayer then
        local failedId = currentAttemptServerId
        isTeleporting = false
        currentAttemptServerId = nil

        if failedId then
            failedServerIds[failedId] = true
        end

        local errorMsg = tostring(errorMessage or teleportResult or "Teleport failed")
        setStatus("Join failed: " .. errorMsg, Color3.fromRGB(239, 68, 68))

        -- Update UI to mark failed server
        if renderServerList then
            renderServerList()
        end

        -- Auto-retry next available smallest server
        task.delay(1.5, function()
            local nextCandidate = nil
            for _, srv in ipairs(loadedServers) do
                if srv.id ~= CurrentJobId and not failedServerIds[srv.id] and (srv.playing or 0) < (srv.maxPlayers or 999) then
                    if not nextCandidate or (srv.playing or 0) < (nextCandidate.playing or 0) then
                        nextCandidate = srv
                    end
                end
            end

            if nextCandidate then
                setStatus(string.format("Auto-retrying next smallest server (%d players)...", nextCandidate.playing or 0), Color3.fromRGB(96, 165, 250))
                teleportToServer(nextCandidate.id, nextCandidate.playing, true)
            else
                setStatus("Selected server unavailable. Please refresh.", Color3.fromRGB(239, 68, 68))
            end
        end)
    end
end)

-- Create a Server Row Item
local function createServerCard(serverData, index)
    local isCurrent = (serverData.id == CurrentJobId)
    local isFailed = (failedServerIds[serverData.id] == true)
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
    CardStroke.Color = isCurrent and Color3.fromRGB(59, 130, 246) or (isFailed and Color3.fromRGB(239, 68, 68) or Color3.fromRGB(36, 40, 52))
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
    PlayerLabel.Text = string.format("%d / %d Players", playing, maxPlayers)
    PlayerLabel.TextColor3 = (playing <= 3) and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(245, 245, 245)
    PlayerLabel.TextSize = 13
    PlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
    PlayerLabel.Parent = Card

    -- Details Sublabel (Ping, FPS, ID snippet)
    local shortId = string.sub(serverData.id or "Unknown", 1, 8)
    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Size = UDim2.new(1, -210, 0, 18)
    InfoLabel.Position = UDim2.new(0, 10, 0, 32)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Font = Enum.Font.Gotham
    InfoLabel.Text = string.format("Ping: %s | FPS: %s | ID: %s...", ping, fps, shortId)
    InfoLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
    InfoLabel.TextSize = 11
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.Parent = Card

    -- Copy JobId Button
    local CopyBtn = Instance.new("TextButton")
    CopyBtn.Name = "CopyBtn"
    CopyBtn.Size = UDim2.new(0, 68, 0, 30)
    CopyBtn.Position = UDim2.new(1, -162, 0, 13)
    CopyBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 56)
    CopyBtn.BorderSizePixel = 0
    CopyBtn.Font = Enum.Font.GothamMedium
    CopyBtn.Text = "Copy"
    CopyBtn.TextColor3 = Color3.fromRGB(209, 213, 219)
    CopyBtn.TextSize = 11
    CopyBtn.Parent = Card

    local CopyCorner = Instance.new("UICorner")
    CopyCorner.CornerRadius = UDim.new(0, 6)
    CopyCorner.Parent = CopyBtn

    CopyBtn.MouseButton1Click:Connect(function()
        local copied = copyToClipboard(serverData.id)
        if copied then
            CopyBtn.Text = "Copied!"
            CopyBtn.TextColor3 = Color3.fromRGB(52, 211, 153)
            task.delay(1.5, function()
                CopyBtn.Text = "Copy"
                CopyBtn.TextColor3 = Color3.fromRGB(209, 213, 219)
            end)
        else
            CopyBtn.Text = "Error"
        end
    end)

    -- Join Button
    local JoinBtn = Instance.new("TextButton")
    JoinBtn.Name = "JoinBtn"
    JoinBtn.Size = UDim2.new(0, 80, 0, 30)
    JoinBtn.Position = UDim2.new(1, -88, 0, 13)
    JoinBtn.BorderSizePixel = 0
    JoinBtn.Font = Enum.Font.GothamBold
    JoinBtn.TextSize = 12
    JoinBtn.Parent = Card

    local JoinCorner = Instance.new("UICorner")
    JoinCorner.CornerRadius = UDim.new(0, 6)
    JoinCorner.Parent = JoinBtn

    if isCurrent then
        JoinBtn.BackgroundColor3 = Color3.fromRGB(55, 65, 81)
        JoinBtn.Text = "Current"
        JoinBtn.TextColor3 = Color3.fromRGB(156, 163, 175)
        JoinBtn.AutoButtonColor = false
    elseif isFailed then
        JoinBtn.BackgroundColor3 = Color3.fromRGB(75, 40, 40)
        JoinBtn.Text = "Unavailable"
        JoinBtn.TextColor3 = Color3.fromRGB(200, 140, 140)
        JoinBtn.AutoButtonColor = false
    else
        JoinBtn.BackgroundColor3 = (playing <= 3) and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(37, 99, 235)
        JoinBtn.Text = "Join"
        JoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

        JoinBtn.MouseButton1Click:Connect(function()
            if isTeleporting then return end
            JoinBtn.Text = "Joining..."
            teleportToServer(serverData.id, playing)
        end)
    end

    return Card
end

renderServerList = function()
  -- Clear previous cards
  for _, child in ipairs(ScrollContainer:GetChildren()) do
    if child:IsA("Frame") and child.Name:sub(1, 11) == "ServerCard_" then
      child:Destroy()
    end
  end

  local maxThreshold = tonumber(MaxTextBox.Text)
  local filtered = {}

  for _, srv in ipairs(loadedServers) do
    local passMax = (not maxThreshold) or ((srv.playing or 0) <= maxThreshold)
    local passCurrent = (not excludeCurrentActive) or (srv.id ~= CurrentJobId)
    if passMax and passCurrent then
      table.insert(filtered, srv)
    end
  end

  -- Strict sort ascending by player count
  table.sort(filtered, function(a, b)
    return (a.playing or 0) < (b.playing or 0)
  end)

  if #filtered == 0 then
    EmptyLabel.Visible = true
    EmptyLabel.Text = (isFetching and "Scanning Roblox servers..." or "No servers match your current filters.")
  else
    EmptyLabel.Visible = false
    for index, srv in ipairs(filtered) do
      createServerCard(srv, index)
    end
  end

  setStatus(string.format("Showing %d small servers", #filtered), Color3.fromRGB(156, 163, 175))
end

-- Fetch Servers from Roblox API
local function queryServers(cursor)
  if isFetching then return end
  isFetching = true
  setStatus("Fetching servers from Roblox...", Color3.fromRGB(96, 165, 250))
  EmptyLabel.Text = "Scanning Roblox servers..."
  EmptyLabel.Visible = true

  task.spawn(function()
    local cursorParam = (cursor and cursor ~= "") and ("&cursor=" .. safeUrlEncode(cursor)) or ""
    local url = string.format(
      "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s",
      tostring(PlaceId),
      cursorParam
    )

    local body, reqErr = httpRequest(url)
    isFetching = false

    if not body then
      setStatus("Request failed. Check executor.", Color3.fromRGB(239, 68, 68))
      EmptyLabel.Text = "Failed to fetch servers. Ensure your executor supports HTTP requests."
      return
    end

    local decodeSuccess, parsed = pcall(function()
      return HttpService:JSONDecode(body)
    end)

    if not decodeSuccess or not parsed or not parsed.data then
      setStatus("Failed to parse server data.", Color3.fromRGB(239, 68, 68))
      EmptyLabel.Text = "Could not parse JSON response from Roblox API."
      return
    end

    nextPageCursor = parsed.nextPageCursor or ""

    if not cursor or cursor == "" then
      loadedServers = {}
    end

    for _, srv in ipairs(parsed.data) do
      -- Avoid duplicate server entries
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

-- Re-filter when MaxTextBox text changes
MaxTextBox:GetPropertyChangedSignal("Text"):Connect(function()
  renderServerList()
end)

-- Button Listeners
RefreshBtn.MouseButton1Click:Connect(function()
  queryServers("")
end)

LoadMoreBtn.MouseButton1Click:Connect(function()
  if isFetching then return end
  if nextPageCursor and nextPageCursor ~= "" then
    queryServers(nextPageCursor)
  else
    setStatus("No more server pages available.", Color3.fromRGB(245, 158, 11))
  end
end)

-- Quick Join Smallest Server Algorithm
QuickJoinBtn.MouseButton1Click:Connect(function()
    if isFetching or isTeleporting then return end
    setStatus("Finding smallest available server...", Color3.fromRGB(16, 185, 129))
    
    -- Check if we already have a suitable server loaded
    local candidate = nil
    for _, srv in ipairs(loadedServers) do
        if srv.id ~= CurrentJobId and not failedServerIds[srv.id] and (srv.playing or 0) < (srv.maxPlayers or 999) then
            if not candidate or (srv.playing or 0) < (candidate.playing or 0) then
                candidate = srv
            end
        end
    end

    if candidate then
        teleportToServer(candidate.id, candidate.playing)
        return
    end

    -- If not loaded yet, fetch directly
    isFetching = true
    task.spawn(function()
        local url = string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100",
            tostring(PlaceId)
        )
        local body, reqErr = httpRequest(url)
        isFetching = false

        if not body then
            setStatus("Quick Join failed: " .. tostring(reqErr or "Network error"), Color3.fromRGB(239, 68, 68))
            return
        end

        local decodeSuccess, parsed = pcall(function()
            return HttpService:JSONDecode(body)
        end)

        if decodeSuccess and parsed and parsed.data then
            local bestServer = nil
            for _, srv in ipairs(parsed.data) do
                if srv.id ~= CurrentJobId and not failedServerIds[srv.id] and (srv.playing or 0) < (srv.maxPlayers or 999) then
                    bestServer = srv
                    break
                end
            end

            if bestServer then
                teleportToServer(bestServer.id, bestServer.playing)
            else
                setStatus("No small servers found to join.", Color3.fromRGB(245, 158, 11))
            end
        else
            setStatus("Quick Join: Error reading server list.", Color3.fromRGB(239, 68, 68))
        end
    end)
end)

-- Initial Auto-Search on Launch
task.spawn(function()
  task.wait(0.2)
  queryServers("")
end)

print("[Server Finder] Initialized successfully. Press RightControl to toggle GUI.")
