--[[
	ADMIN MENU - SINGLE EXECUTABLE SCRIPT
	All-in-one: Server handlers + Client GUI
	J = Toggle GUI | Drag from title bar
	Execute with: loadstring(game:HttpGet('URL'))() or paste directly
]]

--=======================
-- PREVENT DOUBLE-EXEC
--=======================
if _G.AdminMenuLoaded then return end
_G.AdminMenuLoaded = true

--=======================
-- SERVICES
--=======================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

--=======================
-- REMOTE EVENT SETUP
--=======================
local remote = ReplicatedStorage:FindFirstChild("AdminRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "AdminRemote"
	remote.Parent = ReplicatedStorage
end

--=======================
-- SERVER-SIDE HANDLERS (if running on server or executor with server access)
--=======================
pcall(function()
	local TeleportService = game:GetService("TeleportService")
	local chatTags = {}

	remote.OnServerEvent:Connect(function(plr, action, ...)
		local args = {...}

		if action == "Fling" then
			local target = args[1]
			if typeof(target) == "Instance" and target:IsA("Player") and target.Character then
				local hrp = target.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
					-- Take network ownership on server so velocity changes actually take effect
					pcall(function() hrp:SetNetworkOwner(nil) end)

					-- Apply strong initial velocity
					local dir = Vector3.new(
						math.random(-3000, 3000), math.random(2000, 5000), math.random(-3000, 3000))
					hrp.AssemblyLinearVelocity = dir
					hrp.AssemblyAngularVelocity = Vector3.new(
						math.random(-50, 50), math.random(-50, 50), math.random(-50, 50))

					-- Sustained force via BodyVelocity so the fling isn't instantly cancelled by the client physics
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(1e8, 1e8, 1e8)
					bv.Velocity = dir
					bv.Parent = hrp
					game:GetService("Debris"):AddItem(bv, 0.5)

					-- Give network ownership back after the fling
					task.delay(1, function()
						pcall(function() hrp:SetNetworkOwner(target) end)
					end)
				end
			end

		elseif action == "TeleportToPlayer" then
			local target = args[1]
			if typeof(target) == "Instance" and target:IsA("Player") and target.Character and plr.Character then
				local tHrp = target.Character:FindFirstChild("HumanoidRootPart")
				local pHrp = plr.Character:FindFirstChild("HumanoidRootPart")
				if tHrp and pHrp then
					pHrp.CFrame = tHrp.CFrame * CFrame.new(0, 0, 5)
				end
			end

		elseif action == "ServerHop" then
			pcall(function()
				TeleportService:Teleport(game.PlaceId, plr)
			end)

		elseif action == "SetChatTag" then
			if typeof(args[1]) == "string" then
				chatTags[plr.UserId] = args[1]
				plr:SetAttribute("ChatTagColor", args[1])
			end

		elseif action == "PlayEmote" then
			if typeof(args[1]) == "number" and plr.Character then
				local hum = plr.Character:FindFirstChildOfClass("Humanoid")
				local anim = hum and hum:FindFirstChildOfClass("Animator")
				if anim then
					local a = Instance.new("Animation")
					a.AnimationId = "rbxassetid://" .. tostring(args[1])
					local track = anim:LoadAnimation(a)
					track:Play()
					a:Destroy()
				end
			end

		elseif action == "GetServerInfo" then
			remote:FireClient(plr, "ServerInfo", {
				placeId = game.PlaceId,
				jobId = game.JobId,
				playerCount = #Players:GetPlayers(),
				uptime = workspace.DistributedGameTime,
			})
		end
	end)

	-- Chat tag system (server-side OnIncomingMessage)
	if TextChatService then
		local tagHex = {
			green="#00FF00", red="#FF0000", blue="#0000FF",
			yellow="#FFFF00", purple="#9400D3", orange="#FF7F00",
			white="#FFFFFF", pink="#FF69B4",
		}
		TextChatService.OnIncomingMessage = function(msg)
			local src = msg.TextSource
			if not src then return end
			local p = Players:GetPlayerByUserId(src.UserId)
			if not p then return end
			local color = p:GetAttribute("ChatTagColor")
			if not color or color == "none" then return end
			local props = Instance.new("TextChatMessageProperties")
			if color == "rainbow" then
				props.PrefixText = '<font color="#FF0000">[</font><font color="#FF7F00">A</font><font color="#FFFF00">D</font><font color="#00FF00">M</font><font color="#0000FF">I</font><font color="#9400D3">]</font> ' .. msg.PrefixText
			else
				local hex = tagHex[color]
				if hex then
					props.PrefixText = string.format('<font color="%s">[ADMIN]</font> %s', hex, msg.PrefixText)
				else return end
			end
			return props
		end
	end
end)

--=======================
-- CLIENT-SIDE HELPERS
--=======================
-- Fling a player (client-side)
-- If target is self, directly set velocity. If target is another player, use body-ram technique
-- since we don't have network ownership of their character.
local function flingPlayer(target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then return end

	-- Fling self: we have network ownership, so direct velocity works
	if target == player then
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.AssemblyLinearVelocity = Vector3.new(
					math.random(-3000, 3000), math.random(2000, 5000), math.random(-3000, 3000))
				hrp.AssemblyAngularVelocity = Vector3.new(
					math.random(-50, 50), math.random(-50, 50), math.random(-50, 50))
			end
		end
		return
	end

	-- Fling another player: use body-ram technique
	-- Store our position, ram our character into theirs at high speed, then return
	local myChar = player.Character
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local targetChar = target.Character
	local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")

	if not myHrp or not targetHrp then return end

	local savedCFrame = myHrp.CFrame
	local flingDir = Vector3.new(
		math.random(-1, 1), 0, math.random(-1, 1))
	if flingDir.Magnitude == 0 then flingDir = Vector3.new(0, 0, -1) end
	flingDir = flingDir.Unit

	-- Ram into target multiple times from different angles
	task.spawn(function()
		for i = 1, 5 do
			local offset = CFrame.new(
				flingDir.X * (10 - i * 2),
				0,
				flingDir.Z * (10 - i * 2)
			) * CFrame.Angles(0, math.rad(i * 72), 0)
			myHrp.CFrame = targetHrp.CFrame * offset
			myHrp.AssemblyLinearVelocity = flingDir * 2000 + Vector3.new(0, 1000, 0)
			task.wait(0.05)
		end
		-- Return to original position
		task.wait(0.1)
		myHrp.CFrame = savedCFrame
		myHrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
end

-- Teleport self to a player (client-side)
local function teleportToPlayer(target)
	if typeof(target) == "Instance" and target:IsA("Player") and target.Character and player.Character then
		local tHrp = target.Character:FindFirstChild("HumanoidRootPart")
		local pHrp = player.Character:FindFirstChild("HumanoidRootPart")
		if tHrp and pHrp then
			pHrp.CFrame = tHrp.CFrame * CFrame.new(0, 0, 5)
		end
	end
end

-- Play emote on own character (client-side)
local function playEmote(animId)
	if typeof(animId) == "number" and player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		local anim = hum and hum:FindFirstChildOfClass("Animator")
		if anim then
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. tostring(animId)
			local track = anim:LoadAnimation(a)
			track:Play()
			a:Destroy()
		end
	end
end

-- Server hop (client-side attempt)
local function serverHop()
	pcall(function()
		local TeleportService = game:GetService("TeleportService")
		TeleportService:Teleport(game.PlaceId, player)
	end)
end

--=======================
-- STATE
--=======================
local guiVisible = true
local currentTab = "HOME"
local espEnabled = false
local hitboxEnabled = false
local touchFlingEnabled = false
local jumpBoostActive = false
local speedBoostActive = false
local selectedTarget = nil
local savedHomePos = nil
local chatTagEnabled = false
local espObjects = {}
local hitboxObjects = {}

--=======================
-- THEME
--=======================
local C_BG = Color3.fromRGB(38, 20, 68)
local C_SIDEBAR = Color3.fromRGB(28, 14, 52)
local C_BTN = Color3.fromRGB(55, 30, 95)
local C_BTN_HOVER = Color3.fromRGB(75, 40, 130)
local C_BTN_ACTIVE = Color3.fromRGB(105, 55, 175)
local C_TEXT = Color3.fromRGB(255, 255, 255)
local C_CONTENT = Color3.fromRGB(33, 17, 62)
local C_SCROLL = Color3.fromRGB(24, 11, 44)
local C_ACCENT = Color3.fromRGB(135, 72, 220)
local C_DIM = Color3.fromRGB(180, 180, 200)

--=======================
-- HELPERS
--=======================
local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
	return c
end

local function makeLabel(parent, text, size, pos, color, ts)
	local l = Instance.new("TextLabel")
	l.Size = size or UDim2.new(1, -20, 0, 28)
	l.Position = pos or UDim2.new(0, 10, 0, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or C_TEXT
	l.Font = Enum.Font.GothamMedium
	l.TextSize = ts or 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function makeSection(parent, text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 0, 32)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = C_ACCENT
	l.Font = Enum.Font.GothamBold
	l.TextSize = 18
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent

	local under = Instance.new("Frame")
	under.Size = UDim2.new(1, -10, 0, 2)
	under.Position = UDim2.new(0, 0, 1, -2)
	under.BackgroundColor3 = C_ACCENT
	under.BackgroundTransparency = 0.4
	under.BorderSizePixel = 0
	under.Parent = l
	return l
end

local function makeButton(parent, text, size, pos, color)
	local b = Instance.new("TextButton")
	b.Size = size or UDim2.new(1, -20, 0, 36)
	b.Position = pos or UDim2.new(0, 10, 0, 0)
	b.BackgroundColor3 = color or C_BTN
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = C_TEXT
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.Parent = parent
	corner(b, 6)

	b.MouseEnter:Connect(function() b.BackgroundColor3 = C_BTN_HOVER end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = color or C_BTN end)
	return b
end

local function makeInfo(parent, text)
	local l = makeLabel(parent, text, UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 0, 0), C_DIM, 12)
	return l
end

local function makeSpacer(parent, h)
	local s = Instance.new("Frame")
	s.Size = UDim2.new(1, -20, 0, h or 10)
	s.BackgroundTransparency = 1
	s.Parent = parent
	return s
end

-- Keybind system
local allKeybinds = {}

local function makeKeybind(parent, onToggle)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 140, 0, 34)
	btn.BackgroundColor3 = C_BTN
	btn.BorderSizePixel = 0
	btn.Text = "Click to bind"
	btn.TextColor3 = C_TEXT
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 14
	btn.Parent = parent
	corner(btn, 6)

	local bind = {key = nil, active = false, btn = btn, listening = false, onToggle = onToggle}
	table.insert(allKeybinds, bind)

	btn.MouseButton1Click:Connect(function()
		bind.listening = true
		btn.Text = "Press key..."
		btn.BackgroundColor3 = C_BTN_ACTIVE
	end)
	btn.MouseEnter:Connect(function() if not bind.listening then btn.BackgroundColor3 = C_BTN_HOVER end end)
	btn.MouseLeave:Connect(function() if not bind.listening then btn.BackgroundColor3 = C_BTN end end)
	return btn, bind
end

-- Slider system
local function makeSlider(parent, minVal, maxVal, default)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, -20, 0, 50)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local valLabel = Instance.new("TextLabel")
	valLabel.Size = UDim2.new(0, 50, 0, 20)
	valLabel.Position = UDim2.new(1, -50, 0, 0)
	valLabel.BackgroundTransparency = 1
	valLabel.Text = tostring(default)
	valLabel.TextColor3 = C_TEXT
	valLabel.Font = Enum.Font.GothamBold
	valLabel.TextSize = 14
	valLabel.TextXAlignment = Enum.TextXAlignment.Right
	valLabel.Parent = container

	local minMax = Instance.new("TextLabel")
	minMax.Size = UDim2.new(0, 100, 0, 20)
	minMax.BackgroundTransparency = 1
	minMax.Text = minVal .. " - " .. maxVal
	minMax.TextColor3 = C_DIM
	minMax.Font = Enum.Font.GothamMedium
	minMax.TextSize = 11
	minMax.TextXAlignment = Enum.TextXAlignment.Left
	minMax.Parent = container

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 6)
	bar.Position = UDim2.new(0, 0, 0, 28)
	bar.BackgroundColor3 = Color3.fromRGB(20, 10, 40)
	bar.BorderSizePixel = 0
	bar.Parent = container
	corner(bar, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new((default - minVal) / (maxVal - minVal), 0, 1, 0)
	fill.BackgroundColor3 = C_ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = bar
	corner(fill, 3)

	local handle = Instance.new("Frame")
	handle.Size = UDim2.new(0, 16, 0, 16)
	handle.Position = UDim2.new(fill.Size.X.Scale, -8, 0.5, -8)
	handle.BackgroundColor3 = C_TEXT
	handle.BorderSizePixel = 0
	handle.Parent = bar
	corner(handle, 8)

	local value = default
	local dragging = false

	local function update(input)
		local mx = input.Position.X
		local left = bar.AbsolutePosition.X
		local w = bar.AbsoluteSize.X
		local pct = math.clamp((mx - left) / w, 0, 1)
		value = math.floor(minVal + (maxVal - minVal) * pct)
		fill.Size = UDim2.new(pct, 0, 1, 0)
		handle.Position = UDim2.new(pct, -8, 0.5, -8)
		valLabel.Text = tostring(value)
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			update(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then update(input) end
	end)

	return container, function() return value end
end

--=======================
-- BUILD GUI
--=======================
-- Remove old GUI if exists
local oldGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("AdminMenu")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdminMenu"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Main Frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 560, 0, 380)
mainFrame.Position = UDim2.new(0.5, -280, 0.5, -190)
mainFrame.BackgroundColor3 = C_BG
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui
corner(mainFrame, 10)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(120, 60, 200)
mainStroke.Thickness = 1.5
mainStroke.Parent = mainFrame

-- Title bar
local titleBar = Instance.new("TextLabel")
titleBar.Size = UDim2.new(1, -20, 0, 32)
titleBar.Position = UDim2.new(0, 10, 0, 5)
titleBar.BackgroundTransparency = 1
titleBar.Text = "ADMIN MENU"
titleBar.TextColor3 = C_TEXT
titleBar.Font = Enum.Font.GothamBold
titleBar.TextSize = 18
titleBar.TextXAlignment = Enum.TextXAlignment.Center
titleBar.Parent = mainFrame

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 140, 1, -52)
sidebar.Position = UDim2.new(0, 10, 0, 42)
sidebar.BackgroundColor3 = C_SIDEBAR
sidebar.BorderSizePixel = 0
sidebar.Parent = mainFrame
corner(sidebar, 8)

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.Padding = UDim.new(0, 8)
sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sidebarLayout.VerticalAlignment = Enum.VerticalAlignment.Top
sidebarLayout.Parent = sidebar

local sidebarPad = Instance.new("UIPadding")
sidebarPad.PaddingTop = UDim.new(0, 10)
sidebarPad.PaddingLeft = UDim.new(0, 8)
sidebarPad.PaddingRight = UDim.new(0, 8)
sidebarPad.Parent = sidebar

-- Tab buttons
local tabButtons = {}
local tabs = {"HOME", "PLAYER", "MAIN", "ESP"}

for _, tabName in ipairs(tabs) do
	local btn = Instance.new("TextButton")
	btn.Name = tabName
	btn.Size = UDim2.new(1, 0, 0, 44)
	btn.BackgroundColor3 = C_BTN
	btn.BorderSizePixel = 0
	btn.Text = tabName
	btn.TextColor3 = C_TEXT
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 16
	btn.Parent = sidebar
	corner(btn, 6)
	btn.MouseEnter:Connect(function() btn.BackgroundColor3 = C_BTN_HOVER end)
	btn.MouseLeave:Connect(function()
		if currentTab ~= tabName then btn.BackgroundColor3 = C_BTN end
	end)
	tabButtons[tabName] = btn
end

-- Content area
local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -165, 1, -52)
contentArea.Position = UDim2.new(0, 155, 0, 42)
contentArea.BackgroundTransparency = 1
contentArea.ClipsDescendants = true
contentArea.Parent = mainFrame

--=======================
-- PANEL CREATION
--=======================
local panels = {}

local function makePanel(name)
	local p = Instance.new("ScrollingFrame")
	p.Size = UDim2.new(1, 0, 1, 0)
	p.Position = UDim2.new(0, 0, 0, 0)
	p.BackgroundTransparency = 1
	p.ScrollBarThickness = 4
	p.ScrollBarImageColor3 = C_ACCENT
	p.CanvasSize = UDim2.new(0, 0, 0, 0)
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.Visible = false
	p.Parent = contentArea

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = p

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = p

	panels[name] = p
	return p
end

--=======================
-- ESP PANEL
--=======================
local espPanel = makePanel("ESP")

makeSection(espPanel, "ESP TOGGLE")
makeInfo(espPanel, "Bind a key to toggle ESP (player names & health)")
local _, espBind = makeKeybind(espPanel, function(active)
	espEnabled = active
end)
makeSpacer(espPanel)

makeSection(espPanel, "HITBOX")
makeInfo(espPanel, "Bind a key to toggle hitbox visualization")
local _, hitboxBind = makeKeybind(espPanel, function(active)
	hitboxEnabled = active
end)

--=======================
-- HOME PANEL
--=======================
local homePanel = makePanel("HOME")

makeSection(homePanel, "FLING")
makeInfo(homePanel, "Bind a key to toggle touch fling (fling on touch)")
local _, flingBind = makeKeybind(homePanel, function(active)
	touchFlingEnabled = active
end)
makeSpacer(homePanel)

makeSection(homePanel, "ACTIONS")
local flingSelfBtn = makeButton(homePanel, "FLING SELF")
flingSelfBtn.MouseButton1Click:Connect(function()
	flingPlayer(player)
end)
local flingTargetBtn = makeButton(homePanel, "FLING TARGET")
flingTargetBtn.MouseButton1Click:Connect(function()
	if selectedTarget then
		-- Try server first, fallback to client
		pcall(function() remote:FireServer("Fling", selectedTarget) end)
		flingPlayer(selectedTarget)
	end
end)
local tpToPlayerBtn = makeButton(homePanel, "TP TO PLAYER")
tpToPlayerBtn.MouseButton1Click:Connect(function()
	if selectedTarget then
		-- Try server first, fallback to client
		pcall(function() remote:FireServer("TeleportToPlayer", selectedTarget) end)
		teleportToPlayer(selectedTarget)
	end
end)
makeSpacer(homePanel)

makeSection(homePanel, "TARGET")
local targetLabel = makeLabel(homePanel, "Target: None", UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 0, 0), Color3.fromRGB(200, 200, 100), 13)
local openTargetBtn = makeButton(homePanel, "SELECT TARGET")
makeSpacer(homePanel)

makeSection(homePanel, "CREATE HOME")
local createHomeBtn = makeButton(homePanel, "CREATE HOME")
local tpHomeBtn = makeButton(homePanel, "TP HOME")
createHomeBtn.MouseButton1Click:Connect(function()
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then savedHomePos = hrp.CFrame end
	end
end)
tpHomeBtn.MouseButton1Click:Connect(function()
	if savedHomePos then
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = savedHomePos end
		end
	end
end)
makeSpacer(homePanel)

--=======================
-- MAIN PANEL
--=======================
local mainPanel = makePanel("MAIN")

makeSection(mainPanel, "PLAYERSTATS")
local statsLabel = makeLabel(mainPanel, "Loading...", UDim2.new(1, -20, 0, 80), UDim2.new(0, 10, 0, 0), C_TEXT, 13)
statsLabel.TextWrapped = true
statsLabel.TextYAlignment = Enum.TextYAlignment.Top

-- Listen for server info response
remote.OnClientEvent:Connect(function(action, data)
	if action == "ServerInfo" then
		statsLabel.Text = string.format(
			"Place ID: %d\nJob ID: %s\nPlayers: %d\nUptime: %.0f seconds",
			data.placeId or 0, data.jobId or "N/A", data.playerCount or 0, data.uptime or 0)
	end
end)

-- Also show client-side info immediately
task.spawn(function()
	task.wait(1)
	if statsLabel.Text == "Loading..." then
		statsLabel.Text = string.format(
			"Place ID: %d\nJob ID: %s\nPlayers: %d\nUptime: %.0f seconds",
			game.PlaceId, game.JobId or "N/A", #Players:GetPlayers(), workspace.DistributedGameTime)
	end
end)

-- Request server info
pcall(function() remote:FireServer("GetServerInfo") end)
makeSpacer(mainPanel)

makeSection(mainPanel, "CHAT")
makeInfo(mainPanel, "Toggle chat tag and select a color:")
local chatTagBtn = makeButton(mainPanel, "CHAT TAG: OFF")

local colorContainer = Instance.new("Frame")
colorContainer.Size = UDim2.new(1, -20, 0, 32)
colorContainer.BackgroundTransparency = 1
colorContainer.Parent = mainPanel

local colorLayout = Instance.new("UIListLayout")
colorLayout.FillDirection = Enum.FillDirection.Horizontal
colorLayout.Padding = UDim.new(0, 5)
colorLayout.Parent = colorContainer

local chatColors = {
	{name="Rainbow", c="rainbow"}, {name="Green", c="green"}, {name="Red", c="red"},
	{name="Blue", c="blue"}, {name="Yellow", c="yellow"}, {name="Purple", c="purple"},
}
local colorBtns = {}
for _, col in ipairs(chatColors) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 58, 1, 0)
	btn.BackgroundColor3 = C_BTN
	btn.BorderSizePixel = 0
	btn.Text = col.name
	btn.TextColor3 = C_TEXT
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 11
	btn.Parent = colorContainer
	corner(btn, 4)
	btn.MouseButton1Click:Connect(function()
		if chatTagEnabled then
			pcall(function() remote:FireServer("SetChatTag", col.c) end)
			player:SetAttribute("ChatTagColor", col.c)
			for _, b in ipairs(colorBtns) do b.BackgroundColor3 = C_BTN end
			btn.BackgroundColor3 = C_BTN_ACTIVE
		end
	end)
	btn.MouseEnter:Connect(function() btn.BackgroundColor3 = C_BTN_HOVER end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = C_BTN
	end)
	table.insert(colorBtns, btn)
end

chatTagBtn.MouseButton1Click:Connect(function()
	chatTagEnabled = not chatTagEnabled
	if chatTagEnabled then
		chatTagBtn.Text = "CHAT TAG: ON"
		chatTagBtn.BackgroundColor3 = C_BTN_ACTIVE
		pcall(function() remote:FireServer("SetChatTag", "green") end)
		player:SetAttribute("ChatTagColor", "green")
		for _, b in ipairs(colorBtns) do b.BackgroundColor3 = C_BTN end
		colorBtns[2].BackgroundColor3 = C_BTN_ACTIVE
	else
		chatTagBtn.Text = "CHAT TAG: OFF"
		chatTagBtn.BackgroundColor3 = C_BTN
		pcall(function() remote:FireServer("SetChatTag", "none") end)
		player:SetAttribute("ChatTagColor", "none")
		for _, b in ipairs(colorBtns) do b.BackgroundColor3 = C_BTN end
	end
end)
makeSpacer(mainPanel)

makeSection(mainPanel, "SERVER HOP")
local serverHopBtn = makeButton(mainPanel, "SERVER HOP")
serverHopBtn.MouseButton1Click:Connect(function()
	serverHop()
end)
makeSpacer(mainPanel)

makeSection(mainPanel, "EMOTES")
local openEmotesBtn = makeButton(mainPanel, "OPEN EMOTES")
makeSpacer(mainPanel)

makeSection(mainPanel, "AVATAR")
local viewport = Instance.new("ViewportFrame")
viewport.Size = UDim2.new(0, 100, 0, 150)
viewport.BackgroundColor3 = C_SCROLL
viewport.BorderSizePixel = 0
viewport.Parent = mainPanel
corner(viewport, 6)

local refreshAvatarBtn = makeButton(mainPanel, "Refresh Avatar", UDim2.new(0, 140, 0, 30))

local function updateAvatar()
	for _, c in ipairs(viewport:GetChildren()) do c:Destroy() end
	local char = player.Character
	if not char then return end
	char.Archivable = true
	local clone = char:Clone()
	if not clone then return end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end
	clone.Parent = viewport
	local cam = Instance.new("Camera")
	cam.CFrame = CFrame.new(Vector3.new(0, 3, 6), Vector3.new(0, 2, 0))
	viewport.CurrentCamera = cam
	cam.Parent = viewport
	pcall(function() clone:PivotTo(CFrame.new(0, -2, 0)) end)
end
refreshAvatarBtn.MouseButton1Click:Connect(updateAvatar)
task.spawn(function() task.wait(2); updateAvatar() end)

-- EMOTES POPUP
local emotesPopup = Instance.new("Frame")
emotesPopup.Size = UDim2.new(1, 0, 1, 0)
emotesPopup.BackgroundColor3 = C_CONTENT
emotesPopup.Visible = false
emotesPopup.ZIndex = 10
emotesPopup.Parent = contentArea
corner(emotesPopup, 8)

local emotesTitle = Instance.new("TextLabel")
emotesTitle.Size = UDim2.new(1, -50, 0, 30)
emotesTitle.Position = UDim2.new(0, 10, 0, 5)
emotesTitle.BackgroundTransparency = 1
emotesTitle.Text = "EMOTES"
emotesTitle.TextColor3 = C_ACCENT
emotesTitle.Font = Enum.Font.GothamBold
emotesTitle.TextSize = 18
emotesTitle.TextXAlignment = Enum.TextXAlignment.Left
emotesTitle.ZIndex = 11
emotesTitle.Parent = emotesPopup

local emotesClose = Instance.new("TextButton")
emotesClose.Size = UDim2.new(0, 30, 0, 30)
emotesClose.Position = UDim2.new(1, -35, 0, 5)
emotesClose.BackgroundColor3 = C_BTN
emotesClose.BorderSizePixel = 0
emotesClose.Text = "X"
emotesClose.TextColor3 = C_TEXT
emotesClose.Font = Enum.Font.GothamBold
emotesClose.TextSize = 14
emotesClose.ZIndex = 11
emotesClose.Parent = emotesPopup
corner(emotesClose, 6)

local emotesScroll = Instance.new("ScrollingFrame")
emotesScroll.Size = UDim2.new(1, -20, 1, -50)
emotesScroll.Position = UDim2.new(0, 10, 0, 40)
emotesScroll.BackgroundTransparency = 1
emotesScroll.ScrollBarThickness = 4
emotesScroll.ScrollBarImageColor3 = C_ACCENT
emotesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
emotesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
emotesScroll.ZIndex = 11
emotesScroll.Parent = emotesPopup

local emotesLayout = Instance.new("UIListLayout")
emotesLayout.Padding = UDim.new(0, 6)
emotesLayout.Parent = emotesScroll

local emotesList = {
	{name="Wave", id=507770239}, {name="Point", id=507770453},
	{name="Cheer", id=507770669}, {name="Laugh", id=507770818},
	{name="Dance", id=507770677}, {name="Dance 2", id=507770773},
	{name="Dance 3", id=507771060},
}
for _, emote in ipairs(emotesList) do
	local eb = makeButton(emotesScroll, emote.name, UDim2.new(1, 0, 0, 32))
	eb.MouseButton1Click:Connect(function()
		-- Try server first, fallback to client
		pcall(function() remote:FireServer("PlayEmote", emote.id) end)
		playEmote(emote.id)
	end)
end

openEmotesBtn.MouseButton1Click:Connect(function() emotesPopup.Visible = true end)
emotesClose.MouseButton1Click:Connect(function() emotesPopup.Visible = false end)

-- TARGET POPUP
local targetPopup = Instance.new("Frame")
targetPopup.Size = UDim2.new(1, 0, 1, 0)
targetPopup.BackgroundColor3 = C_CONTENT
targetPopup.Visible = false
targetPopup.ZIndex = 10
targetPopup.Parent = contentArea
corner(targetPopup, 8)

local targetPopupTitle = Instance.new("TextLabel")
targetPopupTitle.Size = UDim2.new(1, -50, 0, 30)
targetPopupTitle.Position = UDim2.new(0, 10, 0, 5)
targetPopupTitle.BackgroundTransparency = 1
targetPopupTitle.Text = "SELECT TARGET"
targetPopupTitle.TextColor3 = C_ACCENT
targetPopupTitle.Font = Enum.Font.GothamBold
targetPopupTitle.TextSize = 18
targetPopupTitle.TextXAlignment = Enum.TextXAlignment.Left
targetPopupTitle.ZIndex = 11
targetPopupTitle.Parent = targetPopup

local targetPopupClose = Instance.new("TextButton")
targetPopupClose.Size = UDim2.new(0, 30, 0, 30)
targetPopupClose.Position = UDim2.new(1, -35, 0, 5)
targetPopupClose.BackgroundColor3 = C_BTN
targetPopupClose.BorderSizePixel = 0
targetPopupClose.Text = "X"
targetPopupClose.TextColor3 = C_TEXT
targetPopupClose.Font = Enum.Font.GothamBold
targetPopupClose.TextSize = 14
targetPopupClose.ZIndex = 11
targetPopupClose.Parent = targetPopup
corner(targetPopupClose, 6)

local targetPopupScroll = Instance.new("ScrollingFrame")
targetPopupScroll.Size = UDim2.new(1, -20, 1, -50)
targetPopupScroll.Position = UDim2.new(0, 10, 0, 40)
targetPopupScroll.BackgroundTransparency = 1
targetPopupScroll.ScrollBarThickness = 4
targetPopupScroll.ScrollBarImageColor3 = C_ACCENT
targetPopupScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
targetPopupScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
targetPopupScroll.ZIndex = 11
targetPopupScroll.Parent = targetPopup

local targetPopupLayout = Instance.new("UIListLayout")
targetPopupLayout.Padding = UDim.new(0, 6)
targetPopupLayout.Parent = targetPopupScroll

local function refreshTargetPopup()
	for _, c in ipairs(targetPopupScroll:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local entry = Instance.new("TextButton")
			entry.Size = UDim2.new(1, 0, 0, 32)
			entry.BackgroundColor3 = (selectedTarget == p) and C_BTN_ACTIVE or C_BTN
			entry.BorderSizePixel = 0
			entry.Text = p.Name .. (selectedTarget == p and " [SELECTED]" or "")
			entry.TextColor3 = C_TEXT
			entry.Font = Enum.Font.GothamMedium
			entry.TextSize = 14
			entry.ZIndex = 11
			entry.Parent = targetPopupScroll
			corner(entry, 4)
			entry.MouseButton1Click:Connect(function()
				selectedTarget = p
				refreshTargetPopup()
				targetPopup.Visible = false
			end)
			entry.MouseEnter:Connect(function() entry.BackgroundColor3 = C_BTN_HOVER end)
			entry.MouseLeave:Connect(function() entry.BackgroundColor3 = (selectedTarget == p) and C_BTN_ACTIVE or C_BTN end)
		end
	end
end

openTargetBtn.MouseButton1Click:Connect(function()
	refreshTargetPopup()
	targetPopup.Visible = true
end)
targetPopupClose.MouseButton1Click:Connect(function() targetPopup.Visible = false end)

--=======================
-- PLAYER PANEL
--=======================
local plrPanel = makePanel("PLAYER")

makeSection(plrPanel, "JUMPBOOST")
local jumpSlider, getJumpVal = makeSlider(plrPanel, 1, 100, 50)
local jumpBtn = makeButton(plrPanel, "ACTIVATE")
jumpBtn.MouseButton1Click:Connect(function()
	jumpBoostActive = not jumpBoostActive
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if jumpBoostActive then
		jumpBtn.Text = "DEACTIVATE"
		jumpBtn.BackgroundColor3 = C_BTN_ACTIVE
		if hum then hum.JumpHeight = 7.2 + (getJumpVal() / 100) * 20 end
	else
		jumpBtn.Text = "ACTIVATE"
		jumpBtn.BackgroundColor3 = C_BTN
		if hum then hum.JumpHeight = 7.2 end
	end
end)
makeSpacer(plrPanel)

makeSection(plrPanel, "SPEEDBOOST")
local speedSlider, getSpeedVal = makeSlider(plrPanel, 1, 500, 100)
local speedBtn = makeButton(plrPanel, "ACTIVATE")
speedBtn.MouseButton1Click:Connect(function()
	speedBoostActive = not speedBoostActive
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if speedBoostActive then
		speedBtn.Text = "DEACTIVATE"
		speedBtn.BackgroundColor3 = C_BTN_ACTIVE
		if hum then hum.WalkSpeed = 16 + getSpeedVal() end
	else
		speedBtn.Text = "ACTIVATE"
		speedBtn.BackgroundColor3 = C_BTN
		if hum then hum.WalkSpeed = 16 end
	end
end)
makeSpacer(plrPanel)

makeSection(plrPanel, "SCRIPTS")
local scriptsScroll = Instance.new("ScrollingFrame")
scriptsScroll.Size = UDim2.new(1, -20, 0, 160)
scriptsScroll.BackgroundColor3 = C_SCROLL
scriptsScroll.BorderSizePixel = 0
scriptsScroll.ScrollBarThickness = 4
scriptsScroll.ScrollBarImageColor3 = C_ACCENT
scriptsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scriptsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scriptsScroll.Parent = plrPanel
corner(scriptsScroll, 6)

local scriptsLayout = Instance.new("UIListLayout")
scriptsLayout.Padding = UDim.new(0, 6)
scriptsLayout.Parent = scriptsScroll
local scriptsPad = Instance.new("UIPadding")
scriptsPad.PaddingTop = UDim.new(0, 8)
scriptsPad.PaddingLeft = UDim.new(0, 8)
scriptsPad.PaddingRight = UDim.new(0, 8)
scriptsPad.PaddingBottom = UDim.new(0, 8)
scriptsPad.Parent = scriptsScroll

local scriptEntries = {
	{name="MM2", status="available"},
	{name="BRAIN LSPD", status="available"},
	{name="MIC UP", status="coming_soon"},
}
for _, entry in ipairs(scriptEntries) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundTransparency = 1
	row.Parent = scriptsScroll

	local nl = Instance.new("TextLabel")
	nl.Size = UDim2.new(0, 150, 1, 0)
	nl.BackgroundTransparency = 1
	nl.Text = entry.name
	nl.TextColor3 = C_TEXT
	nl.Font = Enum.Font.GothamMedium
	nl.TextSize = 14
	nl.TextXAlignment = Enum.TextXAlignment.Left
	nl.Parent = row

	if entry.status == "available" then
		local eb = Instance.new("TextButton")
		eb.Size = UDim2.new(0, 80, 1, -4)
		eb.Position = UDim2.new(1, -85, 0, 2)
		eb.BackgroundColor3 = C_BTN
		eb.BorderSizePixel = 0
		eb.Text = "Execute"
		eb.TextColor3 = C_TEXT
		eb.Font = Enum.Font.GothamMedium
		eb.TextSize = 13
		eb.Parent = row
		corner(eb, 4)
		eb.MouseButton1Click:Connect(function() print("Execute: " .. entry.name) end)
		eb.MouseEnter:Connect(function() eb.BackgroundColor3 = C_BTN_HOVER end)
		eb.MouseLeave:Connect(function() eb.BackgroundColor3 = C_BTN end)
	else
		local sl = Instance.new("TextLabel")
		sl.Size = UDim2.new(0, 100, 1, 0)
		sl.Position = UDim2.new(1, -105, 0, 0)
		sl.BackgroundTransparency = 1
		sl.Text = "Coming Soon"
		sl.TextColor3 = Color3.fromRGB(150, 150, 150)
		sl.Font = Enum.Font.GothamMedium
		sl.TextSize = 13
		sl.Parent = row
	end
end

--=======================
-- TAB SWITCHING
--=======================
local function switchTab(newTab)
	if currentTab == newTab then return end
	local oldPanel = panels[currentTab]
	local newPanel = panels[newTab]

	if oldPanel then
		oldPanel.Visible = true
		TweenService:Create(oldPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {
			Position = UDim2.new(-1, 0, 0, 0),
		}):Play()
		task.delay(0.25, function()
			oldPanel.Visible = false
			oldPanel.Position = UDim2.new(0, 0, 0, 0)
		end)
	end

	if newPanel then
		newPanel.Position = UDim2.new(1, 0, 0, 0)
		newPanel.Visible = true
		TweenService:Create(newPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {
			Position = UDim2.new(0, 0, 0, 0),
		}):Play()
	end

	emotesPopup.Visible = false
	targetPopup.Visible = false

	for tabName, btn in pairs(tabButtons) do
		btn.BackgroundColor3 = (tabName == newTab) and C_BTN_ACTIVE or C_BTN
	end

	currentTab = newTab
end

for tabName, btn in pairs(tabButtons) do
	btn.MouseButton1Click:Connect(function() switchTab(tabName) end)
end

panels["HOME"].Visible = true
tabButtons["HOME"].BackgroundColor3 = C_BTN_ACTIVE

--=======================
-- DRAG
--=======================
local dragging = false
local dragStart, startPos = nil, nil

mainFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mousePos = UserInputService:GetMouseLocation()
		local framePos = mainFrame.AbsolutePosition
		if mousePos.Y - framePos.Y < 38 then
			dragging = true
			dragStart = input.Position
			startPos = mainFrame.Position
		end
	end
end)
mainFrame.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

--=======================
-- J KEY TOGGLE
--=======================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.J then
		guiVisible = not guiVisible
		mainFrame.Visible = guiVisible
	end
end)

--=======================
-- KEYBIND INPUT
--=======================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	for _, bind in ipairs(allKeybinds) do
		if bind.listening then
			bind.key = input.KeyCode
			bind.listening = false
			bind.btn.Text = input.KeyCode.Name
			bind.btn.BackgroundColor3 = C_BTN
		elseif bind.key and input.KeyCode == bind.key then
			bind.active = not bind.active
			bind.btn.Text = bind.key.Name .. (bind.active and " [ON]" or " [OFF]")
			if bind.onToggle then bind.onToggle(bind.active) end
		end
	end
end)

--=======================
-- ESP SYSTEM
--=======================
local function createESP(target)
	if target == player then return end
	local char = target.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	if espObjects[target] then espObjects[target].gui:Destroy() end

	local bb = Instance.new("BillboardGui")
	bb.Name = "ESP"
	bb.Size = UDim2.new(0, 200, 0, 40)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.Parent = head

	local nl = Instance.new("TextLabel")
	nl.Size = UDim2.new(1, 0, 0, 20)
	nl.BackgroundTransparency = 1
	nl.Text = target.Name
	nl.TextColor3 = C_TEXT
	nl.Font = Enum.Font.GothamMedium
	nl.TextSize = 14
	nl.Parent = bb

	local hl = Instance.new("TextLabel")
	hl.Size = UDim2.new(1, 0, 0, 16)
	hl.Position = UDim2.new(0, 0, 0, 20)
	hl.BackgroundTransparency = 1
	hl.Text = "HP: 100"
	hl.TextColor3 = Color3.fromRGB(0, 255, 0)
	hl.Font = Enum.Font.GothamMedium
	hl.TextSize = 12
	hl.Parent = bb

	espObjects[target] = {gui = bb, healthLabel = hl}
end

local function removeESP(target)
	if espObjects[target] then espObjects[target].gui:Destroy(); espObjects[target] = nil end
end

local function createHitbox(target)
	if target == player then return end
	local char = target.Character
	if not char then return end
	if hitboxObjects[target] then hitboxObjects[target]:Destroy() end

	local h = Instance.new("Highlight")
	h.Name = "HitboxHighlight"
	h.FillTransparency = 0.7
	h.FillColor = Color3.fromRGB(255, 0, 0)
	h.OutlineColor = Color3.fromRGB(255, 255, 0)
	h.Parent = char
	hitboxObjects[target] = h
end

local function removeHitbox(target)
	if hitboxObjects[target] then hitboxObjects[target]:Destroy(); hitboxObjects[target] = nil end
end

-- UPDATE LOOP
task.spawn(function()
	while true do
		task.wait(0.2)
		if espEnabled then
			for _, p in Players:GetPlayers() do
				if p ~= player and p.Character then
					local head = p.Character:FindFirstChild("Head")
					if head and (not espObjects[p] or not espObjects[p].gui.Parent) then
						createESP(p)
					end
					if espObjects[p] and espObjects[p].healthLabel then
						local hum = p.Character:FindFirstChildOfClass("Humanoid")
						if hum then
							espObjects[p].healthLabel.Text = "HP: " .. math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth)
						end
					end
				end
			end
		else
			for p, _ in pairs(espObjects) do removeESP(p) end
		end
		if hitboxEnabled then
			for _, p in Players:GetPlayers() do
				if p ~= player and p.Character then
					if not hitboxObjects[p] or not hitboxObjects[p].Parent then createHitbox(p) end
				end
			end
		else
			for p, _ in pairs(hitboxObjects) do removeHitbox(p) end
		end
	end
end)

-- PLAYER CLEANUP
Players.PlayerRemoving:Connect(function(p)
	removeESP(p); removeHitbox(p)
	if selectedTarget == p then selectedTarget = nil end
end)

--=======================
-- TOUCH FLING
--=======================
local function setupTouchFling(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Touched:Connect(function(other)
				if not touchFlingEnabled then return end
				local otherChar = other.Parent
				if not otherChar then return end
				local otherHum = otherChar:FindFirstChildOfClass("Humanoid")
				if otherHum and otherHum.Health > 0 then
					local op = Players:GetPlayerFromCharacter(otherChar)
					if op and op ~= player then
						-- Try server first, fallback to client
						pcall(function() remote:FireServer("Fling", op) end)
						flingPlayer(op)
					end
				end
			end)
		end
	end
end

player.CharacterAdded:Connect(function(char)
	task.wait(0.5)
	setupTouchFling(char)
	task.wait(0.5)
	updateAvatar()
	if jumpBoostActive then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.JumpHeight = 7.2 + (getJumpVal() / 100) * 20 end
	end
	if speedBoostActive then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 + getSpeedVal() end
	end
end)

if player.Character then setupTouchFling(player.Character) end

-- Update target label
task.spawn(function()
	while true do
		task.wait(0.5)
		targetLabel.Text = "Target: " .. (selectedTarget and selectedTarget.Name or "None")
	end
end)

print("[AdminMenu] Single Script loaded successfully")
