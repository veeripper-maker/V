local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local arcadeOrb = workspace.Events.ArcadeSpheres.ArcadeOrb

local function tweenToOrb(duration)
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    rootPart.Anchored = true 
    
    local tweenInfo = TweenInfo.new(
        duration or 0.5,
        Enum.EasingStyle.Sine, 
        Enum.EasingStyle.Out
    )
    
    local goal = {CFrame = arcadeOrb.CFrame}
    
    local tween = TweenService:Create(rootPart, tweenInfo, goal)
    
    tween:Play()

    tween.Completed:Connect(function()
        rootPart.Anchored = false
        print("Collected!")
    end)
end
task.wait(2) 
tweenToOrb(0.8)