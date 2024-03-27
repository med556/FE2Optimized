--!native
--!nolint DeprecatedApi

-- MAPSCRIPT OPTIMIZED
-- Contrastual, 2024/3/26 - 2024/3/27

-- Featured in Liquid Breakout v1.15, Riptide Resurgence: Apex Update

--[[

Copyright 2024 Contrastual

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

]]

local tweenService = game:GetService("TweenService")

local mapScript = {}
local movingParts, movingModels = {}, {}

local waterDefaultColor, acidDefaultColor, lavaDefaultColor = Color3.fromRGB(33, 85, 185), Color3.new(0, 1), Color3.new(1)
local stateTransitionTweenInfo = TweenInfo.new(1, Enum.EasingStyle.Linear)

local easingStyles, easingDirections = Enum.EasingStyle:GetEnumItems(), Enum.EasingDirection:GetEnumItems()

-- Public functions
function mapScript.MovePart(part: BasePart | Model, translation: Vector3 | {number}, duration: number, isLocalSpace: boolean?, easingStyle: string | Enum.EasingStyle, easingDirection: string | Enum.EasingDirection)
	local moveStartTime = os.clock()

	if typeof(part) ~= "Instance" then
		error("MapScript.MovePart: argument #1 is not a valid BasePart or Model", 2)
	end
	local isBasePart, isModel = part:IsA("BasePart"), part:IsA("Model")
	if not (isBasePart or isModel) then
		error("MapScript.MovePart: argument #1 is not a valid BasePart or Model", 2)
	end
	if typeof(translation) == "Vector3" then
		translation = {translation.X, translation.Y, translation.Z}
	elseif type(translation) ~= "table" then
		error("MapScript.MovePart: argument #2 is not a valid Vector3 or array of coordinates", 2)
	end
	if type(duration) ~= "number" or duration ~= duration or math.abs(duration) == math.huge then
		error("MapScript.MovePart: argument #3 is not a valid number")
	end

	local failedEasingStyleCheck
	if type(easingStyle) == "string" then
		for i = 1, #easingStyles do
			if easingStyles[i].Name == easingStyle then
				easingStyle = easingStyles[i]
				break
			end
			if i == #easingStyles then
				failedEasingStyleCheck = true
			end
		end
	else
		failedEasingStyleCheck = typeof(easingStyle) ~= "EnumItem" or easingStyle.EnumType ~= Enum.EasingStyle
	end
	if failedEasingStyleCheck then
		easingStyle = Enum.EasingStyle.Sine
	end

	local failedEasingDurationCheck
	if type(easingDirection) == "string" then
		for i = 1, #easingDirections do
			if easingDirections[i].Name == easingDirection then
				easingDirection = easingDirections[i]
				break
			end
			if i == #easingDirections then
				failedEasingDurationCheck = true
			end
		end
	else
		failedEasingDurationCheck = typeof(easingDirection) ~= "EnumItem" or easingDirection.EnumType ~= Enum.EasingDirection
	end
	if failedEasingDurationCheck then
		easingDirection = Enum.EasingDirection.InOut
	end

	if isModel and not part.PrimaryPart then
		for _, descendant in next, part:GetDescendants() do
			if descendant:IsA("BasePart") then
				part.PrimaryPart = descendant
				warn("mapScript.MovePart: Model does not have a PrimaryPart, one is automatically set")
				break
			end
		end
	end

	local dataBank = isModel and movingModels or movingParts
	local translationData = dataBank[part]
	if not translationData then
		translationData = {}
		dataBank[part] = translationData
	end
	local data = {
		moveStartTime,
		translation[1], translation[2], translation[3],
		0, 0, 0,
		duration,
		isLocalSpace,
		easingStyle,
		easingDirection
	}
	for i = 1, 11 do
		table.insert(translationData, data[i])
	end
end

function mapScript.setWaterState(water: BasePart, state: string, noChangeColor: boolean?, specifiedColor: Color3)
	if typeof(water) ~= "Instance" or not water:IsA("BasePart") then
		return
	end
	state = type(state) == "string" and string.lower(state) or "water"
	if not noChangeColor then
		local newColor = typeof(specifiedColor) == "Vector3" and specifiedColor
			or state == "water" and waterDefaultColor
			or state == "acid" and acidDefaultColor
			or state == "lava" and lavaDefaultColor
		if newColor then
			tweenService:Create(water, stateTransitionTweenInfo, {Color = newColor}):Play()
		end
	end
	task.delay(1, function()
		local waterStateObj = water:FindFirstChild("State") or water:FindFirstChild("WaterState")
		if not waterStateObj then
			waterStateObj = Instance.new("StringValue")
			waterStateObj.Name = "WaterState"
			waterStateObj.Parent = water
		end
		waterStateObj.Value = state
	end)
end

function mapScript.moveWater(part, translation, duration, isLocalSpace)
	mapScript.MovePart(part, translation, duration, isLocalSpace, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
end

-- Internal movement system
local function calculateTranslations(cFrame: CFrame, translations, clock): CFrame
	local iter = 1
	while true do
		local moveStartTime = translations[iter]
		if not moveStartTime then
			break
		end
		local duration = translations[iter + 7]
		local time = math.clamp(clock - moveStartTime, 0, duration)
		local tweenServiceInterpolation = tweenService:GetValue(time / duration, translations[iter + 9], translations[iter + 10])
		local translation = {}
		for i = 1, 3 do
			local axisCheckpointPosition = iter + i + 3
			local newTranslation = translations[axisCheckpointPosition - 3] * tweenServiceInterpolation
			translation[i] = newTranslation - translations[axisCheckpointPosition]
			translations[axisCheckpointPosition] = newTranslation
		end
		cFrame = translations[iter + 8] and cFrame * CFrame.new(translation[1], translation[2], translation[3]) or cFrame + Vector3.new(translation[1], translation[2], translation[3])
		if time == duration then
			for i = 1, 11 do
				table.remove(translations, iter)
			end
			continue
		end
		iter += 11
	end
	return cFrame
end

task.spawn(function()
	local objects, cFrames = {}, {}
	
	local yieldFunctions = {
		task.wait,
		wait
	}
	local yieldType = 1
	
	while yieldFunctions[yieldType]() do
		local clock = os.clock()
		
		table.clear(objects)
		table.clear(cFrames)
		
		debug.profilebegin("interpolatePart")
		for part, translations in next, movingParts do
			table.insert(objects, part)
			table.insert(cFrames, calculateTranslations(part.CFrame, translations, clock))
			if #translations <= 0 then
				movingParts[part] = nil
			end
		end
		debug.profileend()
		
		local partCount = #objects
		if partCount > 0 then
			debug.profilebegin("applyInterpolationsPart")
			if partCount >= 5 then
				workspace:BulkMoveTo(objects, cFrames, Enum.BulkMoveMode.FireAllEvents)
			else
				for i = 1, partCount do
					objects[i].CFrame = cFrames[i]
				end
			end
			debug.profileend()
		end
		
		table.clear(objects)
		table.clear(cFrames)
		
		debug.profilebegin("interpolateModel")
		for model, translations in next, movingModels do
			table.insert(objects, model)
			table.insert(cFrames, calculateTranslations(model:GetPrimaryPartCFrame(), translations, clock))
			if #translations <= 0 then
				movingModels[model] = nil
			end
		end
		debug.profileend()
		
		local modelCount = #objects
		if modelCount > 0 then
			debug.profilebegin("applyInterpolationsModel")
			for i = 1, modelCount do
				objects[i]:SetPrimaryPartCFrame(cFrames[i])
			end
			debug.profileend()
		end

		-- Throttle if movements are taking way too long for some reason
		yieldType = os.clock() - clock > 0.033 and 2 or 1
	end
end)

return mapScript