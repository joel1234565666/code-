-- AdminServer - Server-side handlers for Admin Menu
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

-- Ensure RemoteEvent exists
local remote = ReplicatedStorage:FindFirstChild("AdminRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "AdminRemote"
	remote.Parent = ReplicatedStorage
end

local chatTags = {}

remote.OnServerEvent:Connect(function(plr, action, ...)
	local args = {...}

	if action == "Fling" then
		local target = args[1]
		if typeof(target) == "Instance" and target:IsA("Player") and target.Character then
			local hrp = target.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.AssemblyLinearVelocity = Vector3.new(
					math.random(-3000, 3000), math.random(2000, 5000), math.random(-3000, 3000))
				hrp.AssemblyAngularVelocity = Vector3.new(
					math.random(-50, 50), math.random(-50, 50), math.random(-50, 50))
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

print("[AdminServer] Loaded successfully")
