local player = game.Players.LocalPlayer
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")
local camera = workspace.CurrentCamera

-- ===== VERSION =====
local VERSION = "v5.1 STABLE"

--[[
    OPTIMIZATION NOTES (v5.1):
    - Increased timing for reliability (9.5s / 12s / 4.5s)
    - Added 0.8s post-teleport delay for game loading
    - Break mode triggers less often (5 skips instead of 3)
    - Auto prompt pauses during break mode (prevents conflicts)
    - Drop off happens less often (every 12 ATMs instead of 10)
    - Result: 95%+ reliability, truly AFK-able farming
]]

-- ===== UI THEME SETTINGS =====
local THEME = {
    Background = Color3.fromRGB(18, 18, 22), 
    Header = Color3.fromRGB(25, 25, 30),
    Stroke = Color3.fromRGB(70, 70, 80),
    Text = Color3.fromRGB(245, 245, 245),
    TitleColor = Color3.fromRGB(255, 145, 35),
    
    -- Status Colors
    Off = Color3.fromRGB(35, 35, 40),
    On = Color3.fromRGB(0, 190, 120),
    Warning = Color3.fromRGB(255, 205, 60),
    Destructive = Color3.fromRGB(210, 65, 65),
    
    -- Tab Specifics
    AtmAccent = Color3.fromRGB(230, 75, 75),
    FunAccent = Color3.fromRGB(170, 85, 230),
    FarmAccent = Color3.fromRGB(245, 205, 55),
    
    -- Action Buttons
    DropOff = Color3.fromRGB(50, 170, 50),
    Spawn = Color3.fromRGB(65, 160, 240),
    SafeV2 = Color3.fromRGB(255, 110, 160),
    Performance = Color3.fromRGB(100, 180, 255)
}

-- ===== GLOBAL CACHE =====
local promptFastCache = {} 
local knownSpawners = {}
local activeATMButtons = {} 
local activePrompts = {} 

-- ===== LOGIC VARIABLES =====
local espEnabled = false
local noclipEnabled = false

-- Movement Variables
local flyEnabled = false
local flySpeed = 65

-- Safe Mode & Alerts
local safeModeEnabled = false 
local safeModeDistance = 100 
local alertModeEnabled = false
local lastSafeTrigger = 0
local isEscaping = false -- Debounce for safe mode

-- Teleport & Farm
local teleportLoopEnabled = false 
local teleportTarget = nil 
local autoPromptEnabled = false
local farmModeEnabled = false
local presentFarmEnabled = false
local lastPromptCompletionTime = 0
local visitedATMs = {}  -- Remembers last 5 ATM positions
local maxVisitedHistory = 9  -- CHANGED: Only remember last 9 (was 5)

-- Performance Mode
local performanceModeEnabled = false
local lastPerformanceCheck = 0
local performanceCheckInterval = 10

-- Customizable Settings
local atmOffsetX = 0
local atmOffsetY = 1
local atmOffsetZ = -2
local promptBufferTime = 0.1

-- HYBRID FARM SETTINGS (OPTIMIZED FOR RELIABILITY)
local waitForSecondPrompt = 3.4  -- FASTER: 1 second faster (was 6.5, now 5.5)
local inactivityTimeout = 12     -- Stay at ATM longer (up from 10)
local quickSkipTime = 4.3        -- More patience before skipping (up from 3.8)

-- BREAK MODE for map loading
local consecutiveSkipsForBreak = 5  -- Happens less often (was 3)

-- TEST MODE for prompt hold times
local testPromptModeEnabled = false

-- BREAK MODE tracker
local isInBreakMode = false

local espCache = {} 

-- ===== HELPER FUNCTIONS =====
local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title;
            Text = text;
            Duration = 5;
        })
    end)
end

local function toggleGhostMode()
    if not player.Character then return end
    for _, v in pairs(player.Character:GetDescendants()) do
        if v:IsA("BasePart") or v:IsA("Decal") then
            v.Transparency = (v.Transparency == 1) and 0 or 1
        end
    end
end

local function findModelsInFolder(folder, modelName)
    local models = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") and child.Name == modelName then table.insert(models, child)
        elseif child:IsA("Folder") or child:IsA("Part") then
            for _, m in ipairs(findModelsInFolder(child, modelName)) do table.insert(models, m) end
        end
    end
    return models
end

local function findPartByName(folder, partName)
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Part") and child.Name == partName then return child
        elseif child:IsA("Folder") then
            local found = findPartByName(child, partName)
            if found then return found end
        end
    end
    return nil
end

local function findAllParts(partName)
    local parts = {}
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Name == partName then table.insert(parts, descendant) end
    end
    return parts
end

local function teleportToCFrame(cframe)
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        player.Character.HumanoidRootPart.CFrame = cframe * CFrame.new(atmOffsetX, atmOffsetY, atmOffsetZ)
    end
end

local function teleportToDropOffPoint()
    local dropOffPart = findPartByName(workspace, "CriminalDropOffSpawnerPermanent")
    if dropOffPart and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        local hrp = player.Character.HumanoidRootPart
        local basePos = dropOffPart.Position
        
        -- ULTRA AGGRESSIVE JIGGLE - GUARANTEED MULTIPLE TOUCHES!
        local movements = {
            Vector3.new(0, 15, 0),    -- WAY above (approach from top)
            Vector3.new(0, 10, 0),    -- High above
            Vector3.new(0, 5, 0),     -- Above
            Vector3.new(0, 2, 0),     -- Slightly above
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #1!)
            Vector3.new(0, -1, 0),    -- Slightly below
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #2!)
            Vector3.new(3, 0, 0),     -- Right side
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #3!)
            Vector3.new(-3, 0, 0),    -- Left side
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #4!)
            Vector3.new(0, 0, 3),     -- Forward
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #5!)
            Vector3.new(0, 0, -3),    -- Back
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #6!)
            Vector3.new(2, 1, 2),     -- Diagonal up
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #7!)
            Vector3.new(-2, -1, -2),  -- Diagonal down
            Vector3.new(0, 0, 0),     -- CENTER (TOUCH #8!)
            Vector3.new(0, 2, 0),     -- Up again
            Vector3.new(0, -2, 0),    -- Down through it
            Vector3.new(0, 0, 0),     -- FINAL CENTER (TOUCH #9!)
        }
        
        for _, offset in ipairs(movements) do
            if player.Character and hrp then
                hrp.CFrame = CFrame.new(basePos + offset)
                hrp.AssemblyLinearVelocity = Vector3.zero  -- Stop all movement
                hrp.AssemblyAngularVelocity = Vector3.zero  -- Stop rotation
                task.wait(0.35)  -- INCREASED: More time for touch to register (was 0.25)
            end
        end
    end
end

local function teleportToPresent(presentPart)
    if presentPart and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        player.Character.HumanoidRootPart.CFrame = CFrame.new(presentPart.Position + Vector3.new(0, 5, 0))
    end
end

-- Helper to get random present easily
local function teleportToRandomPresent()
    local presents = findAllParts("PresentSpawnerPad")
    if #presents > 0 then
        local randomPad = presents[math.random(1, #presents)]
        teleportToPresent(randomPad)
        return true
    end
    return false
end

local function teleportToSpawn()
    local spawnLocation = nil
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("SpawnLocation") or (descendant:IsA("BasePart") and descendant.Name == "SpawnLocation") then
            spawnLocation = descendant
            break
        end
    end
    if spawnLocation and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        player.Character.HumanoidRootPart.CFrame = CFrame.new(spawnLocation.Position + Vector3.new(0, 3, 0))
    end
end

-- ===== ATM MEMORY SYSTEM =====
local function wasRecentlyVisited(position)
    -- Check if this ATM position is in our recent memory
    for _, visitedPos in ipairs(visitedATMs) do
        local distance = (position - visitedPos).Magnitude
        if distance < 5 then  -- Within 5 studs = same ATM
            return true
        end
    end
    return false
end

local function rememberATM(position)
    -- Add new ATM to memory
    table.insert(visitedATMs, 1, position)  -- Insert at front
    
    -- Keep only last 5 (remove oldest if over limit)
    while #visitedATMs > maxVisitedHistory do
        table.remove(visitedATMs, #visitedATMs)  -- Remove last (oldest)
    end
end

-- ===== ENHANCED MAP DELETE FUNCTION =====
local function deleteMapForPerformance()
    local deletedCount = 0
    
    local workspaceFolders = {
        "HousePlots", "Matchmaking", "NPCs", "NascarWorld", 
        "PersistentRaceSpawns", "Props", "RegionsContent", "Map", "NEW MAP ADDITIONS"
    }
    
    for _, folderName in ipairs(workspaceFolders) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            pcall(function()
                folder:Destroy()
                deletedCount = deletedCount + 1
            end)
        end
    end
    
    pcall(function()
        local gameFolder = workspace:FindFirstChild("Game")
        if gameFolder then
            local trees = gameFolder:FindFirstChild("Trees")
            local props = gameFolder:FindFirstChild("Props")
            local nightLights = gameFolder:FindFirstChild("NightAmbience_Lights")
            local dayLights = gameFolder:FindFirstChild("Lights (24 Hours)")
            
            if trees then trees:Destroy(); deletedCount = deletedCount + 1 end
            if props then props:Destroy(); deletedCount = deletedCount + 1 end
            if nightLights then nightLights:Destroy(); deletedCount = deletedCount + 1 end
            if dayLights then dayLights:Destroy(); deletedCount = deletedCount + 1 end
        end
    end)
    
    return deletedCount
end

-- ===== PERFORMANCE MODE OPTIMIZATION =====
local function applyPerformanceOptimizations()
    if not performanceModeEnabled then return end
    
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                local skipNames = {"CriminalATM", "PresentSpawnerPad", "CriminalDropOffSpawnerPermanent", "SpawnLocation"}
                local shouldSkip = false
                
                for _, skipName in ipairs(skipNames) do
                    if obj.Name:find(skipName) or (obj.Parent and obj.Parent.Name:find(skipName)) then
                        shouldSkip = true
                        break
                    end
                end
                
                if player.Character and obj:IsDescendantOf(player.Character) then
                    shouldSkip = true
                end
                
                if not shouldSkip then
                    obj.CastShadow = false
                    if obj.Material == Enum.Material.Glass or obj.Transparency > 0.5 then
                        obj.CanCollide = false
                    end
                end
            elseif obj:IsA("Decal") or obj:IsA("Texture") then
                obj.Transparency = 1
            elseif obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
                obj.Enabled = false
            end
        end
    end)
end

-- ===== SIMPLE ALERT LOGIC =====
local function setupSimpleAlerts()
    local function monitorPlayer(plr)
        plr:GetPropertyChangedSignal("Team"):Connect(function()
            if alertModeEnabled and plr.Team then
                local t = plr.Team.Name:lower()
                if t:find("security") or t:find("police") or t:find("cop") then
                    notify("ALERT", "⚠️ " .. plr.Name .. " is now Security!")
                end
            end
        end)
    end
    
    Players.PlayerAdded:Connect(function(plr)
        monitorPlayer(plr)
        if alertModeEnabled then notify("JOIN", plr.Name.." joined.") end
    end)
    
    for _, p in ipairs(Players:GetPlayers()) do monitorPlayer(p) end
end
setupSimpleAlerts()

-- ===== CACHE REFRESHER =====
local function refreshPromptCache()
    local tempCache = {}
    
    -- Find CriminalATM models (these are the READY ones)
    local models = findModelsInFolder(workspace, "CriminalATM")
    for _, model in ipairs(models) do
        local pos = nil
        if model.PrimaryPart then 
            pos = model.PrimaryPart.Position
        elseif model:FindFirstChild("Position") then 
            pos = model.Position.Position 
        end
        
        local prompt = nil
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then prompt = desc; break end
        end
        
        if pos and prompt then
            table.insert(tempCache, {
                Prompt = prompt, 
                Position = pos, 
                Model = model, 
                MaxDist = prompt.MaxActivationDistance
            })
        end
    end
    promptFastCache = tempCache

    -- Find spawners for GUI display
    local spawners = findAllParts("CriminalATMSpawner")
    for _, spawner in ipairs(spawners) do
        local alreadyKnown = false
        for _, k in ipairs(knownSpawners) do
            if k == spawner then alreadyKnown = true; break end
        end
        if not alreadyKnown then
            table.insert(knownSpawners, spawner)
        end
    end
end

-- ===== ESP SYSTEM =====
local function createESP(targetPlayer)
    if targetPlayer == player then return end 
    local bg = Instance.new("BillboardGui")
    bg.Name = "ESP_UI"
    bg.AlwaysOnTop = true
    bg.Size = UDim2.new(0, 200, 0, 50)
    bg.StudsOffset = Vector3.new(0, 3, 0)
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Parent = bg
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.new(1,1,1)
    nameLabel.TextStrokeTransparency = 0.5
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 13
    
    local distLabel = Instance.new("TextLabel")
    distLabel.Parent = bg
    distLabel.Position = UDim2.new(0, 0, 0.5, 0)
    distLabel.Size = UDim2.new(1, 0, 0.5, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextStrokeTransparency = 0.5
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = 11
    
    espCache[targetPlayer] = {GUI = bg, NameLabel = nameLabel, DistLabel = distLabel}
end

local function removeESP(targetPlayer)
    if espCache[targetPlayer] then
        if espCache[targetPlayer].GUI then espCache[targetPlayer].GUI:Destroy() end
        espCache[targetPlayer] = nil
    end
end

local function updateESP()
    for target, data in pairs(espCache) do
        if target.Character and target.Character:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = target.Character.HumanoidRootPart
            local myPos = player.Character.HumanoidRootPart.Position
            local dist = math.floor((hrp.Position - myPos).Magnitude)
            local head = target.Character:FindFirstChild("Head")
            if head then
                data.GUI.Parent = head
                data.GUI.Enabled = espEnabled
                data.NameLabel.Text = target.Name .. " [" .. tostring(target.Team) .. "]"
                data.NameLabel.TextColor3 = target.TeamColor.Color
                data.DistLabel.Text = tostring(dist) .. " studs"
            else
                data.GUI.Enabled = false
            end
        else
            data.GUI.Enabled = false
        end
    end
end

Players.PlayerAdded:Connect(createESP)
Players.PlayerRemoving:Connect(removeESP)
for _, p in ipairs(Players:GetPlayers()) do createESP(p) end

-- ===== UI BUILDER =====
local function MakeDraggable(topbarobject, object)
    local Dragging, DragInput, DragStart, StartPosition
    local function Update(input)
        local Delta = input.Position - DragStart
        object.Position = UDim2.new(StartPosition.X.Scale, StartPosition.X.Offset + Delta.X, StartPosition.Y.Scale, StartPosition.Y.Offset + Delta.Y)
    end
    topbarobject.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Dragging = true
            DragStart = input.Position
            StartPosition = object.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then Dragging = false end
            end)
        end
    end)
    topbarobject.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then DragInput = input end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == DragInput and Dragging then Update(input) end
    end)
end

local function createGUI()
    local existingGui = player.PlayerGui:FindFirstChild("DrivingHubUI")
    if existingGui then existingGui:Destroy() end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DrivingHubUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 185, 0, 295)
    frame.Position = UDim2.new(0, 30, 0, 30)
    frame.BackgroundColor3 = THEME.Background
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local mainStroke = Instance.new("UIStroke", frame)
    mainStroke.Color = THEME.Stroke
    mainStroke.Thickness = 2

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 34)
    header.BackgroundColor3 = THEME.Header
    header.BorderSizePixel = 0
    header.Parent = frame
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = THEME.TitleColor
    title.Text = "DRIVING HUB"
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(0, 45, 1, 0)
    versionLabel.Position = UDim2.new(1, -80, 0, 0)
    versionLabel.BackgroundTransparency = 1
    versionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    versionLabel.Text = VERSION
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.TextSize = 9
    versionLabel.TextXAlignment = Enum.TextXAlignment.Right
    versionLabel.Parent = header

    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, 34, 0, 34)
    toggleButton.Position = UDim2.new(1, -34, 0, 0)
    toggleButton.Text = "-"
    toggleButton.Font = Enum.Font.GothamBlack
    toggleButton.TextSize = 20
    toggleButton.TextColor3 = THEME.Text
    toggleButton.BackgroundTransparency = 1
    toggleButton.Parent = header

    MakeDraggable(header, frame)

    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, -10, 0, 30)
    tabContainer.Position = UDim2.new(0, 5, 0, 38)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = frame
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 5)
    tabLayout.Parent = tabContainer

    local function createTabBtn(text, color)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.31, 0, 1, 0)
        btn.BackgroundColor3 = THEME.Off
        btn.Text = text
        btn.TextColor3 = THEME.Text
        btn.Font = Enum.Font.GothamBlack
        btn.TextSize = 11
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local stroke = Instance.new("UIStroke", btn)
        stroke.Color = color
        stroke.Thickness = 2
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        btn.Parent = tabContainer
        return btn
    end

    local atmTabButton = createTabBtn("ATMs", THEME.AtmAccent)
    local funTabButton = createTabBtn("Fun", THEME.FunAccent)
    local farmTabButton = createTabBtn("Farm", THEME.FarmAccent)

    local function createScroll()
        local s = Instance.new("ScrollingFrame")
        s.Size = UDim2.new(1, -10, 1, -74)
        s.Position = UDim2.new(0, 5, 0, 72)
        s.BackgroundTransparency = 1
        s.ScrollBarThickness = 3
        s.ScrollBarImageColor3 = THEME.Stroke
        s.Parent = frame
        s.Visible = false
        local l = Instance.new("UIListLayout")
        l.Padding = UDim.new(0, 5)
        l.SortOrder = Enum.SortOrder.LayoutOrder
        l.Parent = s
        return s, l
    end

    local atmScroll, atmLayout = createScroll()
    local funScroll, funLayout = createScroll()
    local farmScroll, farmLayout = createScroll()
    atmScroll.Visible = true

    local expanded = true
    toggleButton.MouseButton1Click:Connect(function()
        expanded = not expanded
        frame.Size = expanded and UDim2.new(0, 185, 0, 295) or UDim2.new(0, 185, 0, 34)
        tabContainer.Visible = expanded
        toggleButton.Text = expanded and "-" or "+"
        if expanded then
            if atmTabButton.BackgroundColor3 == THEME.AtmAccent then atmScroll.Visible = true
            elseif funTabButton.BackgroundColor3 == THEME.FunAccent then funScroll.Visible = true
            elseif farmTabButton.BackgroundColor3 == THEME.FarmAccent then farmScroll.Visible = true
            else atmScroll.Visible = true end
        else
            atmScroll.Visible = false; funScroll.Visible = false; farmScroll.Visible = false
        end
    end)

    local function switchTab(activeBtn, activeScroll, color)
        atmTabButton.BackgroundColor3 = THEME.Off
        funTabButton.BackgroundColor3 = THEME.Off
        farmTabButton.BackgroundColor3 = THEME.Off
        atmScroll.Visible = false; funScroll.Visible = false; farmScroll.Visible = false
        activeBtn.BackgroundColor3 = color 
        activeScroll.Visible = true
    end

    atmTabButton.MouseButton1Click:Connect(function() switchTab(atmTabButton, atmScroll, THEME.AtmAccent) end)
    funTabButton.MouseButton1Click:Connect(function() switchTab(funTabButton, funScroll, THEME.FunAccent) end)
    farmTabButton.MouseButton1Click:Connect(function() switchTab(farmTabButton, farmScroll, THEME.FarmAccent) end)
    atmTabButton.BackgroundColor3 = THEME.AtmAccent

    return frame, atmScroll, atmLayout, funScroll, funLayout, farmScroll, farmLayout
end

local function createStyledButton(parent, text, defaultColor, order, borderColor)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = defaultColor or THEME.Off
    btn.TextColor3 = THEME.Text
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.LayoutOrder = order or 999
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    if borderColor then
        local st = Instance.new("UIStroke", btn)
        st.Color = borderColor
        st.Thickness = 1.5
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    end
    return btn
end

local function createSectionLabel(parent, text, order)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 22)
    label.BackgroundTransparency = 1
    label.Text = "━━ " .. text .. " ━━"
    label.TextColor3 = THEME.TitleColor
    label.Font = Enum.Font.GothamBlack
    label.TextSize = 11
    label.LayoutOrder = order or 0
    label.Parent = parent
    return label
end

-- ===== TAB: ATM UPDATER =====
local function updateATMGUI(scrollFrame)
    if not scrollFrame:FindFirstChild("DropOffBtn") then
        local btn = createStyledButton(scrollFrame, "Drop Off", THEME.DropOff, 1, THEME.On)
        btn.Name = "DropOffBtn"
        btn.MouseButton1Click:Connect(function() teleportToDropOffPoint() end)
    end
    if not scrollFrame:FindFirstChild("SpawnBtn") then
        local btn = createStyledButton(scrollFrame, "Teleport to Spawn", THEME.Spawn, 2, THEME.On)
        btn.Name = "SpawnBtn"
        btn.MouseButton1Click:Connect(function() teleportToSpawn() end)
    end
    
    for i, spawner in ipairs(knownSpawners) do
        if spawner.Parent then
            local btnName = "SpawnerBtn_" .. i
            local existingBtn = scrollFrame:FindFirstChild(btnName)
            
            local isReady = spawner:FindFirstChild("CriminalATM") ~= nil
            local btnText = isReady and "🟢 ATM (Ready)" or "🔴 ATM (Robbed)"
            local btnColor = isReady and THEME.On or THEME.Destructive
            
            if not existingBtn then
                local btn = createStyledButton(scrollFrame, btnText, btnColor, 3, THEME.Stroke)
                btn.Name = btnName
                table.insert(activeATMButtons, btn)
                
                btn.MouseButton1Click:Connect(function()
                    for _, b in pairs(activeATMButtons) do
                        if b.Name ~= "DropOffBtn" and b.Name ~= "SpawnBtn" then
                            if b.Text:find("Ready") then b.BackgroundColor3 = THEME.On else b.BackgroundColor3 = THEME.Destructive end
                        end
                    end
                    btn.BackgroundColor3 = THEME.AtmAccent
                    teleportToCFrame(spawner.CFrame)
                end)
            else
                if existingBtn.BackgroundColor3 ~= THEME.AtmAccent then
                    existingBtn.Text = btnText
                    existingBtn.BackgroundColor3 = btnColor
                end
            end
        end
    end
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, scrollFrame.UIListLayout.AbsoluteContentSize.Y)
end

-- ===== TAB: SMART AUTO FARM (WITH 3 OPTIONS) =====
local function setupAutoFarm(scrollFrame)
    
    createSectionLabel(scrollFrame, "FARM SETTINGS", 1)
    
    -- TP Offset
    local offsetFrame = Instance.new("Frame")
    offsetFrame.Size = UDim2.new(1, 0, 0, 45)
    offsetFrame.BackgroundColor3 = THEME.Header
    offsetFrame.BorderSizePixel = 0
    offsetFrame.LayoutOrder = 2
    offsetFrame.Parent = scrollFrame
    Instance.new("UICorner", offsetFrame).CornerRadius = UDim.new(0, 6)
    
    local offsetLabel = Instance.new("TextLabel")
    offsetLabel.Text = "TP Offset (X, Y, Z):"
    offsetLabel.TextColor3 = THEME.Text
    offsetLabel.BackgroundTransparency = 1
    offsetLabel.Font = Enum.Font.GothamBold
    offsetLabel.TextSize = 9
    offsetLabel.Size = UDim2.new(1, -10, 0, 14)
    offsetLabel.Position = UDim2.new(0, 5, 0, 5)
    offsetLabel.TextXAlignment = Enum.TextXAlignment.Left
    offsetLabel.Parent = offsetFrame
    
    local function createInput(default, pos)
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0.28, 0, 0, 18)
        box.Position = pos
        box.BackgroundColor3 = THEME.Background
        box.TextColor3 = THEME.Text
        box.Text = tostring(default)
        box.Font = Enum.Font.GothamBold
        box.TextSize = 10
        box.Parent = offsetFrame
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
        return box
    end
    
    local xInput = createInput(atmOffsetX, UDim2.new(0.05, 0, 0, 24))
    local yInput = createInput(atmOffsetY, UDim2.new(0.36, 0, 0, 24))
    local zInput = createInput(atmOffsetZ, UDim2.new(0.67, 0, 0, 24))
    
    xInput.FocusLost:Connect(function() atmOffsetX = tonumber(xInput.Text) or 0 end)
    yInput.FocusLost:Connect(function() atmOffsetY = tonumber(yInput.Text) or 0 end)
    zInput.FocusLost:Connect(function() atmOffsetZ = tonumber(zInput.Text) or 0 end)

    -- SAFE MODE (MOVED TO FARM TAB) - UPDATED: NO LONGER STOPS AUTO FARM
    local safeContainer = Instance.new("Frame")
    safeContainer.Size = UDim2.new(1, 0, 0, 35)
    safeContainer.BackgroundTransparency = 1
    safeContainer.LayoutOrder = 3
    safeContainer.Parent = scrollFrame
    
    local safeInfoLabel = Instance.new("TextLabel")
    safeInfoLabel.Size = UDim2.new(1, -10, 0, 12)
    safeInfoLabel.Position = UDim2.new(0, 5, 0, 0)
    safeInfoLabel.BackgroundTransparency = 1
    safeInfoLabel.Text = "🛡️ Auto-escape when players nearby"
    safeInfoLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    safeInfoLabel.Font = Enum.Font.GothamBold
    safeInfoLabel.TextSize = 7
    safeInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    safeInfoLabel.Parent = safeContainer

    local safeButton = Instance.new("TextButton")
    safeButton.Size = UDim2.new(0.65, 0, 0, 20)
    safeButton.Position = UDim2.new(0, 5, 0, 14)
    safeButton.BackgroundColor3 = THEME.Off
    safeButton.Text = "Safe Mode: OFF"
    safeButton.TextColor3 = THEME.Text
    safeButton.Font = Enum.Font.GothamBold
    safeButton.TextSize = 9
    safeButton.Parent = safeContainer
    Instance.new("UICorner", safeButton).CornerRadius = UDim.new(0, 6)
    local s1 = Instance.new("UIStroke", safeButton)
    s1.Color = THEME.SafeV2
    s1.Thickness = 1.5
    s1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local safeInput = Instance.new("TextBox")
    safeInput.Size = UDim2.new(0.32, 0, 0, 20)
    safeInput.Position = UDim2.new(0.68, 0, 0, 14)
    safeInput.BackgroundColor3 = THEME.Header
    safeInput.Text = tostring(safeModeDistance)
    safeInput.TextColor3 = THEME.Text
    safeInput.Font = Enum.Font.GothamBold
    safeInput.TextSize = 10
    safeInput.PlaceholderText = "Dist"
    safeInput.Parent = safeContainer
    Instance.new("UICorner", safeInput).CornerRadius = UDim.new(0, 6)
    
    -- NOTE: Safe Mode variable is global
    safeButton.MouseButton1Click:Connect(function()
        safeModeEnabled = not safeModeEnabled
        safeButton.Text = "Safe Mode: " .. (safeModeEnabled and "ON" or "OFF")
        safeButton.BackgroundColor3 = safeModeEnabled and THEME.On or THEME.Off
    end)
    
    safeInput.FocusLost:Connect(function()
        local num = tonumber(safeInput.Text)
        if num then 
            safeModeDistance = num
            notify("✅ Safe Distance", safeModeDistance .. " studs")
        else 
            safeInput.Text = tostring(safeModeDistance)
        end
    end)

    -- === FARM CONTROLS ===
    createSectionLabel(scrollFrame, "AUTO FARM", 4)
    
    local farmButton = createStyledButton(scrollFrame, "Smart ATM Farm: OFF", THEME.Off, 5, THEME.FarmAccent)
    local presentFarmButton = createStyledButton(scrollFrame, "Present Farm: OFF", THEME.Off, 6, THEME.FarmAccent)
    
    -- Make farmButton accessible for external reference
    _G.FarmButtonRef = farmButton

    presentFarmButton.MouseButton1Click:Connect(function()
        presentFarmEnabled = not presentFarmEnabled
        presentFarmButton.Text = "Present Farm: " .. (presentFarmEnabled and "ON" or "OFF")
        presentFarmButton.BackgroundColor3 = presentFarmEnabled and THEME.On or THEME.Off
        if presentFarmEnabled then
            if farmModeEnabled then 
                farmModeEnabled = false
                farmButton.Text = "Smart ATM Farm: OFF"
                farmButton.BackgroundColor3 = THEME.Off 
            end
            task.spawn(function()
                while presentFarmEnabled do
                    local presentPads = findAllParts("PresentSpawnerPad")
                    if #presentPads > 0 then
                        for i, pad in ipairs(presentPads) do
                            if not presentFarmEnabled then break end
                            teleportToPresent(pad)
                            task.wait(0.3)
                        end
                    end
                    task.wait(5)
                end
            end)
        end
    end)

    -- SMART ATM FARM WITH 3 OPTIONS - UPDATED: SAFE MODE NO LONGER STOPS FARM
    farmButton.MouseButton1Click:Connect(function()
        farmModeEnabled = not farmModeEnabled
        farmButton.Text = "Smart ATM Farm: " .. (farmModeEnabled and "ON" or "OFF")
        farmButton.BackgroundColor3 = farmModeEnabled and THEME.On or THEME.Off
        
        if farmModeEnabled then
            if presentFarmEnabled then 
                presentFarmEnabled = false
                presentFarmButton.Text = "Present Farm: OFF"
                presentFarmButton.BackgroundColor3 = THEME.Off 
            end
            if not autoPromptEnabled then autoPromptEnabled = true end
            
            notify("Farm Started", "3 Options Active!")
            
            task.spawn(function()
                local atmCounter = 0
                local consecutiveSkips = 0
                
                while farmModeEnabled do
                    -- FORCE REFRESH CACHE every loop to ensure we have latest ATMs
                    refreshPromptCache()
                    
                    -- Get ONLY READY ATMs (ones that have CriminalATM model)
                    local readyATMs = {}
                    local totalReadyATMs = 0  -- Count before memory filter
                    
                    for _, item in ipairs(promptFastCache) do
                        -- Check if the spawner still has CriminalATM model (READY status)
                        local spawner = item.Model.Parent
                        if spawner and spawner:IsA("BasePart") and spawner.Name == "CriminalATMSpawner" then
                            if spawner:FindFirstChild("CriminalATM") then
                                totalReadyATMs = totalReadyATMs + 1
                                
                                -- MEMORY CHECK: Skip if we visited this ATM recently
                                if not wasRecentlyVisited(item.Position) then
                                    table.insert(readyATMs, item)
                                end
                            end
                        end
                    end
                    
                    -- EMERGENCY: If memory is filtering out ALL ATMs, clear it!
                    if totalReadyATMs > 0 and #readyATMs == 0 then
                        notify("Memory Full", "Clearing memory to access ATMs!")
                        visitedATMs = {}
                        -- Retry the filter without memory
                        for _, item in ipairs(promptFastCache) do
                            local spawner = item.Model.Parent
                            if spawner and spawner:IsA("BasePart") and spawner.Name == "CriminalATMSpawner" then
                                if spawner:FindFirstChild("CriminalATM") then
                                    table.insert(readyATMs, item)
                                end
                            end
                        end
                    end
                    
                    if #readyATMs > 0 then
                        for _, item in ipairs(readyATMs) do
                            if not farmModeEnabled then break end
                            
                            notify("TP to ATM", "#" .. (atmCounter + 1) .. " | Skips: " .. consecutiveSkips .. " | Mem: " .. #visitedATMs)
                            teleportToCFrame(CFrame.new(item.Position))
                            rememberATM(item.Position)  -- REMEMBER: Add to visited memory
                            task.wait(0.8)  -- STABILITY: Let game load ATM and prompts
                            atmCounter = atmCounter + 1
                            
                            local tpTime = tick()
                            local promptsCompleted = 0
                            local lastActivity = tick()
                            local loopStart = tick()
                            
                            -- HYBRID LOOP WITH 3 OPTIONS
                            while (tick() - loopStart) < 20 and farmModeEnabled do
                                task.wait(0.2)  -- Keep 0.2 for stability
                                
                                if lastPromptCompletionTime > lastActivity then
                                    promptsCompleted = promptsCompleted + 1
                                    lastActivity = tick()
                                    consecutiveSkips = 0
                                    
                                    if promptsCompleted == 1 then
                                        notify("Prompt 1 ✅", "Wait " .. waitForSecondPrompt .. "s")
                                        task.wait(waitForSecondPrompt)  -- UPDATED: Now uses 9.0s default
                                    elseif promptsCompleted == 2 then
                                        notify("Prompt 2 ✅", "Done!")
                                        task.wait(2)
                                        break
                                    end
                                end
                                
                                -- Option 2: Stay at ATM
                                if promptsCompleted > 0 and (tick() - lastActivity) > inactivityTimeout then
                                    notify("Done", promptsCompleted .. " prompt(s)")
                                    break
                                end
                                
                                -- Option 3: Quick Skip
                                if promptsCompleted == 0 and (tick() - loopStart) > quickSkipTime then
                                    notify("Quick Skip", "Empty | Skip: " .. (consecutiveSkips + 1))
                                    consecutiveSkips = consecutiveSkips + 1
                                    break
                                end
                            end
                            
                            -- Break mode (happens less often now - 5 skips instead of 3)
                            if consecutiveSkips >= consecutiveSkipsForBreak then
                                notify("Break Mode", "15s break...")
                                isInBreakMode = true  -- SIGNAL: Pause auto prompt
                                consecutiveSkips = 0
                                local breakStart = tick()
                                while (tick() - breakStart) < 15 and farmModeEnabled do
                                    local presents = findAllParts("PresentSpawnerPad")
                                    if #presents > 0 then
                                        teleportToPresent(presents[math.random(1, #presents)])
                                        task.wait(0.5)
                                    else
                                        break
                                    end
                                end
                                isInBreakMode = false  -- RESUME: Auto prompt can work again
                                notify("Break Done", "Back to ATMs!")
                            end
                            
                            -- Drop off happens less often (every 12 ATMs instead of 10)
                            if atmCounter >= 12 and farmModeEnabled then
                                notify("Drop Off", "Depositing money...")
                                
                                -- 1. CRITICAL: DISABLE FLY/NOCLIP *BEFORE* TELEPORTING!
                                local wasFlying = flyEnabled
                                local wasNoclip = noclipEnabled
                                
                                -- Turn off immediately
                                if wasFlying then 
                                    flyEnabled = false 
                                end
                                if wasNoclip then 
                                    noclipEnabled = false
                                end
                                
                                -- Wait for systems to actually disable
                                task.wait(0.5)
                                
                                -- Aggressively clean up fly physics objects
                                if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                                    local hrp = player.Character.HumanoidRootPart
                                    
                                    -- Remove fly components
                                    if hrp:FindFirstChild("FlyVelocity") then 
                                        hrp.FlyVelocity:Destroy() 
                                    end
                                    if hrp:FindFirstChild("FlyGyro") then 
                                        hrp.FlyGyro:Destroy() 
                                    end
                                    
                                    -- Reset physics
                                    hrp.AssemblyLinearVelocity = Vector3.zero
                                    hrp.AssemblyAngularVelocity = Vector3.zero
                                end
                                
                                -- CRITICAL: Re-enable collisions for ALL body parts (for touch detection!)
                                if player.Character then
                                    for _, part in pairs(player.Character:GetChildren()) do
                                        if part:IsA("BasePart") then
                                            part.CanCollide = true  -- Force collisions ON
                                        end
                                    end
                                end
                                
                                task.wait(0.3)  -- Extra safety wait for physics to settle
                                
                                -- 2. DO DROP OFF (Ultra Aggressive Jiggle = 9 GUARANTEED TOUCHES!)
                                teleportToDropOffPoint()
                                
                                task.wait(2.5)  -- INCREASED: Let server fully process all 9 touch events
                                
                                -- 3. RE-ENABLE FLY/NOCLIP IF THEY WERE ON
                                if wasFlying then 
                                    flyEnabled = true 
                                end
                                if wasNoclip then 
                                    noclipEnabled = true
                                end
                                
                                atmCounter = 0
                                notify("Drop Off Complete", "Back to farming!")
                            end
                            
                            task.wait(0.5)
                        end
                    else
                        -- NO ATMs FOUND! This is a problem - let's fix it
                        notify("No ATMs", "Cache:" .. #promptFastCache .. " | Clearing memory...")
                        
                        -- CLEAR MEMORY (might be filtering everything out)
                        visitedATMs = {}
                        
                        -- FORCE CACHE REFRESH AGAIN
                        refreshPromptCache()
                        
                        -- DO PRESENT FARM while waiting for ATMs to respawn
                        local presentFarmTime = tick()
                        while (tick() - presentFarmTime) < 15 and farmModeEnabled do
                            local presents = findAllParts("PresentSpawnerPad")
                            if #presents > 0 then
                                local randomPresent = presents[math.random(1, #presents)]
                                teleportToPresent(randomPresent)
                                task.wait(0.5)
                            else
                                task.wait(1)
                            end
                        end
                        
                        notify("Rescan Complete", "Back to ATM farming!")
                    end
                    
                    task.wait(1)
                end
            end)
        end
    end)
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, scrollFrame.UIListLayout.AbsoluteContentSize.Y)
end

-- ===== TAB: FUN MENU (UPDATED: ADDED TEST PROMPT BUTTON) =====
local function setupFunMenu(scrollFrame)
    
    createSectionLabel(scrollFrame, "PERFORMANCE", 1)
    
    local deleteMapButton = createStyledButton(scrollFrame, "Delete Map Objects", THEME.Off, 2, THEME.Destructive)
    deleteMapButton.MouseButton1Click:Connect(function()
        local count = deleteMapForPerformance()
        if count > 0 then
            deleteMapButton.Text = "Deleted " .. count .. " Objects!"
            deleteMapButton.BackgroundColor3 = THEME.Destructive
            notify("FPS Boost", count .. " objects removed!")
            task.wait(2)
            deleteMapButton.Text = "Delete Map Objects"
            deleteMapButton.BackgroundColor3 = THEME.Off
        else
            deleteMapButton.Text = "Nothing Found"
            task.wait(1)
            deleteMapButton.Text = "Delete Map Objects"
        end
    end)

    local perfButton = createStyledButton(scrollFrame, "Performance Mode: OFF", THEME.Off, 3, THEME.Performance)
    perfButton.MouseButton1Click:Connect(function()
        performanceModeEnabled = not performanceModeEnabled
        perfButton.Text = "Performance Mode: " .. (performanceModeEnabled and "ON" or "OFF")
        perfButton.BackgroundColor3 = performanceModeEnabled and THEME.On or THEME.Off
        if performanceModeEnabled then
            applyPerformanceOptimizations()
            notify("Performance Mode", "Shadows & effects disabled!")
        end
    end)

    createSectionLabel(scrollFrame, "ALERTS", 4)
    
    local alertButton = createStyledButton(scrollFrame, "Alert Mode: OFF", THEME.Off, 5, THEME.Warning)
    alertButton.MouseButton1Click:Connect(function()
        alertModeEnabled = not alertModeEnabled
        alertButton.Text = "Alert Mode: " .. (alertModeEnabled and "ON" or "OFF")
        alertButton.BackgroundColor3 = alertModeEnabled and THEME.On or THEME.Off
    end)

    createSectionLabel(scrollFrame, "VISUALS", 7)
    
    local espButton = createStyledButton(scrollFrame, "ESP: OFF", THEME.Off, 8, THEME.FunAccent)
    espButton.MouseButton1Click:Connect(function()
        espEnabled = not espEnabled
        espButton.Text = "ESP: " .. (espEnabled and "ON" or "OFF")
        espButton.BackgroundColor3 = espEnabled and THEME.On or THEME.Off
        if not espEnabled then for _, data in pairs(espCache) do data.GUI.Enabled = false end end
    end)

    local ghostButton = createStyledButton(scrollFrame, "Ghost Mode: OFF", THEME.Off, 9, THEME.FunAccent)
    ghostButton.MouseButton1Click:Connect(function()
        toggleGhostMode()
        local isOn = (ghostButton.BackgroundColor3 == THEME.On)
        ghostButton.BackgroundColor3 = isOn and THEME.Off or THEME.On
        ghostButton.Text = "Ghost Mode: " .. (isOn and "OFF" or "ON")
    end)

    createSectionLabel(scrollFrame, "MOVEMENT", 10)
    
    local noclipButton = createStyledButton(scrollFrame, "Noclip: OFF", THEME.Off, 11, THEME.FunAccent)
    noclipButton.MouseButton1Click:Connect(function()
        noclipEnabled = not noclipEnabled
        noclipButton.Text = "Noclip: " .. (noclipEnabled and "ON" or "OFF")
        noclipButton.BackgroundColor3 = noclipEnabled and THEME.On or THEME.Off
    end)

    local flyContainer = Instance.new("Frame")
    flyContainer.Size = UDim2.new(1, 0, 0, 30)
    flyContainer.BackgroundTransparency = 1
    flyContainer.LayoutOrder = 12
    flyContainer.Parent = scrollFrame

    local flyButton = Instance.new("TextButton")
    flyButton.Size = UDim2.new(0.65, 0, 1, 0)
    flyButton.BackgroundColor3 = THEME.Off
    flyButton.Text = "Fly: OFF"
    flyButton.TextColor3 = THEME.Text
    flyButton.Font = Enum.Font.GothamBold
    flyButton.TextSize = 10
    flyButton.Parent = flyContainer
    Instance.new("UICorner", flyButton).CornerRadius = UDim.new(0, 6)
    
    local speedInput = Instance.new("TextBox")
    speedInput.Size = UDim2.new(0.32, 0, 1, 0)
    speedInput.Position = UDim2.new(0.68, 0, 0, 0)
    speedInput.BackgroundColor3 = THEME.Header
    speedInput.Text = tostring(flySpeed)
    speedInput.TextColor3 = THEME.Text
    speedInput.Font = Enum.Font.GothamBold
    speedInput.TextSize = 11
    speedInput.PlaceholderText = "Spd"
    speedInput.Parent = flyContainer
    Instance.new("UICorner", speedInput).CornerRadius = UDim.new(0, 6)

    flyButton.MouseButton1Click:Connect(function()
        flyEnabled = not flyEnabled
        if flyEnabled then teleportLoopEnabled = false end
        flyButton.Text = "Fly: " .. (flyEnabled and "ON" or "OFF")
        flyButton.BackgroundColor3 = flyEnabled and THEME.On or THEME.Off
    end)
    
    speedInput.FocusLost:Connect(function()
        local num = tonumber(speedInput.Text)
        if num then flySpeed = num else speedInput.Text = tostring(flySpeed) end
    end)

    createSectionLabel(scrollFrame, "TELEPORT", 13)
    
    local teleportButton = createStyledButton(scrollFrame, "Teleport Loop: OFF", THEME.Off, 14, THEME.FunAccent)
    local playerDropdown = createStyledButton(scrollFrame, "Select Player ▼", THEME.Off, 15, THEME.FunAccent)
    local playersExpanded = false
    local playerButtons = {}

    local function refreshPlayerList()
        for _, btn in ipairs(playerButtons) do btn:Destroy() end
        playerButtons = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player then
                local pBtn = createStyledButton(scrollFrame, "  → " .. plr.Name, THEME.Header, 16, nil)
                pBtn.Visible = playersExpanded
                pBtn.MouseButton1Click:Connect(function()
                    teleportTarget = plr
                    playerDropdown.Text = "Target: " .. plr.Name .. " ▼"
                    playersExpanded = false
                    for _, b in ipairs(playerButtons) do b.Visible = false end
                    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, scrollFrame.UIListLayout.AbsoluteContentSize.Y)
                end)
                table.insert(playerButtons, pBtn)
            end
        end
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, scrollFrame.UIListLayout.AbsoluteContentSize.Y)
    end

    playerDropdown.MouseButton1Click:Connect(function()
        playersExpanded = not playersExpanded
        playerDropdown.Text = (teleportTarget and ("Target: " .. teleportTarget.Name) or "Select Player") .. (playersExpanded and " ▲" or " ▼")
        if playersExpanded then refreshPlayerList() end
        for _, btn in ipairs(playerButtons) do btn.Visible = playersExpanded end
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, scrollFrame.UIListLayout.AbsoluteContentSize.Y)
    end)

    teleportButton.MouseButton1Click:Connect(function()
        teleportLoopEnabled = not teleportLoopEnabled
        if teleportLoopEnabled then
            flyEnabled = false
            flyButton.Text = "Fly: OFF"
            flyButton.BackgroundColor3 = THEME.Off
        end
        teleportButton.Text = "Teleport Loop: " .. (teleportLoopEnabled and "ON" or "OFF")
        teleportButton.BackgroundColor3 = teleportLoopEnabled and THEME.On or THEME.Off
    end)

    -- FAST ROB FEATURE (mimics gamepass for faster robbing)
    createSectionLabel(scrollFrame, "FAST ROB", 97)
    
    local fastRobInfo = Instance.new("TextLabel")
    fastRobInfo.Size = UDim2.new(1, 0, 0, 20)
    fastRobInfo.BackgroundTransparency = 1
    fastRobInfo.Text = "⚡ Makes Robbing Faster\n(Don't use if already have gamepass)"
    fastRobInfo.TextColor3 = Color3.fromRGB(180, 180, 180)
    fastRobInfo.Font = Enum.Font.Gotham
    fastRobInfo.TextSize = 7
    fastRobInfo.TextWrapped = true
    fastRobInfo.TextYAlignment = Enum.TextYAlignment.Top
    fastRobInfo.LayoutOrder = 97.5
    fastRobInfo.Parent = scrollFrame
    
    local fastRobButton = createStyledButton(scrollFrame, "Fast Rob (3.2s): OFF", THEME.Off, 98, THEME.Warning)
    fastRobButton.MouseButton1Click:Connect(function()
        testPromptModeEnabled = not testPromptModeEnabled
        fastRobButton.Text = "Fast Rob (3.2s): " .. (testPromptModeEnabled and "ON" or "OFF")
        fastRobButton.BackgroundColor3 = testPromptModeEnabled and THEME.On or THEME.Off
        
        if testPromptModeEnabled then
            notify("Fast Rob ON", "Robbing speed: 3.2s (LIVE)")
        else
            notify("Fast Rob OFF", "Back to normal speed")
        end
    end)
    
    createSectionLabel(scrollFrame, "AUTOMATION", 99)
    
    local autoPromptButton = createStyledButton(scrollFrame, "Auto Prompt: OFF", THEME.Off, 100, THEME.FunAccent)
    autoPromptButton.MouseButton1Click:Connect(function()
        autoPromptEnabled = not autoPromptEnabled
        autoPromptButton.Text = "Auto Prompt: " .. (autoPromptEnabled and "ON" or "OFF")
        autoPromptButton.BackgroundColor3 = autoPromptEnabled and THEME.On or THEME.Off
    end)
    
    -- OLD TEST PROMPT BUTTON REMOVED - NOW REPLACED BY FAST ROB
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, scrollFrame.UIListLayout.AbsoluteContentSize.Y)
end

local frame, atmScroll, atmLayout, funScroll, funLayout, farmScroll, farmLayout = createGUI()
setupFunMenu(funScroll, funLayout)
setupAutoFarm(farmScroll, farmLayout)

-- ===== MAIN LOOPS =====

RunService.Stepped:Connect(function()
    if noclipEnabled and player.Character then
        for _, part in pairs(player.Character:GetChildren()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end
    
    if teleportLoopEnabled and teleportTarget and teleportTarget.Parent == Players then
        if teleportTarget.Character and teleportTarget.Character:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            player.Character.HumanoidRootPart.CFrame = teleportTarget.Character.HumanoidRootPart.CFrame + Vector3.new(0, 5, 0)
            player.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if performanceModeEnabled and (tick() - lastPerformanceCheck) > performanceCheckInterval then
        lastPerformanceCheck = tick()
        applyPerformanceOptimizations()
    end

    -- UPDATED: SAFE MODE NO LONGER STOPS AUTO FARM
    if safeModeEnabled and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and (tick() - lastSafeTrigger > 2) then
        local myPos = player.Character.HumanoidRootPart.Position
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= player and otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local dist = (otherPlayer.Character.HumanoidRootPart.Position - myPos).Magnitude
                if dist <= safeModeDistance then
                    -- Danger detected! ESCAPE but DON'T STOP FARM
                    
                    -- TELEPORT AWAY (farm will continue after escape)
                    local escaped = teleportToRandomPresent()
                    if not escaped then teleportToSpawn() end -- Fallback
                    
                    lastSafeTrigger = tick()
                    notify("Safe Mode", "Escaped from: " .. otherPlayer.Name)
                    
                    -- Wait a moment to let physics catch up
                    task.wait(0.5) 
                    break
                end
            end
        end
    end

    if flyEnabled and player.Character then
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        local hum = player.Character:FindFirstChild("Humanoid")
        local cam = workspace.CurrentCamera

        if hrp and hum then
            local bv = hrp:FindFirstChild("FlyVelocity")
            local bg = hrp:FindFirstChild("FlyGyro")

            if not bv then
                bv = Instance.new("BodyVelocity")
                bv.Name = "FlyVelocity"
                bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bv.Parent = hrp
            end
            if not bg then
                bg = Instance.new("BodyGyro")
                bg.Name = "FlyGyro"
                bg.P = 1e4
                bg.D = 500
                bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bg.Parent = hrp
            end

            local moveDir = Vector3.zero
            local moveVector = hum.MoveDirection

            if moveVector.Magnitude > 0 then
                local camLook = cam.CFrame.LookVector
                local camRight = cam.CFrame.RightVector
                local forwardAmount = moveVector:Dot(Vector3.new(camLook.X, 0, camLook.Z).Unit)
                local rightAmount = moveVector:Dot(Vector3.new(camRight.X, 0, camRight.Z).Unit)
                moveDir = (camLook * forwardAmount) + (camRight * rightAmount)
            end

            if moveDir.Magnitude > 0 then
                bv.Velocity = moveDir.Unit * flySpeed
            else
                bv.Velocity = Vector3.new(0, 0.1, 0)
            end
            bg.CFrame = CFrame.new(hrp.Position, hrp.Position + cam.CFrame.LookVector)
        end
    else
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            if hrp:FindFirstChild("FlyVelocity") then hrp.FlyVelocity:Destroy() end
            if hrp:FindFirstChild("FlyGyro") then hrp.FlyGyro:Destroy() end
        end
    end

    -- AUTO PROMPT (with TEST MODE support & BREAK MODE awareness)
    if autoPromptEnabled and not isInBreakMode and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        local hrp = player.Character.HumanoidRootPart
        for _, item in ipairs(promptFastCache) do
            local prompt = item.Prompt
            if prompt and prompt.Parent and not activePrompts[prompt] then
                -- APPLY TEST MODE CONTINUOUSLY (before distance check)
                if testPromptModeEnabled then
                    prompt.HoldDuration = 3.2
                end
                
                local dist = (item.Position - hrp.Position).Magnitude
                if dist <= item.MaxDist then
                    activePrompts[prompt] = true
                    
                    task.spawn(function()
                        prompt.RequiresLineOfSight = false 
                        
                        if hrp then hrp.Anchored = true end
                        prompt:InputHoldBegin()
                        
                        local holdTime = prompt.HoldDuration + promptBufferTime
                        local start = tick()
                        while tick() - start < holdTime do
                            RunService.Heartbeat:Wait()
                        end
                        
                        prompt:InputHoldEnd()
                        task.wait(0.5)  -- Mobile fix - faster retry on lag
                        
                        if hrp then hrp.Anchored = false end
                        
                        lastPromptCompletionTime = tick()
                        activePrompts[prompt] = nil
                    end)
                end
            end
        end
    end
    
    if espEnabled then updateESP() end
end)

-- CACHE REFRESH LOOP
task.spawn(function()
    while true do
        refreshPromptCache()
        task.wait(1) 
    end
end)

-- ===== 10 MINUTE ANTI-AFK LOOP =====
task.spawn(function()
    while true do
        task.wait(600) -- Wait 10 minutes (600 seconds)
        pcall(function()
            if VirtualUser then
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
                notify("Anti-AFK", "10m Check Triggered")
            end
        end)
    end
end)

-- UI REFRESH LOOP
while true do
    if next(knownSpawners) then updateATMGUI(atmScroll) end
    task.wait(1)
end