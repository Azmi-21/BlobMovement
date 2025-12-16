--// Character Client Visuals
--// This script implements a custom character movement for the blobs

--// Constants
local DEATH_ANIM_TIME = 1.5
local ABSORB_ANIM_TIME = 1

--// Services
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--// players  refs
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

--// modules
local Components = require(game.ReplicatedStorage.components).new(Character)
local NumberSpinner = require(script.number_spinner)

local SkinsFolder = game.ReplicatedStorage.skins
local BlobTemplate = script.dome
local CircleTemplate = script.circle

--// Blob registry
-- blobs[player] = { character, { blob, circle, gui,points, name  } }
local Blobs = {}

-- base walk speed tracking per humanoid
local BaseWalkSpeeds = setmetatable({}, { __mode = "k" })

-- Utility
local function resizeOverhead(blob: BasePart, gui: BillboardGui, size: number)
	local width = (blob.Size.X + blob.Size.Z) / 2
	gui.Size = UDim2.new(1.25 * width, 0, 0.375 * width)
	gui.StudsOffset = Vector3.new(0, 0.85 * (size / 2), 0)
end

-- Detect slope and boost speed when going downhill
local function applySlopeAcceleration(humanoid: Humanoid, rootPart: BasePart, blob: BasePart, circle: BasePart)
	if not rootPart then return end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		local base = BaseWalkSpeeds[humanoid]
		if base then
			humanoid.WalkSpeed = base
		end
		return
	end

	local baseSpeed = BaseWalkSpeeds[humanoid]
	if not baseSpeed or baseSpeed <= 0 then
		baseSpeed = humanoid.WalkSpeed
		if baseSpeed <= 0 then
			baseSpeed = 16
		end
		BaseWalkSpeeds[humanoid] = baseSpeed
	end

	local offsetDist = 3
	local rayLength = 20
	local moveUnit = moveDir.Unit
	local offset = moveUnit * offsetDist

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { humanoid.Parent, blob, circle }

	local origin = rootPart.Position
	local down = Vector3.new(0, -rayLength, 0)

	local aheadResult = Workspace:Raycast(origin + offset, down, params)
	local behindResult = Workspace:Raycast(origin - offset, down, params)

	if not aheadResult or not behindResult then
		humanoid.WalkSpeed = baseSpeed
		return
	end

	local dh = behindResult.Position.Y - aheadResult.Position.Y
	local slope = dh / (2 * offsetDist)

	if slope > 0.01 then
		local downhillBoost = math.clamp(slope * 35, 0, 0.8)
		humanoid.WalkSpeed = baseSpeed * (1 + downhillBoost)
	else
		humanoid.WalkSpeed = baseSpeed
	end
end

-- Overhead UI
local function createOverhead(player: Player, blob: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Text = player.DisplayName
	name.TextScaled = true
	name.FontFace = Font.new(
		"rbxasset://fonts/families/SourceSansPro.json",
		Enum.FontWeight.Bold
	)
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.35
	name.TextStrokeColor3 = Color3.fromRGB(72, 72, 72)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0.5, 0)
	name.Size = UDim2.new(1, 0, 0.3, 0)
	name.Parent = gui

	local points = NumberSpinner.new()
	points.Parent = gui
	points.FontFace = Font.fromEnum(Enum.Font.Cartoon)
	points.Decimals = 0
	points.Duration = 0.5
	points.Commas = true
	points.TextScaled = true
	points.TextStrokeTransparency = 0.35
	points.TextStrokeColor3 = Color3.fromRGB(72, 72, 72)
	points.TextColor3 = Color3.fromRGB(255, 201, 94)
	points.Value = player.Character:GetAttribute("points")

	gui.Parent = player.Character:FindFirstChild("HumanoidRootPart")

	return gui, points, name
end

-- Blob Lifecycle
local function destroyBlob(player: Player)
	if not Blobs[player] then return end
	for _, inst in ipairs(Blobs[player][2]) do
		inst:Destroy()
	end
	Blobs[player] = nil
end

local function createBlob(player: Player, character: Model, size: number)
	destroyBlob(player)

	local blob = BlobTemplate:Clone()
	local circle = CircleTemplate:Clone()
	local skin = SkinsFolder:FindFirstChild(player:GetAttribute("skin"))

	blob.Size = Vector3.new(size, size / 2, size)
	blob.Anchored = true
	blob.CanCollide = false
	blob.CanTouch = false
	blob.CastShadow = false
	blob.Name = "blob"

	if skin then
		for _, item in ipairs(skin:GetChildren()) do
			item:Clone().Parent = blob
		end
	end

	if player == LocalPlayer then
		local highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillTransparency = 1
		highlight.Parent = blob
	end

	local gui, points, name = createOverhead(player, blob)

	blob.Parent = workspace
	circle.Parent = workspace

	Blobs[player] = {
		character,
		{ blob, circle, gui, points, name }
	}

	return blob
end

-- Death Animation
local function playDeathAnimation(blob: BasePart, circle: BasePart)
	if blob:HasTag("addressed_death") then return end
	blob:AddTag("addressed_death")

	local blobCopy = blob:Clone()
	local circleCopy = circle:Clone()
	local circleImage = circleCopy:FindFirstChildWhichIsA("ImageLabel", true)

	blob.Transparency = 1
	if circleImage then circleImage.ImageTransparency = 1 end

	blobCopy.Parent = workspace
	circleCopy.Parent = workspace

	TweenService:Create(
		blobCopy,
		TweenInfo.new(DEATH_ANIM_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{
			Position = blobCopy.Position - Vector3.new(0, blobCopy.Size.Y / 2, 0),
			Size = Vector3.new(blobCopy.Size.X * 1.5, 0, blobCopy.Size.Z * 1.5),
			Transparency = 1
		}
	):Play()

	task.delay(DEATH_ANIM_TIME, function()
		blobCopy:Destroy()
		circleCopy:Destroy()
	end)
end

-- Per Frame Update
Components.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
Components.humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

RunService.RenderStepped:Connect(function(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then continue end

		local size = Components:require("shared_functions"):get_size(character:GetAttribute("points"))

		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "blob" then
				part.Transparency = 1
			end
		end

		if not Blobs[player] and humanoid.Health > 0 then
			createBlob(player, character, size)
		end

		local entry = Blobs[player]
		if not entry then continue end

		local blob = entry[2][1]
		local circle = entry[2][2]
		local gui = entry[2][3]
		local points = entry[2][4]

		if humanoid.Health <= 0 then
			playDeathAnimation(blob, circle)
			continue
		end

		if player == LocalPlayer then
			Camera.CameraSubject = humanoid
		end

		local runTime = tick()
		local breathe = humanoid.MoveDirection.Magnitude > 0.1
			and math.sin(runTime * 10) * (size / 60) - (size / 30)
			or math.sin(runTime) * (size / 40)

		blob.Size = blob.Size:Lerp(
			Vector3.new(size - breathe, size / 2 + breathe, size - breathe),
			0.1
		)

		local rootPart = humanoid.RootPart
		if rootPart then
			blob.Position = rootPart.Position + Vector3.new(0, -3 + blob.Size.Y / 2, 0)
			circle.Position = rootPart.Position + Vector3.new(0, -3, 0)
		end

		if humanoid.MoveDirection.Magnitude > 0.2 then
			blob.CFrame = blob.CFrame:Lerp(
				CFrame.lookAlong(blob.Position, humanoid.MoveDirection),
				0.1
			)
		end

		-- slope-based acceleration (mainly affects local player's humanoid)
		if player == LocalPlayer and rootPart then
			applySlopeAcceleration(humanoid, rootPart, blob, circle)
		end

		resizeOverhead(blob, gui, size)
		points.Value = character:GetAttribute("points")
	end
end)

Players.PlayerRemoving:Connect(destroyBlob)
