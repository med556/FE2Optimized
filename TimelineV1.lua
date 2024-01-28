-- TIMELINE RUNTIME V1 OPTIMIZED
-- med556deluxe/Contrastual, originally by Crazyblox, 2024/1/28

-- This script is an optimized version of Flood Escape 2's Timelines V1 runtime, with some changes listed below:
-- + TimelinePlayer.Tween now has the same behavior as TimelinePlayer.SetProperties.
-- + This script's internal workings now abide by the camelCase naming convention.
--   TimelinePlayer functions are still named via PascalCase.
-- + MovePart no longer relies on a CFrameValue object and instead computes interpolation on the fly.
--   + This has the added benefit of combining with other MovePart functions, which modern FE2 cannot do. This was possible before
--     the introduction of MapScript.MovePart in FE2.
-- + Added proper functionality to relative properties.
-- + This script attempts to reduce the amount of index, newindex, and namecall operations with the engine,
--   allowing for better performance. You may be interested in reversing some of this as some of these localizations do inflate
--   the stack.
-- + XFrame functions now reside on a table, allowing modular addition of new functions.
-- + The InternalValues table in TimelinePlayer.SetProperties is now in the main thread to help ease the stack by not generating
--   a new table everytime TimelinePlayer.SetProperties is called.

-- The original runtime is provided by Crazyblox. See the repository here: https://github.com/Crazyblox-Games/FloodEscape2
-- This work is licensed under CC BY-SA 4.0. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/4.0/

local timelines = script.Parent:WaitForChild("Timelines")
if not timelines then error("Map requires 'Timelines' to function") end

local Lib = workspace.Multiplayer.GetMapVals:Invoke()

local players = game:FindService("Players")
local tweenService = game:FindService("TweenService")
local heartbeat = game:FindService("RunService").Heartbeat

local timelinePlayer = {}
local internalTweenConfigs = {}

local function translatePart(startTime, obj, translation, duration, isLocalSpace, easingStyle, easingDirection, isModel)
	easingStyle, easingDirection = Enum.EasingStyle[easingStyle], Enum.EasingDirection[easingDirection]

	local translateCheckpoint = Vector3.zero

	while true do
		local time = math.min(duration, tick() - startTime)

		local translate = translation * tweenService:GetValue(time / duration, easingStyle, easingDirection)
		local interpolation = translate - translateCheckpoint
		translateCheckpoint = translate

		if isModel then
			heartbeat:Wait()
			local pivot = obj:GetPivot()
			obj:PivotTo(isLocalSpace and pivot * CFrame.new(interpolation) or pivot + interpolation)
			
			if time >= duration then
				break
			end
			
			continue
		end

		local objCFrame = obj.CFrame
		obj.CFrame = isLocalSpace and objCFrame * CFrame.new(interpolation) or objCFrame + interpolation
		
		if time >= duration then
			break
		end

		heartbeat:Wait()
	end
end

function timelinePlayer.SetWaterState(water, state, noChangeColor, specifiedColor)
	if water:IsA("BasePart") then
		state = state or string.lower(state)
		local oldColor = water.Color
		local newColor = specifiedColor
			or (not state or state == "water") and Color3.fromRGB(33, 85, 185)
			or state == "acid" and Color3.new(0, 1)
			or state == "lava" and Color3.new(1)
		if not noChangeColor then
			tweenService:Create(water, TweenInfo.new(1, Enum.EasingStyle.Linear), {Color = newColor}):Play()
		end
		task.defer(function()
			local updState = water:FindFirstChild("WaterState")
			if updState then
				updState.Value = state
			end
			if not noChangeColor then
				water.Color = newColor
			end
		end)
	end
end

function timelinePlayer.MovePart(obj, translation, duration, isLocalSpace, easingStyle, easingDirection)
	if typeof(obj) ~= "Instance" then
		error("Object: Only an Instance (Model, BasePart) can be provided")
	end
	if not (obj:IsA("Model") or obj:IsA("BasePart")) then
		error("Object: MovePart can only accept a Model with a PrimaryPart or a BasePart")
	end
	if typeof(translation) ~= "Vector3" then
		error("Translation: Provided invalid data type (" .. typeof(translation) .. "); please provide a Vector3 Value")
	end
	easingStyle, easingDirection = easingStyle or "Sine", easingDirection or "InOut"

	local isModel = obj:IsA("Model")
	if isModel then
		if not obj.PrimaryPart then
			for _, descendant in next, obj:GetDescendants() do
				if descendant:IsA("BasePart") then
					obj.PrimaryPart = descendant
					warn("PrimaryPart not present; function has automatically assigned a PrimaryPart")
					break
				end
			end
		end
	end

	local internalCFrame = CFrame.new()

	local info = internalTweenConfigs[obj]
	if not info then
		info = {}; internalTweenConfigs[obj] = info
	end
	table.insert(internalTweenConfigs, task.spawn(translatePart, tick(), obj, translation, duration, isLocalSpace, easingStyle, easingDirection, isModel))
end

local internalValues = {
	CFrame = "CFrameValue",
	number = "NumberValue",
	Color3 = "Color3Value",
	Vector3 = "Vector3Value"
}

function timelinePlayer.SetProperties(obj, properties, attributes, tInfo, applyToDescendants, relative)
	local name = obj.Name
	if name == "Settings" or name == "Rescue" then
		error(name .. " can not be accessed by SetProperties")
	end
	for name, value in next, attributes do
		if tInfo == 0 then
			pcall(function()
				obj:SetAttribute(name, value)
			end)
			continue
		end
		local classMapping = internalValues[typeof(value)]
		if not classMapping then
			print(name, typeof(value), "not a valid internal value type")
			continue
		end
		local internalValue = Instance.new(classMapping)
		local tween = tweenService:Create(internalValue, tInfo, {
			Value = classMapping == "CFrameValue" and obj:GetAttribute(name) * relative or value + relative})
		internalValue.Value = obj:GetAttribute(name)
		internalValue:GetPropertyChangedSignal("Value"):Connect(function()
			obj:SetAttribute(name, internalValue.Value)
		end)
		tween.Completed:Connect(function()
			internalValue:Destroy()
		end)
		tween:Play()
	end
	local objectsToApplyTo = applyToDescendants == true and {obj, unpack(obj:GetDescendants())} or {obj}
	for i = 1, #objectsToApplyTo do
		if tInfo == 0 then
			for property, value in next, properties do
				pcall(function()
					local prop = objectsToApplyTo[property]
					objectsToApplyTo[property] = typeof(prop) == "CFrame" and prop * value or prop + value
				end)
			end
			continue
		end
		local properties = properties
		if relative then
			properties = table.clone(properties)
			for property, value in next, properties do
				pcall(function()
					local prop = objectsToApplyTo[property]
					properties[property] = typeof(prop) == "CFrame" and prop * value or prop + value
				end)
			end
		end
		pcall(function()
			tweenService:Create(objectsToApplyTo[i], tInfo, properties):Play()
		end)
	end
end

function timelinePlayer.Sound(obj, id, volume, pitch)
	local newSound = Instance.new("Sound")
	newSound.SoundId = "rbxassetid://" .. id
	newSound.Volume = 1
	newSound.Pitch = pitch
	newSound.Parent = obj or script.Parent
	newSound:Play()
end

function timelinePlayer.Alert(msg, color, duration)
	print("Alert function needs to be hooked up to the client!")
end

function timelinePlayer.ShakeCamera(intensity, length)
	print("ShakeCamera function needs to be hooked up to the client!")
end

local function teleportPlayer(destination, player)
	local character = player.Character
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			humanoidRootPart.CFrame = destination
		end
	end
end

function timelinePlayer.Teleport(destination, player)
	local destinationCFrame = destination.CFrame
	if player then
		teleportPlayer(destination, player)
	else
		for _, player in next, {--[[Plug your own method for getting all ingame players here]]} do
			teleportPlayer(destination, player)
		end
	end
end

function timelinePlayer.SetCamera(subject, enabled, camInfo, relativeToSubject)
	print("SetCamera needs to be hooked up to the client!")
end

local xFrameFunctions = {
	SetProperties = function(map, xFrame, player, length, value, attributes_)
		if value then
			local properties, attributes = {}, {}
			local isTween

			for name, value in next, attributes_ do
				if string.sub(name, 1, 9) == "Property_" then
					properties[string.sub(name, 10)] = value
				elseif string.sub(name, 1, 10) == "Attribute_" then
					attributes[string.sub(name, 11)] = value
				elseif string.sub(name, 1, 6) == "Tween_" then
					isTween = true
				end
			end
			
			local arguments = {
				value,
				properties,
				attributes,
				0,
				attributes_.XFrame_ApplyToDescendants or attributes_.ApplyToDescendants,
				attributes.ApplyRelative
			}
			
			if isTween then
				arguments[4] = TweenInfo.new(
					length,
					Enum.EasingStyle[attributes_.Tween_EasingStyle or "Sine"],
					Enum.EasingDirection[attributes_.Tween_EasingDirection or "InOut"],
					attributes_.Tween_RepeatCount or 0,
					attributes_.Tween_Reverses or false,
					attributes_.Tween_DelayTime or 0
				)
			end
			
			timelinePlayer.SetProperties(unpack(arguments))
		end
	end,
	SetWaterState = function(map, xFrame, player, length, value, attributes)
		if value then
			timelinePlayer.SetWaterState(
				value,
				attributes.State,
				attributes.DontChangeColor,
				attributes.SpecifiedColor
			)
		end
	end,
	MovePart = function(map, xFrame, player, length, value, attributes)
		if value then
			timelinePlayer.MovePart(
				value,
				attributes.Translation,
				length,
				attributes.UseLocalSpace or false,
				attributes.EasingStyle,
				attributes.EasingDirection)
		end
	end,
	Alert = function(map, xFrame, player, length, value, attributes)
		timelinePlayer.Alert(attributes.Message, attributes.Color, length)
	end,
	Sound = function(map, xFrame, player, length, value, attributes)
		timelinePlayer.Sound(value, attributes.SoundId, attributes.Volume or 1, attributes.Pitch or 1)
	end,
	ShakeCamera = function(map, xFrame, player, length, value, attributes)
		timelinePlayer.ShakeCamera(attributes.Intensity, length)
	end,
	Teleport = function(map, xFrame, player, length, value, attributes)
		timelinePlayer.Teleport(value, player)
	end,
	SetCamera = function(map, xFrame, player, length, value, attributes)
		timelinePlayer.SetCamera(value, attributes.Enabled, attributes.CamInfo, attributes.RelativeToSubject)
	end,
	
}
xFrameFunctions.Tween = xFrameFunctions.SetProperties

function timelinePlayer.PerformXFrame(map, xFrame, player)
	local attributes = xFrame:GetAttributes()
	local func, position, length = attributes.XFrame_Function, attributes.XFrame_Timestamp, attributes.XFrame_Length

	if type(func) ~= "string" then
		error("XFrame " .. xFrame.Name .. " contains invalid function")
	end

	if type(position) ~= "number" then
		error("XFrame " .. xFrame.Name .. " contains invalid Timestamp")
	end

	if type(length) ~= "number" then
		length = 0
	end

	if xFrameFunctions[func] then
		xFrameFunctions[func](map, xFrame, player, length, xFrame.Value, attributes)
	end
end

-- Validates a timeline
local function validateIsTimeline(Timeline)
	return Timeline.ClassName == "Configuration" and (
		Timeline:GetAttribute("Trigger_Delay")
			or Timeline:GetAttribute("Trigger_Button")
			or Timeline:GetAttribute("Trigger_Timeline")
			or Timeline:GetAttribute("Trigger_Touch")
	)
end

-- Validates an XFrame
local function validateIsXFrame(XFrame)
	return XFrame.ClassName == "ObjectValue" and (
		type(XFrame:GetAttribute("XFrame_Function")) == "string"
			and type(XFrame:GetAttribute("XFrame_Timestamp")) == "number"
	)
end

-- Retrieves a timeline's duration
local function getTimelineDuration(timeline)
	local maxTime = 0
	local children = timeline:GetChildren()
	for i = 1, #children do
		local keyframe = children[i]
		local attributes = keyframe:GetAttributes()
		local position = attributes.XFrame_Timestamp
		if type(position) == "number" then
			local duration = attributes.XFrame_Length
			if type(duration) == "number" then
				local repeatCount = attributes.Tween_RepeatCount or 0
				if repeatCount == -1 then
					return math.huge
				end
				position += ((duration * (repeatCount + 1)) * (attributes.Tween_Reverses and 2 or 1))
			end
			if position > maxTime then
				maxTime = position
			end
		end
	end
	return maxTime
end

-- Executes all XFrames within a Timeline
local function playTimeline(timeline, player)
	local attributes = timeline:GetAttributes()
	local delay = attributes.Trigger_Delay
	if type(delay) == "number" and delay > 0 then
		task.wait(delay)
	end
	local canLoop, allowMultipleTouches, duration =
		attributes.RepeatOnCompletion,
		attributes.Touch_AllowMultiple,
		getTimelineDuration(timeline)
	repeat
		for _, keyframe in next, timeline:GetDescendants() do
			if validateIsXFrame(keyframe) then
				local position = keyframe:GetAttribute("XFrame_Timestamp")
				if
					type(position) == "number"
					and type(keyframe:GetAttribute("XFrame_Function")) == "string"
				then
					task.delay(position, timelinePlayer.PerformXFrame, script.Parent, keyframe, player)
				end
			end
		end
		if duration == math.huge then
			return
		end
		task.wait(duration)
	until not canLoop or allowMultipleTouches
	for _, timeline in timelines:GetDescendants() do
		if validateIsTimeline(timeline) and timeline.Name == attributes.Trigger_Timeline then
			coroutine.resume(coroutine.create(playTimeline), timeline)
		end
	end
end

-- Connects Lib.Button to LibMap-based games
Lib.Button:connect(function(player, buttonNumber)
	for _, timeline in timelines:GetDescendants() do
		if validateIsTimeline(timeline) then
			local timelineTrigger, buttonTrigger = timeline:GetAttribute("Trigger_Timeline"), timeline:GetAttribute("Trigger_Button")
			if (type(timelineTrigger) ~= "string" or timelineTrigger ~= "") and buttonTrigger == buttonNumber then
				coroutine.resume(coroutine.create(playTimeline), timeline)
			end
		end
	end
end)

-- Generic start function
local mapObjs = script.Parent:GetDescendants()
local timelineDescendants = timelines:GetDescendants()
for i = 1, #timelineDescendants do
	local timeline = timelineDescendants[i]
	if validateIsTimeline(timeline) then
		local attributes = timeline:GetAttributes()
		local timelineTrigger, buttonTrigger, touchTrigger, delayTrigger =
			attributes.Trigger_Timeline,
			attributes.Trigger_Button,
			attributes.Trigger_Touch,
			attributes.Trigger_Delay
		if type(touchTrigger) == "string" and touchTrigger ~= "" then
			if (type(touchTrigger) ~= "string" or touchTrigger == "")
				or (type(buttonTrigger) ~= "number" or buttonTrigger <= 0) then
				local listeners, maxListeners = {}, 10
				local debounces = {}
				local allowMultiple = timeline:GetAttribute("Touch_AllowMultiple")
				for i = 1, #mapObjs do
					local obj = mapObjs[i]
					if obj.Name == touchTrigger and obj:IsA("BasePart") and #listeners < maxListeners then
						local connection
						connection = obj.Touched:Connect(function(hit)
							local player = players:GetPlayerFromCharacter(hit.Parent)
							if player then
								local uid = player.UserId
								if not table.find(debounces, uid) then
									table.insert(debounces, uid)
									task.spawn(playTimeline, timeline, allowMultiple and player)
									if allowMultiple then
										task.wait(1)
										table.remove(debounces, table.find(debounces, uid) or 0)
										return
									end
									debounces = nil
									local find = table.find(listeners, connection)
									if find then
										connection:Disconnect()
										table.remove(listeners, find)
									end
								end
							end
						end)
						table.insert(listeners, connection)
					end
				end
			end
			continue
		end
		if type(delayTrigger) == "number" then
			if (type(timelineTrigger) ~= "string" or timelineTrigger == "")
				or (type(buttonTrigger) ~= "number" or buttonTrigger <= 0)
				or (type(touchTrigger) ~= "string" or touchTrigger == "") then
				task.spawn(playTimeline, timeline)
			end
		end
	end
end

return timelinePlayer