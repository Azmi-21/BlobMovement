--// Character Client Visuals
-- Client-only visual replacement for characters using blob avatars

--// Constants
-- Centralized so animation pacing stays consistent across effects
local DEATH_ANIM_TIME = 1.5
local ABSORB_ANIM_TIME = 1

--// Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--// Player refs
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

--// Modules
-- Components provides shared character-related utilities (ex: size calculation)
local Components = require(game.ReplicatedStorage.components).new(Character)

-- Used to animate numeric changes instead of abrupt text updates
local NumberSpinner = require(script.number_spinner)

--// Assets
local SkinsFolder = game.ReplicatedStorage.skins
local BlobTemplate = script.dome
local CircleTemplate = script.circle

--// Active blob visuals per player
-- Stored to avoid recreating visuals every frame
-- blobs[player] = { character, { blob, circle, gui, points, name } }
local Blobs = {}

-- Tracks original WalkSpeed so slope boosts are reversible and non-stacking
local BaseWalkSpeeds = setmetatable({}, { __mode = "k" })

-- Scales overhead UI so it remains readable as blobs grow
local function resizeOverhead(blob: BasePart, gui: BillboardGui, size: number)
	local width = (blob.Size.X + blob.Size.Z) / 2
	gui.Size = UDim2.new(1.25 * width, 0, 0.375 * width)

	-- Offset tied to size to prevent clipping into the blob
	gui.StudsOffset = Vector3.new(0, 0.85 * (size / 2), 0)
end

-- Applies downhill-only acceleration without touching server movement logic
local function applySlopeAcceleration(humanoid: Humanoid, rootPart: BasePart, blob: BasePart, circle: BasePart)
	if not rootPart then return end

	local moveDir = humanoid.MoveDirection

	-- Restore base speed immediately when stopping
	if moveDir.Magnitude < 0.1 then
		local base = BaseWalkSpeeds[humanoid]
		if base then humanoid.WalkSpeed = base end
		return
	end

	-- Cache baseline speed once so boosts are always relative
	local baseSpeed = BaseWalkSpeeds[humanoid]
	if not baseSpeed or baseSpeed <= 0 then
		baseSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16
		BaseWalkSpeeds[humanoid] = baseSpeed
	end

	-- Raycast ahead vs behind to estimate terrain slope
	local offsetDist = 3
	local rayLength = 20
	local offset = moveDir.Unit * offsetDist

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { humanoid.Parent, blob, circle }

	local origin = rootPart.Position
	local down = Vector3.new(0, -rayLength, 0)

	local ahead = Workspace:Raycast(origin + offset, down, params)
	local behind = Workspace:Raycast(origin - offset, down, params)

	-- Fallback to base speed if slope data is unreliable
	if not ahead or not behind then
		humanoid.WalkSpeed = baseSpeed
		return
	end

	local slope = (behind.Position.Y - ahead.Position.Y) / (2 * offsetDist)

	if slope > 0.01 then
		-- Clamp boost to avoid uncontrollable downhill speeds
		local boost = math.clamp(slope * 35, 0, 0.8)
		humanoid.WalkSpeed = baseSpeed * (1 + boost)
	else
		humanoid.WalkSpeed = baseSpeed
	end
end

-- Creates name + points UI attached to blob
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
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.35
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0.5, 0)
	name.Size = UDim2.new(1, 0, 0.3, 0)
	name.Parent = gui

	-- Spinner makes point changes readable without UI spam
	local points = NumberSpinner.new()
	points.Parent = gui
	points.Decimals = 0
	points.Duration = 0.5
	points.Commas = true
	points.TextScaled = true
	points.TextStrokeTransparency = 0.35
	points.TextColor3 = Color3.fromRGB(255, 201, 94)

	-- Value pulled from attributes to stay server-authoritative
	points.Value = player.Character:GetAttribute("points")

	gui.Parent = player.Character:FindFirstChild("HumanoidRootPart")

	return gui, points, name
end

-- Removes all visuals associated with a player
local function destroyBlob(player: Player)
	if not Blobs[player] then return end
	for _, inst in ipairs(Blobs[player][2]) do
		inst:Destroy()
	end
	Blobs[player] = nil
end

local function createBlob(player: Player, character: Model, size: number)
	-- Destroy first to guarantee a clean visual state
	destroyBlob(player)

	local blob = BlobTemplate:Clone()
	local circle = CircleTemplate:Clone()
	local skin = SkinsFolder:FindFirstChild(player:GetAttribute("skin"))

	-- Anchored to avoid physics instability at large sizes
	blob.Size = Vector3.new(size, size / 2, size)
	blob.Anchored = true
	blob.CanCollide = false
	blob.CanTouch = false
	blob.CastShadow = false
	blob.Name = "blob"

	-- Skins applied locally so cosmetics never affect gameplay
	if skin then
		for _, item in ipairs(skin:GetChildren()) do
			item:Clone().Parent = blob
		end
	end

	-- Local highlight improves self-visibility in crowds
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

-- Plays squash/fade animation once per death
local function playDeathAnimation(blob: BasePart, circle: BasePart)
	if blob:HasTag("addressed_death") then return end
	blob:AddTag("addressed_death")

	-- Clone visuals so original can be hidden immediately
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

-- Disable humanoid states that conflict with blob visuals
Components.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
Components.humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

RunService.RenderStepped:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then continue end

		-- Size derived from points for deterministic growth
		local size = Components:require("shared_functions")
			:get_size(character:GetAttribute("points"))

		-- Hide default character so only blob is visible
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

		local blob, circle, gui, points =
			entry[2][1], entry[2][2], entry[2][3], entry[2][4]

		if humanoid.Health <= 0 then
			playDeathAnimation(blob, circle)
			continue
		end

		-- Keep default Roblox camera logic intact
		if player == LocalPlayer then
			Camera.CameraSubject = humanoid
		end

		-- Subtle squash/stretch for motion feedback
		local t = tick()
		local breathe = humanoid.MoveDirection.Magnitude > 0.1
			and math.sin(t * 10) * (size / 60) - (size / 30)
			or math.sin(t) * (size / 40)

		blob.Size = blob.Size:Lerp(
			Vector3.new(size - breathe, size / 2 + breathe, size - breathe),
			0.1
		)

		local rootPart = humanoid.RootPart
		if rootPart then
			blob.Position = rootPart.Position + Vector3.new(0, -3 + blob.Size.Y / 2, 0)
			circle.Position = rootPart.Position + Vector3.new(0, -3, 0)
		end

		-- Smooth orientation to avoid jitter
		if humanoid.MoveDirection.Magnitude > 0.2 then
			blob.CFrame = blob.CFrame:Lerp(
				CFrame.lookAlong(blob.Position, humanoid.MoveDirection),
				0.1
			)
		end

		-- Local-only slope boost to avoid replication issues
		if player == LocalPlayer and rootPart then
			applySlopeAcceleration(humanoid, rootPart, blob, circle)
		end

		resizeOverhead(blob, gui, size)
		points.Value = character:GetAttribute("points")
	end
end)

-- Ensure visuals never outlive the player
Players.PlayerRemoving:Connect(destroyBlob)
