--!strict
--[=[
	CadBridge client: registers the /911 and /panic chat commands and shows notifications.

	The client is untrusted. It only forwards what the player typed; the server re-validates
	every field, rate-limits, and decides who may do what.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("CadBridgeShared")
local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: any
local CommandParser = require(Shared:WaitForChild("CommandParser") :: ModuleScript) :: any

local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
local requestCall = remotesFolder:WaitForChild(Remotes.RequestCall) :: RemoteEvent
local panic = remotesFolder:WaitForChild(Remotes.Panic) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild(Remotes.Notify) :: RemoteEvent

-- Toasts ----------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CadBridgeToasts"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Position = UDim2.new(0.5, 0, 0, 16)
holder.Size = UDim2.fromOffset(420, 300)
holder.Parent = gui

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = holder

local COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(40, 60, 90),
	warn = Color3.fromRGB(110, 70, 20),
	dispatch = Color3.fromRGB(20, 90, 60),
	panic = Color3.fromRGB(140, 20, 20),
}

local order = 0
local function toast(kind: string, message: string)
	order += 1
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 36)
	label.BackgroundColor3 = COLORS[kind] or COLORS.info
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextWrapped = true
	label.Text = message
	label.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	task.delay(if kind == "panic" then 10 else 6, function()
		local tween = TweenService:Create(
			label,
			TweenInfo.new(0.4),
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		label:Destroy()
	end)
end

notifyRemote.OnClientEvent:Connect(function(kind: unknown, message: unknown)
	if type(kind) == "string" and type(message) == "string" then
		toast(kind, message)
	end
end)

-- Chat commands ---------------------------------------------------------------------------------
if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
	toast("warn", "CadBridge chat commands need TextChatService (ChatVersion = TextChatService).")
end

local function addCommand(name: string, alias: string, onTriggered: (text: string) -> ())
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = alias
	command.Parent = TextChatService
	command.Triggered:Connect(function(_source: TextSource, text: string)
		onTriggered(text)
	end)
end

addCommand("CadBridgeCall", "/911", function(text)
	local input, usage = CommandParser.parseCall(text)
	if input == nil then
		toast("info", usage or CommandParser.USAGE)
		return
	end
	requestCall:FireServer(input)
end)

addCommand("CadBridgePanic", "/panic", function(_text)
	panic:FireServer()
end)
