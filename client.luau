-- idk why I made this but it’s handy for exploring
local player = game.Players.LocalPlayer
local runSrv = game:GetService("RunService")

local Gui = Instance.new("ScreenGui")
Gui.Name = "UI"
Gui.Parent = player:WaitForChild("PlayerGui")

local Label = Instance.new("TextLabel")
local Corner = Instance.new("UICorner")

Corner.Parent = Label
Corner.CornerRadius = UDim.new(0, 10)
Label.Size = UDim2.new(0, 200, 0, 30)
Label.Position = UDim2.new(0, 15, 0, 15)
Label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
Label.BackgroundTransparency = 0.25
Label.TextColor3 = Color3.new(1, 1, 1)
Label.Font = Enum.Font.FredokaOne
Label.TextScaled = true
Label.Text = "Loading coords..."
Label.Parent = Gui

runSrv.RenderStepped:Connect(function()
	local char = player.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local pos = root.Position
			Label.Text = string.format("X: %.1f | Y: %.1f | Z: %.1f", pos.X, pos.Y, pos.Z)
		end
	end
end)
