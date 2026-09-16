--[[
    ========================================================================
    HORIZON REAL-TIME PLAYER COUNTER • HUD WIDGET
    ========================================================================
    Features:
    - 100% Real-Time Server Data directly from Roblox Players Service.
    - Instant event-driven updates on PlayerAdded & PlayerRemoving.
    - Compact, modern, draggable HUD pill (touch & mouse support).
    - Dynamic Solo Indicator:
      • Green Dot: Solo Server (1 Player - You are alone!)
      • Blue Dot: Low Population (2-4 Players)
      • Gray/Amber Dot: Standard Server (5+ Players)
    - Join/Leave Alerts: Notifies you immediately if someone enters your server!
    - Right Control keybind to toggle visibility.
    ========================================================================
--]]

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Prevent duplicate instances
if getgenv and getgenv().HorizonPlayerCounterInstance then
    pcall(function()
        getgenv().HorizonPlayerCounterInstance:Destroy()
    end)
    getgenv().HorizonPlayerCounterInstance = nil
end

-- ========================================================================
-- UTILITIES & CONTAINER RESOLUTION
-- ========================================================================

local function tween(object, properties, duration, style, direction)
    style = style or Enum.EasingStyle.Quad
    direction = direction or Enum.EasingDirection.Out
    duration = duration or 0.16
    local t = TweenService:Create(object, TweenInfo.new(duration, style, direction), properties)
    t:Play()
    return t
end

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

local function notify(title, message, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Player Alert",
            Text = message or "",
            Duration = duration or 3
        })
    end)
end

-- Smooth Draggable Handler (Mouse + Touch Screen)
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

-- ========================================================================
-- USER INTERFACE (COMPACT MODERN HUD PILL)
-- ========================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HorizonPlayerCounterGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 1000
ScreenGui.Parent = getGuiContainer()

if getgenv then
    getgenv().HorizonPlayerCounterInstance = ScreenGui
end

-- Main Draggable Pill Frame
local PillFrame = Instance.new("Frame")
PillFrame.Name = "PillFrame"
PillFrame.Size = UDim2.new(0, 160, 0, 36)
PillFrame.Position = UDim2.new(0.5, -80, 0, 18) -- Centered near top of screen
PillFrame.BackgroundColor3 = Color3.fromRGB(14, 16, 23)
PillFrame.BorderSizePixel = 0
PillFrame.ClipsDescendants = true
PillFrame.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 18)
PillCorner.Parent = PillFrame

local PillStroke = Instance.new("UIStroke")
PillStroke.Color = Color3.fromRGB(38, 42, 58)
PillStroke.Thickness = 1.2
PillStroke.Parent = PillFrame

-- Status Indicator Dot (Glows based on player count)
local StatusDot = Instance.new("Frame")
StatusDot.Name = "StatusDot"
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(0, 14, 0.5, -4)
StatusDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
StatusDot.BorderSizePixel = 0
StatusDot.Parent = PillFrame

local DotCorner = Instance.new("UICorner")
DotCorner.CornerRadius = UDim.new(1, 0)
DotCorner.Parent = StatusDot

-- Player Count Label
local CountLabel = Instance.new("TextLabel")
CountLabel.Name = "CountLabel"
CountLabel.Size = UDim2.new(1, -56, 1, 0)
CountLabel.Position = UDim2.new(0, 28, 0, 0)
CountLabel.BackgroundTransparency = 1
CountLabel.Font = Enum.Font.GothamBold
CountLabel.Text = "1 Player (Solo)"
CountLabel.TextColor3 = Color3.fromRGB(240, 244, 255)
CountLabel.TextSize = 12
CountLabel.TextXAlignment = Enum.TextXAlignment.Left
CountLabel.Parent = PillFrame

-- Mini Close / Toggle Button
local MiniCloseBtn = Instance.new("TextButton")
MiniCloseBtn.Name = "MiniCloseBtn"
MiniCloseBtn.Size = UDim2.new(0, 22, 0, 22)
MiniCloseBtn.Position = UDim2.new(1, -28, 0.5, -11)
MiniCloseBtn.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
MiniCloseBtn.BorderSizePixel = 0
MiniCloseBtn.Font = Enum.Font.GothamBold
MiniCloseBtn.Text = "×"
MiniCloseBtn.TextColor3 = Color3.fromRGB(150, 156, 175)
MiniCloseBtn.TextSize = 14
MiniCloseBtn.Parent = PillFrame

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(1, 0)
CloseCorner.Parent = MiniCloseBtn

MiniCloseBtn.MouseEnter:Connect(function()
    tween(MiniCloseBtn, { TextColor3 = Color3.fromRGB(248, 113, 113), BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
end)
MiniCloseBtn.MouseLeave:Connect(function()
    tween(MiniCloseBtn, { TextColor3 = Color3.fromRGB(150, 156, 175), BackgroundColor3 = Color3.fromRGB(24, 27, 38) })
end)

-- Make the entire pill draggable
makeDraggable(PillFrame, PillFrame)

-- Floating Restore Pill (When closed/minimized)
local RestorePill = Instance.new("TextButton")
RestorePill.Name = "RestorePill"
RestorePill.Size = UDim2.new(0, 42, 0, 42)
RestorePill.Position = UDim2.new(0, 20, 0, 140)
RestorePill.BackgroundColor3 = Color3.fromRGB(14, 16, 23)
RestorePill.BorderSizePixel = 0
RestorePill.Font = Enum.Font.GothamBold
RestorePill.Text = "👥"
RestorePill.TextSize = 16
RestorePill.Visible = false
RestorePill.Parent = ScreenGui

local RestoreCorner = Instance.new("UICorner")
RestoreCorner.CornerRadius = UDim.new(1, 0)
RestoreCorner.Parent = RestorePill

local RestoreStroke = Instance.new("UIStroke")
RestoreStroke.Color = Color3.fromRGB(52, 211, 153)
RestoreStroke.Thickness = 1.2
RestoreStroke.Parent = RestorePill

makeDraggable(RestorePill, RestorePill)

local function toggleVisibility(visible)
    if visible == nil then
        PillFrame.Visible = not PillFrame.Visible
    else
        PillFrame.Visible = visible
    end
    RestorePill.Visible = not PillFrame.Visible
end

MiniCloseBtn.MouseButton1Click:Connect(function()
    toggleVisibility(false)
end)

RestorePill.MouseButton1Click:Connect(function()
    toggleVisibility(true)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightControl then
        toggleVisibility()
    end
end)

-- ========================================================================
-- REAL-TIME DATA LOGIC & DYNAMIC STYLING
-- ========================================================================

local function updateRealTimeCount()
    local playerList = Players:GetPlayers()
    local count = #playerList
    local maxPlayers = Players.MaxPlayers or 12

    if count <= 1 then
        -- Solo Server
        CountLabel.Text = string.format("1 / %d (Solo)", maxPlayers)
        CountLabel.TextColor3 = Color3.fromRGB(192, 132, 252)
        StatusDot.BackgroundColor3 = Color3.fromRGB(192, 132, 252)
        PillStroke.Color = Color3.fromRGB(124, 58, 237)
        RestoreStroke.Color = Color3.fromRGB(124, 58, 237)
    elseif count <= 4 then
        -- Small Server
        CountLabel.Text = string.format("%d / %d Players", count, maxPlayers)
        CountLabel.TextColor3 = Color3.fromRGB(52, 211, 153)
        StatusDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
        PillStroke.Color = Color3.fromRGB(16, 185, 129)
        RestoreStroke.Color = Color3.fromRGB(16, 185, 129)
    else
        -- Standard / Crowded Server
        CountLabel.Text = string.format("%d / %d Players", count, maxPlayers)
        CountLabel.TextColor3 = Color3.fromRGB(240, 244, 255)
        StatusDot.BackgroundColor3 = Color3.fromRGB(251, 191, 36)
        PillStroke.Color = Color3.fromRGB(50, 56, 76)
        RestoreStroke.Color = Color3.fromRGB(50, 56, 76)
    end
end

-- Instant event listeners
Players.PlayerAdded:Connect(function(player)
    updateRealTimeCount()
    if player ~= LocalPlayer then
        notify("Player Joined", string.format("%s joined the server! (Total: %d)", player.DisplayName or player.Name, #Players:GetPlayers()), 4)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    -- Allow short tick for player list to update internally
    task.defer(function()
        updateRealTimeCount()
    end)
    if player ~= LocalPlayer then
        notify("Player Left", string.format("%s left the server. (Total: %d)", player.DisplayName or player.Name, math.max(0, #Players:GetPlayers() - 1)), 3)
    end
end)

-- Initial update
updateRealTimeCount()

-- 1-second fallback poll to ensure 100% sync
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(1)
        updateRealTimeCount()
    end
end)

print("[Player Counter] Real-time HUD loaded. Drag anywhere to move.")
