
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local TweenService = game:GetService("TweenService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local localPlayer = Players.LocalPlayer

local cameraModule
local controlModule

local CharacterContainer = {} do
	CharacterContainer.__index = CharacterContainer
	
	function CharacterContainer.new()
		local self = setmetatable({}, CharacterContainer)
		
		self.Characters = {}
		
		return self
	end
	
	function CharacterContainer:_GetIter(character)
		return table.find(self.Characters, character)
	end
	
	function CharacterContainer:Add(character)
		assert(self:_GetIter(character) == nil, "character is already in array")
		table.insert(self.Characters, character)
	end
	
	function CharacterContainer:Remove(character)
		local pos = self:_GetIter(character)
		assert(pos, "character is not in array")
		table.remove(self.Characters, pos)
	end
end

local characterContainer = CharacterContainer.new()

local Player = {} do
	Player.__index = Player
	
	function Player.new(playerObject)
		local self = setmetatable({}, Player)
		
		self.Character = nil
		self.PlayerObject = playerObject
		self.Humanoid = nil
		
		playerObject.CharacterAdded:Connect(function(character)
			self:OnCharacterAdded(character)
		end)
		
		playerObject.CharacterRemoving:Connect(function(character)
			self:OnCharacterRemoving(character)
		end)
		
		return self
	end
	
	function Player:Destroy()
		self.Character = nil
		self.PlayerObject = nil
		self.Humanoid = nil
	end
	
	function Player:GetRootPart()
		local humanoid = self.Humanoid
		return humanoid and humanoid.RootPart or nil
	end
	
	function Player:OnCharacterAdded(character)
		self.Character = character
		characterContainer:Add(character)
		self.Humanoid = character:FindFirstChildOfClass("Humanoid")
		while not self.Humanoid do
			local child = character.ChildAdded:Wait()
			if child:IsA("Humanoid") then
				self.Humanoid = child
			end
		end
	end
	
	function Player:OnCharacterRemoving(character)
		characterContainer:Remove(character)
		self.Character = nil
		self.Humanoid = nil
	end
end

--local PLAYER_GUI_WAIT_ASYNCHRONOUS = false
local LocalPlayerHandler = {} do
	LocalPlayerHandler.__index = LocalPlayerHandler
	
	LocalPlayerHandler.GetRootPart = Player.GetRootPart
	LocalPlayerHandler.Destroy = Player.Destroy
	
	function LocalPlayerHandler.new(playerObject)
		local self = setmetatable(Player.new(playerObject), LocalPlayerHandler)
		
		self.PlayerGui = nil
		
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			self.PlayerGui = playerGui
		else
			local playerGuiAddedConn
			playerGuiAddedConn = localPlayer.ChildAdded:Connect(function(child)
				if child:IsA("PlayerGui") then
					playerGuiAddedConn:Disconnect()
					self.PlayerGui = child
					controlModule:OnPlayerGuiAdded()
				end
			end)
		end
		
		return self
	end
	
	function LocalPlayerHandler:OnCharacterAdded(character)
		Player.OnCharacterAdded(self, character)
		cameraModule.CameraController:OnCharacterAdded(character)
		controlModule:UpdateTouchGuiVisibility(character)
	end
	
	function LocalPlayerHandler:OnCharacterRemoving(character)
		Player.OnCharacterRemoving(self, character)
		
		controlModule:UpdateTouchGuiVisibility()
	end
end

local PlayerHandler = {} do
	PlayerHandler.__index = PlayerHandler
	
	function PlayerHandler.new()
		local self = setmetatable({}, PlayerHandler)
		
		self.PlayerMap = {}
		
		for _, player in next, Players:GetPlayers() do
			if player ~= localPlayer then
				self:OnPlayerAdded(player)
			end
		end
		
		self.LocalPlayer = LocalPlayerHandler.new(localPlayer)
		self.PlayerMap[localPlayer] = self.LocalPlayer
		
		Players.PlayerAdded:Connect(function(playerObject)
			self:OnPlayerAdded(playerObject)
		end)
		
		Players.PlayerRemoving:Connect(function(playerObject)
			self:OnPlayerRemoving(playerObject)
		end)
		
		return self
	end
	
	function PlayerHandler:OnPlayerAdded(playerObject)
		self.PlayerMap[playerObject] = Player.new(playerObject)
	end
	
	function PlayerHandler:OnPlayerRemoving(playerObject)
		self.PlayerMap[playerObject]:Destroy()
		self.PlayerMap[playerObject] = nil
	end
end

local popper

local cameraHandler do
	
	CameraHandler = {} do
		CameraHandler.__index = CameraHandler
		
		function CameraHandler.new()
			local self = setmetatable({}, CameraHandler)
			
			local camera = workspace.CurrentCamera
			
			self.CameraObject = camera
			
			self.FieldOfView = camera.FieldOfView
			self.ViewportSize = camera.ViewportSize
			
			self.NearPlaneZ = camera.NearPlaneZ
			self.CameraSubject = camera.CameraSubject
			self.CameraType = camera.CameraType
			
			camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
				self.FieldOfView = camera.FieldOfView
				self:OnFieldOfViewChanged()
			end)
			
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self.ViewportSize = camera.ViewportSize
				self:OnViewportSizeChanged()
			end)
			
			camera:GetPropertyChangedSignal("NearPlaneZ"):Connect(function()
				self.NearPlaneZ = camera.NearPlaneZ
				self:OnNearPlaneZChanged()
			end)
			
			camera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
				self.CameraSubject = camera.CameraSubject
				self:UpdateCameraSubject()
			end)
			
			camera:GetPropertyChangedSignal("CameraType"):Connect(function()
				self.CameraType = camera.CameraType
				self:OnCameraTypeChanged()
			end)
			
			return self
		end
		
		function CameraHandler:OnFieldOfViewChanged()
			popper:UpdateProjection(self.FieldOfView, self.ViewportSize)
		end
		
		function CameraHandler:OnViewportSizeChanged()
			popper:UpdateProjection(self.FieldOfView, self.ViewportSize)
		end
		
		function CameraHandler:OnNearPlaneZChanged()
			popper:UpdateNearPlaneZ(self.NearPlaneZ)
		end
		
		function CameraHandler:UpdateCameraSubject()
			popper:UpdateCameraSubject(self.CameraSubject)
			cameraModule:OnCameraSubjectChanged(self.CameraSubject, self.CameraType)
		end
		
		function CameraHandler:OnCameraTypeChanged()
			cameraModule:OnCameraTypeChanged(self.CameraType)
		end
	end
	
	cameraHandler = CameraHandler.new()
end

local localPlayerD = PlayerHandler.new().LocalPlayer

local CameraUtils = {} do
	--[[
		CameraUtils - Math utility functions shared by multiple camera scripts
		2018 Camera Update - AllYourBlox
	--]]
	
	local savedMouseBehavior: Enum.MouseBehavior = Enum.MouseBehavior.Default
	local lastMouseBehaviorOverride: Enum.MouseBehavior? = nil
	function CameraUtils.setMouseBehaviorOverride(value: Enum.MouseBehavior)
		if UserInputService.MouseBehavior ~= lastMouseBehaviorOverride then
			savedMouseBehavior = UserInputService.MouseBehavior
		end
		
		UserInputService.MouseBehavior = value
		lastMouseBehaviorOverride = value
	end
	
	function CameraUtils.restoreMouseBehavior()
		if UserInputService.MouseBehavior == lastMouseBehaviorOverride then
			UserInputService.MouseBehavior = savedMouseBehavior
		end
		lastMouseBehaviorOverride = nil
	end
	
	local savedRotationType: Enum.RotationType = Enum.RotationType.MovementRelative
	local lastRotationTypeOverride: Enum.RotationType? = nil
	function CameraUtils.setRotationTypeOverride(value: Enum.RotationType)
		if UserGameSettings.RotationType ~= lastRotationTypeOverride then
			savedRotationType = UserGameSettings.RotationType
		end
		
		UserGameSettings.RotationType = value
		lastRotationTypeOverride = value
	end
	
	function CameraUtils.restoreRotationType()
		if UserGameSettings.RotationType == lastRotationTypeOverride then
			UserGameSettings.RotationType = savedRotationType
		end
		lastRotationTypeOverride = nil
	end
	
end


local Popper = {} do
	Popper.__index = Popper
	
	--------------------------------------------------------------------------------------------
	-- Popper uses the level geometry find an upper bound on subject-to-camera distance.
	--
	-- Hard limits are applied immediately and unconditionally. They are generally caused
	-- when level geometry intersects with the near plane (with exceptions, see below).
	--
	-- Soft limits are only applied under certain conditions.
	-- They are caused when level geometry occludes the subject without actually intersecting
	-- with the near plane at the target distance.
	--
	-- Soft limits can be promoted to hard limits and hard limits can be demoted to soft limits.
	-- We usually don"t want the latter to happen.
	--
	-- A soft limit will be promoted to a hard limit if an obstruction
	-- lies between the current and target camera positions.
	--------------------------------------------------------------------------------------------
	
	function Popper.new(camera)
		local self = setmetatable({}, Popper)
		
		self.NearPlaneZ = nil
		self.ProjX = nil
		self.ProjY = nil
		
		self.SubjectRoot = nil
		self.SubjectPart = nil
		
		self.ViewportSize = nil
		self.CameraObject = camera
		
		return self
	end
	
	function Popper:UpdateProjection(fieldOfView, viewportSize)
		local fov = math.rad(fieldOfView)
		local view = viewportSize
		local ar = view.X / view.Y
		
		self.ProjY = 2 * math.tan(fov / 2)
		self.ProjX = ar * self.ProjY
		self.ViewportSize = viewportSize
	end
	
	function Popper:UpdateNearPlaneZ(nearPlaneZ)
		self.NearPlaneZ = nearPlaneZ
	end
	
	function Popper:UpdateCameraSubject(subject)
		if subject:IsA("Humanoid") then
			self.SubjectPart = subject.RootPart
		elseif subject:IsA("BasePart") then
			self.SubjectPart = subject
		else
			self.SubjectPart = nil
		end
	end
	
	local function eraseFromEnd(t, toSize)
		for i = #t, toSize + 1, -1 do
			t[i] = nil
		end
	end
	
	local newRay = Ray.new
	local blacklist = characterContainer.Characters
	
	--------------------------------------------------------------------------------
	-- Piercing raycasts
	
	
	local function getCollisionPoint(origin, dir)
		local originalSize = #blacklist
		repeat
			local hitPart, hitPoint = workspace:FindPartOnRayWithIgnoreList(
				newRay(origin, dir), blacklist, false, true
			)
			
			if hitPart then
				if hitPart.CanCollide then
					eraseFromEnd(blacklist, originalSize)
					return hitPoint, true
				end
				table.insert(blacklist, hitPart)
			end
		until not hitPart
		
		eraseFromEnd(blacklist, originalSize)
		return origin + dir, false
	end
	
	--------------------------------------------------------------------------------
	
	local function getTotalTransparency(part)
		return 1 - (1 - part.Transparency) * (1 - part.LocalTransparencyModifier)
	end
	
	local function canOcclude(part, subjectRoot)
		-- Occluders must be:
		-- 1. Opaque
		-- 2. Interactable
		-- 3. Not in the same assembly as the subject
		
		return getTotalTransparency(part) < 0.25
			and part.CanCollide
			and subjectRoot ~= (part:GetRootPart() or part)
			and not part:IsA("TrussPart")
	end
	
	-- Maximum number of rays that can be cast
	local QUERY_POINT_CAST_LIMIT = 64
	
	function Popper:_QueryPoint(origin, unitDir, dist, lastPos)
		debug.profilebegin("queryPoint")
		
		local originalSize = #blacklist
		
		local nearPlaneZ = self.NearPlaneZ
		dist += nearPlaneZ
		local target = origin + unitDir*dist
		
		local softLimit = math.huge
		local hardLimit = math.huge
		local movingOrigin = origin
		
		local numPierced = 0
		
		local subjectRoot = self.SubjectRoot
		
		repeat
			local entryPart, entryPos = workspace:FindPartOnRayWithIgnoreList(
				newRay(movingOrigin, target - movingOrigin), blacklist, false, true)
			numPierced += 1
			
			if entryPart then
				-- forces the current iteration into a hard limit to cap the number of raycasts
				local earlyAbort = numPierced >= QUERY_POINT_CAST_LIMIT
				
				if canOcclude(entryPart, subjectRoot) or earlyAbort then
					local wl = {entryPart}
					local exitPart = workspace:FindPartOnRayWithWhitelist(newRay(target, entryPos - target), wl, true)
					
					local lim = (entryPos - origin).Magnitude
					
					if exitPart and not earlyAbort then
						local promote = false
						if lastPos then
							promote = workspace:FindPartOnRayWithWhitelist(newRay(lastPos, target - lastPos), wl, true)
								or workspace:FindPartOnRayWithWhitelist(newRay(target, lastPos - target), wl, true)
						end
						
						if promote then
							-- Ostensibly a soft limit, but the camera has passed through it in the last frame, so promote to a hard limit.
							hardLimit = lim
						elseif dist < softLimit then
							-- Trivial soft limit
							softLimit = lim
						end
					else
						-- Trivial hard limit
						hardLimit = lim
					end
				end
				
				table.insert(blacklist, entryPart)
				movingOrigin = entryPos - unitDir * 1e-3
			end
		until hardLimit < math.huge or not entryPart
		
		eraseFromEnd(blacklist, originalSize)
		
		debug.profileend()
		return softLimit - nearPlaneZ, hardLimit - nearPlaneZ
	end
	
	function Popper:_QueryViewport(focus, dist)
		debug.profilebegin("queryViewport")
		
		local fP =  focus.p
		local fX =  focus.rightVector
		local fY =  focus.upVector
		local fZ = -focus.lookVector
		
		local viewport = self.ViewportSize
		
		local hardBoxLimit = math.huge
		local softBoxLimit = math.huge
		
		local projX = self.ProjX
		local projY = self.ProjY
		local nearPlaneZ = self.NearPlaneZ
		
		local camera = self.CameraObject
		
		-- Center the viewport on the PoI, sweep points on the edge towards the target, and take the minimum limits
		for viewX = 0, 1 do
			local worldX = fX * ((viewX - 0.5) * projX)
			
			for viewY = 0, 1 do
				local worldY = fY * ((viewY - 0.5) * projY)
				
				local origin = fP + nearPlaneZ * (worldX + worldY)
				local lastPos = camera:ViewportPointToRay(
					viewport.x * viewX,
					viewport.y * viewY
				).Origin
				
				local softPointLimit, hardPointLimit = self:_QueryPoint(origin, fZ, dist, lastPos)
				
				if hardPointLimit < hardBoxLimit then
					hardBoxLimit = hardPointLimit
				end
				
				if softPointLimit < softBoxLimit then
					softBoxLimit = softPointLimit
				end
			end
		end
		
		debug.profileend()
		
		return softBoxLimit, hardBoxLimit
	end
	
	
	-- Offsets for the volume visibility test
	local SCAN_SAMPLE_OFFSETS = {
		Vector2.new( 0.4, 0.0),
		Vector2.new(-0.4, 0.0),
		Vector2.new( 0.0,-0.4),
		Vector2.new( 0.0, 0.4),
		Vector2.new( 0.0, 0.2),
	}
	
	function Popper:_TestPromotion(focus, dist, focusExtrapolation)
		debug.profilebegin("TestPromotion")
		
		local fP = focus.p
		local fX = focus.rightVector
		local fY = focus.upVector
		local fZ = -focus.lookVector
		
		do
			-- Dead reckoning the camera rotation and focus
			debug.profilebegin("extrapolate")
			
			local SAMPLE_DT = 0.0625
			local SAMPLE_MAX_T = 1.25
			
			local maxDist = (getCollisionPoint(fP, focusExtrapolation.posVelocity * SAMPLE_MAX_T) - fP).Magnitude
			-- Metric that decides how many samples to take
			local combinedSpeed = focusExtrapolation.posVelocity.magnitude
			
			local limit = math.min(SAMPLE_MAX_T, focusExtrapolation.rotVelocity.magnitude + maxDist/combinedSpeed)
			for dt = 0, limit, SAMPLE_DT do
				local cfDt = focusExtrapolation.extrapolate(dt) -- Extrapolated CFrame at time dt
				
				if self:_QueryPoint(cfDt.p, -cfDt.lookVector, dist) >= dist then
					return false
				end
			end
			
			debug.profileend()
		end
		
		do
			-- Test screen-space offsets from the focus for the presence of soft limits
			debug.profilebegin("testOffsets")
			
			for _, offset in next, SCAN_SAMPLE_OFFSETS do
				local scaledOffset = offset
				local pos = getCollisionPoint(fP, fX * scaledOffset.x + fY * scaledOffset.y)
				if self:_QueryPoint(pos, (fP + fZ * dist - pos).Unit, dist) == math.huge then
					return false
				end
			end
			
			debug.profileend()
		end
		
		debug.profileend()
		return true
	end
	
	function Popper:Run(focus, targetDist, focusExtrapolation)
		debug.profilebegin("Popper")
		local subjectPart = self.SubjectPart
		self.SubjectRoot = subjectPart and subjectPart:GetRootPart() or subjectPart
		
		local dist = targetDist
		local soft, hard = self:_QueryViewport(focus, targetDist)
		
		if hard < dist then
			dist = hard
		end
		
		if soft < dist and self:_TestPromotion(focus, targetDist, focusExtrapolation) then
			dist = soft
		end
		
		self.SubjectRoot = nil
		
		debug.profileend()
		return dist
	end
	
end

popper = Popper.new(cameraHandler.CameraObject)
popper:UpdateProjection(cameraHandler.FieldOfView, cameraHandler.ViewportSize)
popper:UpdateNearPlaneZ(cameraHandler.NearPlaneZ)

local zoomController do
	local ZoomController = {} do
		ZoomController.__index = ZoomController
		
		-- Controls the distance between the focus and the camera.
		
		local ZOOM_STIFFNESS = 4.5
		local ZOOM_DEFAULT = 12.5
		local ZOOM_ACCELERATION = 0.0375
		
		local MIN_FOCUS_DIST = 0.5
		local DIST_OPAQUE = 1
		
		local ConstrainedSpring = {} do
			ConstrainedSpring.__index = ConstrainedSpring
			
			function ConstrainedSpring.new(frequency: number, initialPosition: number)
				return setmetatable({
					Frequency = frequency,
					Position = initialPosition,
					Velocity = 0,
					MinValue = 0,
					MaxValue = 0,
					Goal = initialPosition,
				}, ConstrainedSpring)
			end
			
			function ConstrainedSpring:Step(dt: number)
				local frequency = self.Frequency * 2 * math.pi -- Convert from Hz to rad/s
				local position = self.Position
				local velocity = self.Velocity
				local minValue = self.MinValue
				local maxValue = self.MaxValue
				local goal = self.Goal
				
				-- Solve the spring ODE for position and velocity after time t, assuming critical damping:
				--   2*f*x'[t] + x''[t] = f^2*(g - x[t])
				-- Knowns are x[0] and x'[0].
				-- Solve for x[t] and x'[t].
				
				local offset = goal - position
				local step = frequency * dt
				local decay = math.exp(-step)
				
				local resultPosition = goal + (velocity * dt - offset * (step + 1)) * decay
				local resultVelocity = ((offset * frequency - velocity) * step + velocity) * decay
				
				-- Constrain
				if resultPosition < minValue then
					resultPosition = minValue
					resultVelocity = 0
				elseif resultPosition > maxValue then
					resultPosition = maxValue
					resultVelocity = 0
				end
				
				self.Position = resultPosition
				self.Velocity = resultVelocity
				
				return resultPosition
			end
		end
		
		function ZoomController.new()
			local self = setmetatable({}, ZoomController)
			
			self.ZoomDelta = 0
			self.ZoomSpring = ConstrainedSpring.new(ZOOM_STIFFNESS, ZOOM_DEFAULT)
			
			return self
		end
		
		local function stepTargetZoom(z, dz, zoomMin, zoomMax)
			z = math.clamp(z + dz * (1 + z * ZOOM_ACCELERATION), zoomMin, zoomMax)
			if z < DIST_OPAQUE then
				z = dz <= 0 and zoomMin or DIST_OPAQUE
			end
			return z
		end
		
		function ZoomController:Update(renderDt: number, focus: CFrame, extrapolation, min, max)
			local poppedZoom = math.huge
			
			local zoomSpring = self.ZoomSpring
			if zoomSpring.Goal > DIST_OPAQUE then
				-- Make a pessimistic estimate of zoom distance for this step without accounting for poppercam
				local maxPossibleZoom = math.max(
					zoomSpring.Position,
					stepTargetZoom(zoomSpring.Goal, self.ZoomDelta, min, max)
				)
				
				-- Run the Popper algorithm on the feasible zoom range, [MIN_FOCUS_DIST, maxPossibleZoom]
				poppedZoom = popper:Run(
					focus * CFrame.new(0, 0, MIN_FOCUS_DIST),
					maxPossibleZoom - MIN_FOCUS_DIST,
					extrapolation
				) + MIN_FOCUS_DIST
			end
			
			zoomSpring.MinValue = MIN_FOCUS_DIST
			zoomSpring.MaxValue = math.min(max, poppedZoom)
			
			return zoomSpring:Step(renderDt)
		end
		
		function ZoomController:SetZoomParameters(targetZoom, newZoomDelta)
			self.ZoomSpring.Goal = targetZoom
			self.ZoomDelta = newZoomDelta
		end
		
	end
	
	zoomController = ZoomController.new()
end

local CameraInput = {} do
	
	local CAMERA_INPUT_PRIORITY = Enum.ContextActionPriority.Default.Value
	local MB_TAP_LENGTH = 0.3 -- (s) length of time for a short mouse button tap to be registered
	
	local ROTATION_SPEED_KEYS = math.rad(120) -- (rad/s)
	local ROTATION_SPEED_MOUSE = Vector2.new(1, 0.77) * math.rad(0.5) -- (rad/s)
	local ROTATION_SPEED_POINTERACTION = Vector2.new(1, 0.77) * math.rad(7) -- (rad/s)
	local ROTATION_SPEED_TOUCH = Vector2.new(1, 0.66) * math.rad(1) -- (rad/s)
	local ROTATION_SPEED_GAMEPAD = Vector2.new(1, 0.77) * math.rad(4) -- (rad/s)
	
	local ZOOM_SPEED_MOUSE = 1 -- (scaled studs/wheel click)
	local ZOOM_SPEED_KEYS = 0.1 -- (studs/s)
	local ZOOM_SPEED_TOUCH = 0.04 -- (scaled studs/DIP %)
	
	local MIN_TOUCH_SENSITIVITY_FRACTION = 0.25 -- 25% sensitivity at 90°
	
	-- right mouse button up & down events
	local rmbDown, rmbUp do
		local rmbDownBindable = Instance.new("BindableEvent")
		local rmbUpBindable = Instance.new("BindableEvent")
		
		rmbDown = rmbDownBindable.Event
		rmbUp = rmbUpBindable.Event
		
		UserInputService.InputBegan:Connect(function(input, gpe)
			if not gpe and input.UserInputType == Enum.UserInputType.MouseButton2 then
				rmbDownBindable:Fire()
			end
		end)
		
		UserInputService.InputEnded:Connect(function(input, gpe)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				rmbUpBindable:Fire()
			end
		end)
	end
	
	local thumbstickCurve do
		local K_CURVATURE = 2 -- amount of upwards curvature (0 is flat)
		local K_DEADZONE = 0.1 -- deadzone
		
		function thumbstickCurve(x)
			-- remove sign, apply linear deadzone
			local fDeadzone = (math.abs(x) - K_DEADZONE) / (1 - K_DEADZONE)
			
			-- apply exponential curve and scale to fit in [0, 1]
			local fCurve = (math.exp(K_CURVATURE*fDeadzone) - 1) / (math.exp(K_CURVATURE) - 1)
			
			-- reapply sign and clamp
			return math.sign(x) * math.clamp(fCurve, 0, 1)
		end
	end
	
	-- Adjust the touch sensitivity so that sensitivity is reduced when swiping up
	-- or down, but stays the same when swiping towards the middle of the screen
	local camera = cameraHandler.CameraObject
	local function adjustTouchPitchSensitivity(delta: Vector2): Vector2
		-- get the camera pitch in world space
		local pitch = camera.CFrame:ToEulerAnglesYXZ()
		
		if delta.Y*pitch >= 0 then
			-- do not reduce sensitivity when pitching towards the horizon
			return delta
		end
		
		-- set up a line to fit:
		-- 1 = f(0)
		-- 0 = f(±pi/2)
		local curveY = 1 - (2 * math.abs(pitch) / math.pi) ^ 0.75
		
		-- remap curveY from [0, 1] -> [MIN_TOUCH_SENSITIVITY_FRACTION, 1]
		local sensitivity = curveY * (1 - MIN_TOUCH_SENSITIVITY_FRACTION) + MIN_TOUCH_SENSITIVITY_FRACTION
		
		return Vector2.new(1, sensitivity) * delta
	end
	
	local function isInDynamicThumbstickArea(pos: Vector3): boolean
		local playerGui = localPlayerD.PlayerGui
		local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
		local touchFrame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
		local thumbstickFrame = touchFrame and touchFrame:FindFirstChild("DynamicThumbstickFrame")
		
		if not thumbstickFrame then
			return false
		end
		
		if not touchGui.Enabled then
			return false
		end
		
		local posTopLeft = thumbstickFrame.AbsolutePosition
		local posBottomRight = posTopLeft + thumbstickFrame.AbsoluteSize
		
		return
			pos.X >= posTopLeft.X and
			pos.Y >= posTopLeft.Y and
			pos.X <= posBottomRight.X and
			pos.Y <= posBottomRight.Y
	end
	
	local worldDt = 1 / 60
	RunService.Stepped:Connect(function(_, _worldDt)
		worldDt = _worldDt
	end)
	
	
	local connectionList = {}
	local panInputCount = 0
	
	local function incPanInputCount()
		panInputCount = math.max(0, panInputCount + 1)
	end
	
	local function decPanInputCount()
		panInputCount = math.max(0, panInputCount - 1)
	end
	
	local function resetPanInputCount()
		panInputCount = 0
	end
	
	local gamepadState = {
		Thumbstick2 = Vector2.zero,
	}
	
	local keyboardState = {
		Left = 0,
		Right = 0,
		I = 0,
		O = 0
	}
	
	local mouseState = {
		Movement = Vector2.zero,
		Wheel = 0, -- PointerAction
		Pan = Vector2.zero, -- PointerAction
		Pinch = 0, -- PointerAction
	}
	
	local touchState = {
		Move = Vector2.zero,
		Pinch = 0,
	}
	
	local gamepadZoomPressBindable = Instance.new("BindableEvent")
	CameraInput.gamepadZoomPress = gamepadZoomPressBindable.Event
	
	function CameraInput.getRotation(disableKeyboardRotation: boolean?): Vector2
		local inversionVector = Vector2.new(1, UserGameSettings:GetCameraYInvertValue())
		
		-- keyboard input is non-coalesced, so must account for time delta
		local kKeyboard = Vector2.new(keyboardState.Right - keyboardState.Left, 0)*worldDt
		local kGamepad = gamepadState.Thumbstick2
		local kMouse = mouseState.Movement
		local kPointerAction = mouseState.Pan
		local kTouch = adjustTouchPitchSensitivity(touchState.Move)
		
		if disableKeyboardRotation then
			kKeyboard = Vector2.zero
		end
		
		local result =
			kKeyboard * ROTATION_SPEED_KEYS +
			kGamepad * ROTATION_SPEED_GAMEPAD +
			kMouse * ROTATION_SPEED_MOUSE +
			kPointerAction * ROTATION_SPEED_POINTERACTION +
			kTouch * ROTATION_SPEED_TOUCH
		
		return result*inversionVector
	end
	
	function CameraInput.getZoomDelta(): number
		local kKeyboard = keyboardState.O - keyboardState.I
		local kMouse = -mouseState.Wheel + mouseState.Pinch
		local kTouch = -touchState.Pinch
		return kKeyboard * ZOOM_SPEED_KEYS
			+ kMouse * ZOOM_SPEED_MOUSE
			+ kTouch * ZOOM_SPEED_TOUCH
	end
	
	local function thumbstick(action, state, input)
		local position = input.Position
		
		gamepadState[input.KeyCode.Name] = Vector2.new(
			thumbstickCurve(position.X),
			-thumbstickCurve(position.Y)
		)
		
		return Enum.ContextActionResult.Pass
	end
	
	local function mouseMovement(input)
		local delta = input.Delta
		mouseState.Movement = Vector2.new(delta.X, delta.Y)
	end
	
	local function mouseWheel(action, state, input)
		mouseState.Wheel = input.Position.Z
		return Enum.ContextActionResult.Pass
	end
	
	local function keypress(action, state, input)
		keyboardState[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
	end
	
	local function gamepadZoomPress(action, state, input)
		if state == Enum.UserInputState.Begin then
			gamepadZoomPressBindable:Fire()
		end
	end
	
	local function resetInputDevices()
		local states = {
			gamepadState,
			keyboardState,
			mouseState,
			touchState,
		}
		
		for _, device in next, states do
			for k, v in next, device do
				if type(v) == "boolean" then
					device[k] = false
				else
					-- Mul by zero to preserve vector types
					device[k] *= 0
				end
			end
		end
	end
	
	local touchBegan, touchChanged, touchEnded, resetTouchState do
		-- Use TouchPan & TouchPinch when they work in the Studio emulator
		
		local touches: {[InputObject]: boolean?} = {} -- {[InputObject] = sunk}
		local dynamicThumbstickInput: InputObject? -- Special-cased 
		local lastPinchDiameter: number?
		
		function touchBegan(input: InputObject, sunk: boolean)
			assert(input.UserInputType == Enum.UserInputType.Touch)
			assert(input.UserInputState == Enum.UserInputState.Begin)
			
			if dynamicThumbstickInput == nil and isInDynamicThumbstickArea(input.Position) and not sunk then
				-- any finger down starting in the dynamic thumbstick area should always be
				-- ignored for camera purposes. these must be handled specially from all other
				-- inputs, as the DT does not sink inputs by itself
				dynamicThumbstickInput = input
				return
			end
			
			if not sunk then
				incPanInputCount()
			end
			
			-- register the finger
			touches[input] = sunk
		end
		
		function touchEnded(input: InputObject, sunk: boolean)
			assert(input.UserInputType == Enum.UserInputType.Touch)
			assert(input.UserInputState == Enum.UserInputState.End)
			
			-- reset the DT input
			if input == dynamicThumbstickInput then
				dynamicThumbstickInput = nil
			end
			
			-- reset pinch state if one unsunk finger lifts
			if touches[input] == false then
				lastPinchDiameter = nil
				decPanInputCount()
			end
			
			-- unregister input
			touches[input] = nil
		end
		
		function touchChanged(input, sunk)
			assert(input.UserInputType == Enum.UserInputType.Touch)
			assert(input.UserInputState == Enum.UserInputState.Change)
			
			-- ignore movement from the DT finger
			if input == dynamicThumbstickInput then
				return
			end
			
			-- fixup unknown touches
			if touches[input] == nil then
				touches[input] = sunk
			end
			
			-- collect unsunk touches
			local unsunkTouches = {}
			for touch, sunk in next, touches do
				if not sunk then
					table.insert(unsunkTouches, touch)
				end
			end
			
			-- 1 finger: pan
			if #unsunkTouches == 1 then
				if touches[input] == false then
					local delta = input.Delta
					-- total touch pan movement (reset at end of frame)
					touchState.Move += Vector2.new(delta.X, delta.Y)
				end
			end
			
			-- 2 fingers: pinch
			if #unsunkTouches == 2 then
				local pinchDiameter = (unsunkTouches[1].Position - unsunkTouches[2].Position).Magnitude
				
				if lastPinchDiameter then
					touchState.Pinch += pinchDiameter - lastPinchDiameter
				end
				
				lastPinchDiameter = pinchDiameter
			else
				lastPinchDiameter = nil
			end
		end
		
		function resetTouchState()
			touches = {}
			dynamicThumbstickInput = nil
			lastPinchDiameter = nil
			resetPanInputCount()
		end
	end
	
	local function pointerAction(wheel, pan, pinch, gpe)
		if not gpe then
			mouseState.Wheel = wheel
			mouseState.Pan = pan
			mouseState.Pinch = -pinch
		end
	end
	
	local function inputBegan(input, sunk)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchBegan(input, sunk)
			
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not sunk then
			incPanInputCount()
		end
	end
	
	local function inputChanged(input, sunk)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchChanged(input, sunk)
			
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			mouseMovement(input)
		end
	end
	
	local function inputEnded(input, sunk)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchEnded(input, sunk)
			
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			decPanInputCount()
		end
	end
	
	local inputEnabled = false
	
	function CameraInput.setInputEnabled(_inputEnabled)
		if inputEnabled == _inputEnabled then
			return
		end
		inputEnabled = _inputEnabled
		
		resetInputDevices()
		resetTouchState()
		
		if inputEnabled then -- enable
			ContextActionService:BindActionAtPriority(
				"RbxCameraThumbstick",
				thumbstick,
				false,
				CAMERA_INPUT_PRIORITY,
				Enum.KeyCode.Thumbstick2
			)
			
			ContextActionService:BindActionAtPriority(
				"RbxCameraKeypress",
				keypress,
				false,
				CAMERA_INPUT_PRIORITY,
				Enum.KeyCode.Left,
				Enum.KeyCode.Right,
				Enum.KeyCode.I,
				Enum.KeyCode.O
			)
			
			ContextActionService:BindAction(
				"RbxCameraGamepadZoom",
				gamepadZoomPress,
				false,
				Enum.KeyCode.ButtonR3
			)
			
			table.insert(connectionList, UserInputService.InputBegan:Connect(inputBegan))
			table.insert(connectionList, UserInputService.InputChanged:Connect(inputChanged))
			table.insert(connectionList, UserInputService.InputEnded:Connect(inputEnded))
			table.insert(connectionList, UserInputService.PointerAction:Connect(pointerAction))
			table.insert(connectionList, GuiService.MenuOpened:Connect(resetTouchState))
			
		else -- disable
			ContextActionService:UnbindAction("RbxCameraThumbstick")
			ContextActionService:UnbindAction("RbxCameraMouseMove")
			ContextActionService:UnbindAction("RbxCameraMouseWheel")
			ContextActionService:UnbindAction("RbxCameraKeypress")
			
			ContextActionService:UnbindAction("RbxCameraGamepadZoom")
			
			for _, conn in next, connectionList do
				conn:Disconnect()
			end
			table.clear(connectionList)
		end
	end
	
	function CameraInput.getInputEnabled()
		return inputEnabled
	end
	
	function CameraInput.resetInputForFrameEnd()
		mouseState.Movement = Vector2.zero
		touchState.Move = Vector2.zero
		touchState.Pinch = 0
		
		mouseState.Wheel = 0 -- PointerAction
		mouseState.Pan = Vector2.zero -- PointerAction
		mouseState.Pinch = 0 -- PointerAction
	end
	
	UserInputService.WindowFocused:Connect(resetInputDevices)
	UserInputService.WindowFocusReleased:Connect(resetInputDevices)
end


local MouseLockController = {} do
	MouseLockController.__index = MouseLockController
	
	function MouseLockController.new(cameraModule)
		local self = setmetatable({}, MouseLockController)
		
		self.IsEnabled = true
		self.IsMouseLocked = false
		
		self.MouseLockOffset = Vector3.new(1.75, 0, 0)
		self.BoundKeys = {
			Enum.KeyCode.LeftShift,
			Enum.KeyCode.RightShift
		}
		
		self.CameraModule = cameraModule
		
		self.MouseObject = localPlayer:GetMouse()
		self.LockCursorImage = "rbxasset://textures/MouseLockedCursor.png"
		self.LastMouseIcon = nil
		
		if not UserInputService.TouchEnabled then
			UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
				if gameProcessedEvent then return end
				if not self.IsEnabled then return end
				
				local key = input.KeyCode
				for _, switchKey in next, self.BoundKeys do
					if key == switchKey then
						self:_OnMouseLockToggled()
					end
				end
			end)
		end
		
		return self
	end
	
	function MouseLockController:_SetMouseIconOverride()
		local mouse = self.MouseObject
		self.LastMouseIcon = mouse.Icon
		mouse.Icon = self.LockCursorImage
	end
	
	function MouseLockController:_RestoreMouseIcon()
		self.MouseObject.Icon = self.LastMouseIcon
	end
	
	function MouseLockController:_OnMouseLockToggled()
		self.IsMouseLocked = not self.IsMouseLocked
		
		if self.IsMouseLocked then
			self:_SetMouseIconOverride()
		else
			self:_RestoreMouseIcon()
		end
	end
	
	function MouseLockController:IsMouseLocked(): boolean
		return self.IsEnabled and self.IsMouseLocked
	end
	
	function MouseLockController:EnableMouseLock(enable: boolean)
		if enable == self.IsEnabled then return end
		
		self.IsEnabled = enable
		
		if not self.IsEnabled then
			self:_RestoreMouseIcon()
			
			-- If the mode is disabled while being used, fire the event to toggle it off
			if self.IsMouseLocked then
				self.CameraModule:_OnMouseLockToggled()
			end
			
			self.IsMouseLocked = false
		end
		
	end
	
end

local BaseCamera = {} do
	BaseCamera.__index = BaseCamera
	
	--[[
		BaseCamera - Abstract base class for camera control modules
		2018 Camera Update - AllYourBlox
	--]]
	
	local UNIT_Z = Vector3.new(0, 0, 1)
	
	-- Note: DotProduct check in CoordinateFrame::lookAt() prevents using values within about
	-- 8.11 degrees of the +/- Y axis, that's why these limits are currently 80 degrees
	local MIN_Y = math.rad(-80)
	local MAX_Y = math.rad(80)
	
	local HEAD_OFFSET = Vector3.new(0, 1.5, 0)
	local R15_HEAD_OFFSET = Vector3.new(0, 1.5, 0)
	local R15_HEAD_OFFSET_NO_SCALING = Vector3.new(0, 2, 0)
	local HUMANOID_ROOT_PART_SIZE = Vector3.new(2, 2, 1)
	
	local GAMEPAD_ZOOM_STEP_1 = 0
	local GAMEPAD_ZOOM_STEP_2 = 10
	local GAMEPAD_ZOOM_STEP_3 = 20
	
	local ZOOM_SENSITIVITY_CURVATURE = 0.5
	local FIRST_PERSON_DISTANCE_MIN = 0.5
	
	function BaseCamera.new()
		local self = setmetatable({}, BaseCamera)
		
		-- So that derived classes have access to this
		self.FirstPersonDistanceThreshold = 1 -- Below this value, snap into first person
		
		self.lastUserPanCamera = tick()
		
		-- position on last update call
		self.lastSubjectPosition = Vector3.zero
		
		self.CameraMinZoomDistance = 0
		self.CameraMaxZoomDistance = 2500
		
		-- These subject distance members refer to the nominal camera-to-subject follow distance that the camera
		-- is trying to maintain, not the actual measured value.
		-- The default is updated when screen orientation or the min/max distances change,
		-- to be sure the default is always in range and appropriate for the orientation.
		self.currentSubjectDistance = 12.5
		
		self.IsFirstPerson = false
		
		-- Used by modules which want to reset the camera angle on respawn.
		self.resetCameraAngle = true
		
		self.enabled = false
		
		-- Input Event Connections
		
		self.gamepadZoomPressConnection = nil
		
		self.MouseLockController = MouseLockController.new(self)
		self.mouseLockOffset = Vector3.zero
		
		-- Initialization things used to always execute at game load time, but now these camera modules are instantiated
		-- when needed, so the code here may run well after the start of the game
		
		UserGameSettings:GetPropertyChangedSignal("TouchMovementMode"):Connect(function()
			self:OnGameSettingsTouchMovementModeChanged()
		end)
		self:OnGameSettingsTouchMovementModeChanged()
		
		UserGameSettings:SetCameraYInvertVisible()
		UserGameSettings:SetGamepadCameraSensitivityVisible()
		
		return self
	end
	
	function BaseCamera:OnCharacterAdded(char)
		self.resetCameraAngle = self.resetCameraAngle or self.enabled
	end
	
	function BaseCamera:StepZoom()
		local zoom: number = self.currentSubjectDistance
		local zoomDelta: number = CameraInput.getZoomDelta()
		
		if math.abs(zoomDelta) > 0 then
			local newZoom
			
			if zoomDelta > 0 then
				newZoom = zoom + zoomDelta * (1 + zoom * ZOOM_SENSITIVITY_CURVATURE)
				newZoom = math.max(newZoom, self.FirstPersonDistanceThreshold)
			else
				newZoom = (zoom + zoomDelta) / (1 - zoomDelta * ZOOM_SENSITIVITY_CURVATURE)
				newZoom = math.max(newZoom, FIRST_PERSON_DISTANCE_MIN)
			end
			
			if newZoom < self.FirstPersonDistanceThreshold then
				newZoom = FIRST_PERSON_DISTANCE_MIN
			end
			
			self:SetCameraToSubjectDistance(newZoom)
		end
	end
	
	function BaseCamera:GetSubjectPosition(): Vector3?
		local result = self.lastSubjectPosition
		local cameraSubject = cameraHandler.CameraSubject
		
		if not cameraSubject then
			-- cameraSubject is nil
			-- Note: Previous RootCamera did not have this else case and let self.lastSubjectPosition
			-- get set to nil in the case of cameraSubject being nil. This function now exits here to preserve the
			-- last set valid values for these, as nil values are not handled cases
			return nil
		end
		
		if cameraSubject:IsA("Humanoid") then
			local humanoid = cameraSubject
			local humanoidIsDead = humanoid:GetState() == Enum.HumanoidStateType.Dead
			
			local bodyPartToFollow = humanoid.RootPart
			
			-- If the humanoid is dead, prefer their head part as a follow target, if it exists
			if humanoidIsDead then
				if humanoid.Parent and humanoid.Parent:IsA("Model") then
					bodyPartToFollow = humanoid.Parent:FindFirstChild("Head") or bodyPartToFollow
				end
			end
			
			if bodyPartToFollow and bodyPartToFollow:IsA("BasePart") then
				local heightOffset
				if humanoid.RigType == Enum.HumanoidRigType.R15 then
					if humanoid.AutomaticScalingEnabled then
						heightOffset = R15_HEAD_OFFSET
						if bodyPartToFollow == humanoid.RootPart then
							local rootPartSizeOffset = (humanoid.RootPart.Size.Y / 2) - (HUMANOID_ROOT_PART_SIZE.Y / 2)
							heightOffset = heightOffset + Vector3.new(0, rootPartSizeOffset, 0)
						end
					else
						heightOffset = R15_HEAD_OFFSET_NO_SCALING
					end
				else
					heightOffset = HEAD_OFFSET
				end
				
				if humanoidIsDead then
					heightOffset = Vector3.zero
				end
				
				result = bodyPartToFollow.CFrame.p + bodyPartToFollow.CFrame:vectorToWorldSpace(
					heightOffset + humanoid.CameraOffset)
			end
			
		elseif cameraSubject:IsA("BasePart") then
			result = cameraSubject.CFrame.p
		elseif cameraSubject:IsA("Model") then
			if cameraSubject.PrimaryPart then
				result = cameraSubject:GetPrimaryPartCFrame().p
			else
				result = cameraSubject:GetModelCFrame().p
			end
		end
		
		self.lastSubjectPosition = result
		
		return result
	end
	
	function BaseCamera:OnDynamicThumbstickEnabled()
		if UserInputService.TouchEnabled then
			self.isDynamicThumbstickEnabled = true
		end
	end
	
	function BaseCamera:OnDynamicThumbstickDisabled()
		self.isDynamicThumbstickEnabled = false
	end
	
	function BaseCamera:OnGameSettingsTouchMovementModeChanged()
		if (UserGameSettings.TouchMovementMode == Enum.TouchMovementMode.DynamicThumbstick
			or UserGameSettings.TouchMovementMode == Enum.TouchMovementMode.Default) then
			self:OnDynamicThumbstickEnabled()
		else
			self:OnDynamicThumbstickDisabled()
		end
	end
	
	function BaseCamera:GamepadZoomPress()
		local dist = self:GetCameraToSubjectDistance()
		
		if dist > (GAMEPAD_ZOOM_STEP_2 + GAMEPAD_ZOOM_STEP_3) / 2 then
			self:SetCameraToSubjectDistance(GAMEPAD_ZOOM_STEP_2)
		elseif dist > (GAMEPAD_ZOOM_STEP_1 + GAMEPAD_ZOOM_STEP_2) / 2 then
			self:SetCameraToSubjectDistance(GAMEPAD_ZOOM_STEP_1)
		else
			self:SetCameraToSubjectDistance(GAMEPAD_ZOOM_STEP_3)
		end
	end
	
	function BaseCamera:Enable(enable: boolean)
		if self.enabled ~= enable then
			self.enabled = enable
			if self.enabled then
				CameraInput.setInputEnabled(true)
				
				self.gamepadZoomPressConnection = CameraInput.gamepadZoomPress:Connect(function()
					self:GamepadZoomPress()
				end)
			else
				CameraInput.setInputEnabled(false)
				
				if self.gamepadZoomPressConnection then
					self.gamepadZoomPressConnection:Disconnect()
					self.gamepadZoomPressConnection = nil
				end
				-- Clean up additional event listeners and reset a bunch of properties
				self:Cleanup()
			end
		end
	end
	
	function BaseCamera:Cleanup()
		-- Unlock mouse for example if right mouse button was being held down
		CameraUtils.restoreMouseBehavior()
	end
	
	function BaseCamera:UpdateMouseBehavior()
		-- first time transition to first person mode or mouse-locked third person
		if self.IsFirstPerson or self.MouseLockController.IsMouseLocked then
			CameraUtils.setRotationTypeOverride(Enum.RotationType.CameraRelative)
			CameraUtils.setMouseBehaviorOverride(Enum.MouseBehavior.LockCenter)
		else
			CameraUtils.restoreRotationType()
			CameraUtils.restoreMouseBehavior()
		end
	end
	
	-- Calling this setter with the current value will force checking that it is still
	-- in range after a change to the min/max distance limits
	function BaseCamera:UpdateMaxMinZoomDistance()
		self:SetCameraToSubjectDistance(self.currentSubjectDistance)
	end
	
	function BaseCamera:SetCameraToSubjectDistance(desiredSubjectDistance: number): number
		local lastSubjectDistance = self.currentSubjectDistance
		
		-- By default, camera modules will respect LockFirstPerson and override the currentSubjectDistance with 0
		-- regardless of what Player.CameraMinZoomDistance is set to, so that first person can be made
		-- available by the developer without needing to allow players to mousewheel dolly into first person.
		-- Some modules will override this function to remove or change first-person capability.
		
		local newSubjectDistance = math.clamp(
			desiredSubjectDistance,
			self.CameraMinZoomDistance,
			self.CameraMaxZoomDistance
		)
		
		if newSubjectDistance < self.FirstPersonDistanceThreshold then
			self.currentSubjectDistance = 0.5
			if not self.IsFirstPerson then
				self:EnterFirstPerson()
			end
		else
			self.currentSubjectDistance = newSubjectDistance
			if self.IsFirstPerson then
				self:LeaveFirstPerson()
			end
		end
		
		-- Pass target distance and zoom direction to the zoom controller
		zoomController:SetZoomParameters(
			self.currentSubjectDistance,
			math.sign(desiredSubjectDistance - lastSubjectDistance)
		)
		
		-- Returned only for convenience to the caller to know the outcome
		return self.currentSubjectDistance
	end
	
	-- Nominal distance, set by dollying in and out with the mouse wheel or equivalent, not measured distance
	function BaseCamera:GetCameraToSubjectDistance(): number
		return self.currentSubjectDistance
	end
	
	function BaseCamera:GetCameraLookVector(): Vector3
		return cameraHandler.CameraObject.CFrame.LookVector or UNIT_Z
	end
	
	function BaseCamera:CalculateNewLookCFrameFromArg(suppliedLookVector: Vector3?, rotateInput: Vector2): CFrame
		local currLookVector: Vector3 = suppliedLookVector or self:GetCameraLookVector()
		local currPitchAngle = math.asin(currLookVector.Y)
		
		local yTheta = math.clamp(
			rotateInput.Y,
			-MAX_Y + currPitchAngle,
			-MIN_Y + currPitchAngle
		)
		
		local constrainedRotateInput = Vector2.new(rotateInput.X, yTheta)
		local startCFrame = CFrame.new(Vector3.zero, currLookVector)
		
		local newLookCFrame = CFrame.Angles(0, -constrainedRotateInput.X, 0)
			* startCFrame * CFrame.Angles(-constrainedRotateInput.Y, 0, 0)
		return newLookCFrame
	end
	
	function BaseCamera:CalculateNewLookVectorFromArg(suppliedLookVector: Vector3?, rotateInput: Vector2): Vector3
		local newLookCFrame = self:CalculateNewLookCFrameFromArg(suppliedLookVector, rotateInput)
		return newLookCFrame.LookVector
	end
	
	function BaseCamera:GetHumanoid(): Humanoid?
		local character = localPlayer.Character
		if character then
			return character:FindFirstChildOfClass("Humanoid")
		end
		return nil
	end
	
end

local Poppercam = {} do
	Poppercam.__index = Poppercam
	
	--[[
		Poppercam - Occlusion module that brings the camera closer to the subject when objects are blocking the view.
	--]]
	
	local TransformExtrapolator = {} do
		TransformExtrapolator.__index = TransformExtrapolator
		
		local CF_IDENTITY = CFrame.identity
		
		local function cframeToAxis(cframe: CFrame): Vector3
			local axis: Vector3, angle: number = cframe:ToAxisAngle()
			return axis*angle
		end
		
		local function axisToCFrame(axis: Vector3): CFrame
			local angle: number = axis.Magnitude
			if angle > 1e-5 then
				return CFrame.fromAxisAngle(axis, angle)
			end
			return CF_IDENTITY
		end
		
		local function extractRotation(cf: CFrame): CFrame
			local _, _, _, xx, yx, zx, xy, yy, zy, xz, yz, zz = cf:GetComponents()
			return CFrame.new(0, 0, 0, xx, yx, zx, xy, yy, zy, xz, yz, zz)
		end
		
		function TransformExtrapolator.new()
			return setmetatable({
				lastCFrame = nil,
			}, TransformExtrapolator)
		end
		
		function TransformExtrapolator:Step(dt: number, currentCFrame: CFrame)
			local lastCFrame = self.lastCFrame or currentCFrame
			self.lastCFrame = currentCFrame
			
			local currentPos = currentCFrame.Position
			local currentRot = extractRotation(currentCFrame)
			
			local lastPos = lastCFrame.p
			local lastRot = extractRotation(lastCFrame)
			
			-- Estimate velocities from the delta between now and the last frame
			-- This estimation can be a little noisy.
			local dp = (currentPos - lastPos)/dt
			local dr = cframeToAxis(currentRot*lastRot:inverse())/dt
			
			local function extrapolate(t)
				local p = dp*t + currentPos
				local r = axisToCFrame(dr*t)*currentRot
				return r + p
			end
			
			return {
				extrapolate = extrapolate,
				posVelocity = dp,
				rotVelocity = dr,
			}
		end
		
		function TransformExtrapolator:Reset()
			self.lastCFrame = nil
		end
	end
	
	function Poppercam.new()
		local self = setmetatable({}, Poppercam)
		self.focusExtrapolator = TransformExtrapolator.new()
		return self
	end
	
	function Poppercam:Enable(enable)
		self.focusExtrapolator:Reset()
	end
	
	function Poppercam:Update(renderDt, desiredCameraCFrame, desiredCameraFocus, min, max)
		local rotatedFocus = CFrame.new(desiredCameraFocus.p, desiredCameraCFrame.p)
			* CFrame.new(
				0, 0, 0,
				-1, 0, 0,
				0, 1, 0,
				0, 0, -1
			)
		
		local extrapolation = self.focusExtrapolator:Step(renderDt, rotatedFocus)
		local zoom = zoomController:Update(renderDt, rotatedFocus, extrapolation, min, max)
		
		return rotatedFocus * CFrame.new(0, 0, zoom), desiredCameraFocus
	end
	
end


local ClassicCamera = setmetatable({}, BaseCamera) do
	ClassicCamera.__index = ClassicCamera
	
	--[[
		ClassicCamera - Classic Roblox camera control module
		2018 Camera Update - AllYourBlox

		Note: This module also handles camera control types Follow and Track, the
		latter of which is currently not distinguished from Classic
	--]]
	
	local tweenAcceleration = math.rad(220) -- Radians/Second^2
	local tweenSpeed = math.rad(0)          -- Radians/Second
	local tweenMaxSpeed = math.rad(250)     -- Radians/Second
	local TIME_BEFORE_AUTO_ROTATE = 2       -- Seconds
	
	local INITIAL_CAMERA_ANGLE = CFrame.fromOrientation(math.rad(-15), 0, 0)
	local ZOOM_SENSITIVITY_CURVATURE = 0.5
	local FIRST_PERSON_DISTANCE_MIN = 0.5
	
	-- Critically damped spring class for fluid motion effects
	local Spring = {} do
		Spring.__index = Spring
		
		-- Initialize to a given undamped frequency and default position
		function Spring.new(freq, pos)
			return setmetatable({
				freq = freq,
				goal = pos,
				pos = pos,
				vel = 0,
			}, Spring)
		end
		
		-- Advance the spring simulation by `dt` seconds
		function Spring:step(dt: number)
			local f: number = self.freq::number * 2.0 * math.pi
			local g: Vector3 = self.goal
			local p0: Vector3 = self.pos
			local v0: Vector3 = self.vel
			
			local offset = p0 - g
			local decay = math.exp(-f * dt)
			
			local p1 = (offset * (1 + f * dt) + v0 * dt) * decay + g
			local v1 = (v0 * (1 - f * dt) - offset * (f * f * dt)) * decay
			
			self.pos = p1
			self.vel = v1
			
			return p1
		end
	end
	
	function ClassicCamera.new()
		local self = setmetatable(BaseCamera.new(), ClassicCamera)
		
		self.lastUpdate = tick()
		self.cameraToggleSpring = Spring.new(5, 0)
		self.OcclusionModule = Poppercam.new()
		self.OcclusionModule:Enable(true)
		
		return self
	end
	
	local function isFinite(val: number): boolean
		return val == val and val ~= math.huge and val ~= -math.huge
	end
	
	local function isFiniteVector3(vec3: Vector3): boolean
		return isFinite(vec3.X) and isFinite(vec3.Y) and isFinite(vec3.Z)
	end
	
	function ClassicCamera:Update(dt)
		local now = tick()
		local timeDelta = now - self.lastUpdate
		
		local camera = cameraHandler.CameraObject
		local newCameraCFrame = camera.CFrame
		local newCameraFocus = camera.Focus
		
		local overrideCameraLookVector = nil
		if self.resetCameraAngle then
			local rootPart: BasePart = localPlayerD:GetRootPart()
			if rootPart then
				overrideCameraLookVector = (rootPart.CFrame * INITIAL_CAMERA_ANGLE).lookVector
			else
				overrideCameraLookVector = INITIAL_CAMERA_ANGLE.lookVector
			end
			self.resetCameraAngle = false
		end
		
		local humanoid = self:GetHumanoid()
		local cameraSubject = camera.CameraSubject
		local isClimbing = humanoid and humanoid:GetState() == Enum.HumanoidStateType.Climbing
		
		local rotateInput = CameraInput.getRotation()
		
		self:StepZoom()
		
		-- Reset tween speed if user is panning
		if CameraInput.getRotation() ~= Vector2.zero then
			tweenSpeed = 0
			self.lastUserPanCamera = tick()
		end
		
		local userRecentlyPannedCamera = now - self.lastUserPanCamera < TIME_BEFORE_AUTO_ROTATE
		local subjectPosition: Vector3 = self:GetSubjectPosition()
		
		if subjectPosition and camera then
			local zoom = self:GetCameraToSubjectDistance()
			if zoom < 0.5 then
				zoom = 0.5
			end
			
			if self.MouseLockController.IsMouseLocked and not self.IsFirstPerson then
				-- We need to use the right vector of the camera after rotation, not before
				local newLookCFrame: CFrame = self:CalculateNewLookCFrameFromArg(overrideCameraLookVector, rotateInput)
				
				local offset = self.MouseLockController.MouseLockOffset
				local cameraRelativeOffset: Vector3 = offset.X * newLookCFrame.RightVector + offset.Y * newLookCFrame.UpVector + offset.Z * newLookCFrame.LookVector
				
				--offset can be NAN, NAN, NAN if newLookVector has only y component
				if isFiniteVector3(cameraRelativeOffset) then
					subjectPosition += cameraRelativeOffset
				end
			end
			
			newCameraFocus = CFrame.new(subjectPosition)
			
			local cameraFocusP = newCameraFocus.p
			local newLookVector = self:CalculateNewLookVectorFromArg(overrideCameraLookVector, rotateInput)
			
			newCameraCFrame = CFrame.new(cameraFocusP - (zoom * newLookVector), cameraFocusP)
		end
		
		self.lastUpdate = now
		
		newCameraCFrame, newCameraFocus = self.OcclusionModule:Update(dt, newCameraCFrame, newCameraFocus,
			self.CameraMinZoomDistance, self.CameraMaxZoomDistance)
		return newCameraCFrame, newCameraFocus
	end
	
	function ClassicCamera:EnterFirstPerson()
		self.IsFirstPerson = true
		self:UpdateMouseBehavior()
	end
	
	function ClassicCamera:LeaveFirstPerson()
		self.IsFirstPerson = false
		self:UpdateMouseBehavior()
	end
	
end


local TransparencyController = {} do
	TransparencyController.__index = TransparencyController
	
	--[[
		TransparencyController - Manages transparency of player character at close camera-to-subject distances
		2018 Camera Update - AllYourBlox
	--]]
	
	local MAX_TWEEN_RATE = 2.8 -- per second
	
	function TransparencyController.new()
		local self = setmetatable({}, TransparencyController)
		
		self.transparencyDirty = false
		self.enabled = false
		self.lastTransparency = nil
		
		self.descendantAddedConn = nil
		self.descendantRemovingConn = nil
		
		self.toolDescendantAddedConns = {}
		self.toolDescendantRemovingConns = {}
		self.cachedParts = {}
		
		return self
	end
	
	
	function TransparencyController:HasToolAncestor(object: Instance)
		if object.Parent == nil then return false end
		return object.Parent:IsA("Tool") or self:HasToolAncestor(object.Parent)
	end
	
	function TransparencyController:IsValidPartToModify(part: BasePart)
		if part:IsA("BasePart") or part:IsA("Decal") then
			return not self:HasToolAncestor(part)
		end
		return false
	end
	
	function TransparencyController:CachePartsRecursive(object)
		if object then
			if self:IsValidPartToModify(object) then
				self.cachedParts[object] = true
				self.transparencyDirty = true
			end
			for _, child in next, object:GetChildren() do
				self:CachePartsRecursive(child)
			end
		end
	end
	
	function TransparencyController:TeardownTransparency()
		for child, _ in next, self.cachedParts do
			child.LocalTransparencyModifier = 0
		end
		self.cachedParts = {}
		self.transparencyDirty = true
		self.lastTransparency = nil
		
		if self.descendantAddedConn then
			self.descendantAddedConn:disconnect()
			self.descendantAddedConn = nil
		end
		if self.descendantRemovingConn then
			self.descendantRemovingConn:disconnect()
			self.descendantRemovingConn = nil
		end
		for object, conn in next, self.toolDescendantAddedConns do
			conn:Disconnect()
			self.toolDescendantAddedConns[object] = nil
		end
		for object, conn in next, self.toolDescendantRemovingConns do
			conn:Disconnect()
			self.toolDescendantRemovingConns[object] = nil
		end
	end
	
	function TransparencyController:SetupTransparency(character)
		self:TeardownTransparency()
		
		if self.descendantAddedConn then self.descendantAddedConn:disconnect() end
		self.descendantAddedConn = character.DescendantAdded:Connect(function(object)
			-- This is a part we want to invisify
			if self:IsValidPartToModify(object) then
				self.cachedParts[object] = true
				self.transparencyDirty = true
				-- There is now a tool under the character
			elseif object:IsA("Tool") then
				if self.toolDescendantAddedConns[object] then
					self.toolDescendantAddedConns[object]:Disconnect()
				end
				
				self.toolDescendantAddedConns[object] =
					object.DescendantAdded:Connect(function(toolChild)
						self.cachedParts[toolChild] = nil
						if toolChild:IsA("BasePart") or toolChild:IsA("Decal") then
						-- Reset the transparency
						toolChild.LocalTransparencyModifier = 0
					end
					end)
				
				if self.toolDescendantRemovingConns[object] then
					self.toolDescendantRemovingConns[object]:Disconnect()
				end
				
				self.toolDescendantRemovingConns[object] =
					object.DescendantRemoving:Connect(function(formerToolChild)
						wait() -- wait for new parent
						if character
						and formerToolChild
						and formerToolChild:IsDescendantOf(character) then
						if self:IsValidPartToModify(formerToolChild) then
							self.cachedParts[formerToolChild] = true
							self.transparencyDirty = true
						end
					end
					end)
				
			end
		end)
		
		if self.descendantRemovingConn then
			self.descendantRemovingConn:Disconnect()
		end
		
		self.descendantRemovingConn =
			character.DescendantRemoving:Connect(function(object)
				if self.cachedParts[object] then
				self.cachedParts[object] = nil
				-- Reset the transparency
				object.LocalTransparencyModifier = 0
			end
			end)
		
		self:CachePartsRecursive(character)
	end
	
	
	function TransparencyController:Enable(enable: boolean)
		if self.enabled ~= enable then
			self.enabled = enable
		end
	end
	
	function TransparencyController:SetSubject(subject)
		local character
		
		if subject and subject:IsA("Humanoid") then
			character = subject.Parent
		end
		
		if character then
			self:SetupTransparency(character)
		else
			self:TeardownTransparency()
		end
	end
	
	
	local function round(num: number, places: number): number
		local decimalPivot = 10 ^ places
		return math.floor(num * decimalPivot + 0.5) / decimalPivot
	end
	
	function TransparencyController:Update(dt)
		local camera = cameraHandler.CameraObject
		
		if camera and self.enabled then
			-- calculate goal transparency based on distance
			local distance = (camera.Focus.p - camera.CoordinateFrame.p).Magnitude
			local transparency = (distance < 2) and (1.0 - (distance - 0.5) / 1.5) or 0 -- (7 - distance) / 5
			if transparency < 0.5 then -- too far, don't control transparency
				transparency = 0
			end
			
			-- tween transparency if the goal is not fully transparent and the subject was not fully transparent last frame
			if self.lastTransparency and transparency < 1 and self.lastTransparency < 0.95 then
				local deltaTransparency = transparency - self.lastTransparency
				local maxDelta = MAX_TWEEN_RATE * dt
				deltaTransparency = math.clamp(deltaTransparency, -maxDelta, maxDelta)
				transparency = self.lastTransparency + deltaTransparency
			else
				self.transparencyDirty = true
			end
			
			transparency = math.clamp(round(transparency, 2), 0, 1)
			
			-- update transparencies 
			if self.transparencyDirty or self.lastTransparency ~= transparency then
				for child, _ in next, self.cachedParts do
					child.LocalTransparencyModifier = transparency
				end
				self.transparencyDirty = false
				self.lastTransparency = transparency
			end
		end
	end
	
end

local CameraModule = {} do
	CameraModule.__index = CameraModule
	
	--[[
		CameraModule - This ModuleScript implements a singleton class to manage the
		selection, activation, and deactivation of the current camera controller,
		character occlusion controller, and transparency controller. This script binds to
		RenderStepped at Camera priority and calls the Update() methods on the active
		controller instances.

		The camera controller ModuleScripts implement classes which are instantiated and
		activated as-needed, they are no longer all instantiated up front as they were in
		the previous generation of PlayerScripts.

		2018 PlayerScripts Update - AllYourBlox
	--]]
	
	
	function CameraModule.new()
		local self = setmetatable({}, CameraModule)
		
		self.IsScriptableModeActive = false
		self.CameraController = ClassicCamera.new()
		
		-- Current active controller instances
		self.TransparencyController = TransparencyController.new()
		
		self.TransparencyController:Enable(true)
		
		return self
	end
	
	function CameraModule:SetScriptable(isScriptable)
		self.IsScriptableModeActive = isScriptable
		self.CameraController:Enable(not isScriptable)
	end
	
	function CameraModule:OnCameraSubjectChanged(cameraSubject, cameraType)
		self.TransparencyController:SetSubject(cameraSubject)
		self:SetScriptable(cameraType == Enum.CameraType.Scriptable)
	end
	
	function CameraModule:OnCameraTypeChanged(newCameraType: Enum.CameraType)
		local isScriptable = newCameraType == Enum.CameraType.Scriptable
		
		if isScriptable then
			if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				CameraUtils.restoreMouseBehavior()
			end
		end
		
		self:SetScriptable(isScriptable)
	end
	
	--[[
		Main RenderStep Update. The camera controller and occlusion module both have opportunities
		to set and modify (respectively) the CFrame and Focus before it is set once on CurrentCamera.
		The camera and occlusion modules should only return CFrames, not set the CFrame property of
		CurrentCamera directly.
	--]]
	function CameraModule:Update(dt)
		if self.IsScriptableModeActive then return end
		
		self.CameraController:UpdateMouseBehavior()
		
		local newCameraCFrame, newCameraFocus = self.CameraController:Update(dt)
		
		-- Here is where the new CFrame and Focus are set for this render frame
		local currentCamera = cameraHandler.CameraObject
		currentCamera.CFrame = newCameraCFrame
		currentCamera.Focus = newCameraFocus
		
		-- Update to character local transparency as needed based on camera-to-subject distance
		self.TransparencyController:Update(dt)
		
		if CameraInput.getInputEnabled() then
			CameraInput.resetInputForFrameEnd()
		end
	end
	
end



local BaseCharacterController = {} do
	BaseCharacterController.__index = BaseCharacterController
	
	--[[
		BaseCharacterController - Abstract base class for character controllers, not intended to be
		directly instantiated.

		2018 PlayerScripts Update - AllYourBlox
	--]]
	
	function BaseCharacterController.new()
		local self = setmetatable({}, BaseCharacterController)
		self.enabled = false
		self.moveVector = Vector3.zero
		self.moveVectorIsCameraRelative = true
		self.isJumping = false
		return self
	end
	
	function BaseCharacterController:GetMoveVector(): Vector3
		return self.moveVector
	end
	
	function BaseCharacterController:IsMoveVectorCameraRelative(): boolean
		return self.moveVectorIsCameraRelative
	end
	
	function BaseCharacterController:GetIsJumping(): boolean
		return self.isJumping
	end
	
end


local DynamicThumbstick = setmetatable({}, BaseCharacterController) do
	DynamicThumbstick.__index = DynamicThumbstick
	
	local TOUCH_CONTROLS_SHEET = "rbxasset://textures/ui/Input/TouchControlsSheetV2.png"
	
	local DYNAMIC_THUMBSTICK_ACTION_NAME = "DynamicThumbstickAction"
	local DYNAMIC_THUMBSTICK_ACTION_PRIORITY = Enum.ContextActionPriority.High.Value
	
	local MIDDLE_TRANSPARENCIES = {
		1 - 0.89,
		1 - 0.70,
		1 - 0.60,
		1 - 0.50,
		1 - 0.40,
		1 - 0.30,
		1 - 0.25
	}
	
	local NUM_MIDDLE_IMAGES = #MIDDLE_TRANSPARENCIES
	
	local FADE_IN_OUT_BACKGROUND = true
	local FADE_IN_OUT_MAX_ALPHA = 0.35
	
	local FADE_IN_OUT_HALF_DURATION_DEFAULT = 0.3
	local FADE_IN_OUT_BALANCE_DEFAULT = 0.5
	local ThumbstickFadeTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	
	function DynamicThumbstick.new()
		local self = setmetatable(BaseCharacterController.new(), DynamicThumbstick)
		
		self.moveTouchObject = nil
		self.moveTouchLockedIn = false
		self.moveTouchFirstChanged = false
		self.moveTouchStartPosition = nil
		
		self.startImage = nil
		self.endImage = nil
		self.middleImages = {}
		
		self.startImageFadeTween = nil
		self.endImageFadeTween = nil
		self.middleImageFadeTweens = {}
		
		self.isFirstTouch = true
		
		self.thumbstickFrame = nil
		
		self.onRenderSteppedConn = nil
		
		self.fadeInAndOutBalance = FADE_IN_OUT_BALANCE_DEFAULT
		self.fadeInAndOutHalfDuration = FADE_IN_OUT_HALF_DURATION_DEFAULT
		self.hasFadedBackgroundInPortrait = false
		self.hasFadedBackgroundInLandscape = false
		
		self.tweenInAlphaStart = nil
		self.tweenOutAlphaStart = nil
		
		return self
	end
	
	-- Note: Overrides base class GetIsJumping with get-and-clear behavior to do a single jump
	-- rather than sustained jumping. This is only to preserve the current behavior through the refactor.
	function DynamicThumbstick:GetIsJumping()
		local wasJumping = self.isJumping
		self.isJumping = false
		return wasJumping
	end
	
	function DynamicThumbstick:Enable(enable: boolean?, uiParentFrame): boolean?
		if enable == nil then return false end			-- If nil, return false (invalid argument)
		enable = enable and true or false				-- Force anything non-nil to boolean before comparison
		if self.enabled == enable then return true end	-- If no state change, return true indicating already in requested state
		
		if enable then
			-- Enable
			if not self.thumbstickFrame then
				self:Create(uiParentFrame)
			end
			
			self:BindContextActions()
		else
			ContextActionService:UnbindAction(DYNAMIC_THUMBSTICK_ACTION_NAME)
			self:OnInputEnded()
		end
		
		self.enabled = enable
		self.thumbstickFrame.Visible = enable
		return nil
	end
	
	-- Was called OnMoveTouchEnded in previous version
	function DynamicThumbstick:OnInputEnded()
		self.moveTouchObject = nil
		self.moveVector = Vector3.zero
		self:FadeThumbstick(false)
	end
	
	function DynamicThumbstick:FadeThumbstick(visible: boolean?)
		if not visible and self.moveTouchObject then return end
		if self.isFirstTouch then return end
		
		if self.startImageFadeTween then
			self.startImageFadeTween:Cancel()
		end
		
		if self.endImageFadeTween then
			self.endImageFadeTween:Cancel()
		end
		
		for i = 1, #self.middleImages do
			if self.middleImageFadeTweens[i] then
				self.middleImageFadeTweens[i]:Cancel()
			end
		end
		
		if visible then
			self.startImageFadeTween = TweenService:Create(
				self.startImage,
				ThumbstickFadeTweenInfo,
				{ ImageTransparency = 0 }
			)
			self.startImageFadeTween:Play()
			
			self.endImageFadeTween = TweenService:Create(
				self.endImage,
				ThumbstickFadeTweenInfo,
				{ ImageTransparency = 0.2 }
			)
			self.endImageFadeTween:Play()
			
			for i = 1, #self.middleImages do
				self.middleImageFadeTweens[i] = TweenService:Create(
					self.middleImages[i],
					ThumbstickFadeTweenInfo,
					{ ImageTransparency = MIDDLE_TRANSPARENCIES[i] }
				)
				self.middleImageFadeTweens[i]:Play()
			end
		else
			self.startImageFadeTween = TweenService:Create(
				self.startImage,
				ThumbstickFadeTweenInfo, 
				{ ImageTransparency = 1 }
			)
			self.startImageFadeTween:Play()
			
			self.endImageFadeTween = TweenService:Create(
				self.endImage,
				ThumbstickFadeTweenInfo,
				{ ImageTransparency = 1 }
			)
			self.endImageFadeTween:Play()
			
			for i = 1, #self.middleImages do
				self.middleImageFadeTweens[i] = TweenService:Create(
					self.middleImages[i],
					ThumbstickFadeTweenInfo,
					{ ImageTransparency = 1 }
				)
				self.middleImageFadeTweens[i]:Play()
			end
		end
	end
	
	function DynamicThumbstick:FadeThumbstickFrame(fadeDuration: number, fadeRatio: number)
		self.fadeInAndOutHalfDuration = fadeDuration * 0.5
		self.fadeInAndOutBalance = fadeRatio
		self.tweenInAlphaStart = tick()
	end
	
	function DynamicThumbstick:InputInFrame(inputObject: InputObject)
		local frameCornerTopLeft: Vector2 = self.thumbstickFrame.AbsolutePosition
		local frameCornerBottomRight = frameCornerTopLeft + self.thumbstickFrame.AbsoluteSize
		local inputPosition = inputObject.Position
		if inputPosition.X >= frameCornerTopLeft.X and inputPosition.Y >= frameCornerTopLeft.Y then
			if inputPosition.X <= frameCornerBottomRight.X and inputPosition.Y <= frameCornerBottomRight.Y then
				return true
			end
		end
		return false
	end
	
	function DynamicThumbstick:DoFadeInBackground()
		local playerGui = localPlayerD.PlayerGui
		local hasFadedBackgroundInOrientation = false
		
		-- only fade in/out the background once per orientation
		if playerGui then
			if playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.LandscapeLeft or
				playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.LandscapeRight then
				hasFadedBackgroundInOrientation = self.hasFadedBackgroundInLandscape
				self.hasFadedBackgroundInLandscape = true
			elseif playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.Portrait then
				hasFadedBackgroundInOrientation = self.hasFadedBackgroundInPortrait
				self.hasFadedBackgroundInPortrait = true
			end
		end
		
		if not hasFadedBackgroundInOrientation then
			self.fadeInAndOutHalfDuration = FADE_IN_OUT_HALF_DURATION_DEFAULT
			self.fadeInAndOutBalance = FADE_IN_OUT_BALANCE_DEFAULT
			self.tweenInAlphaStart = tick()
		end
	end
	
	function DynamicThumbstick:DoMove(direction: Vector3)
		local currentMoveVector: Vector3 = direction
		
		-- Scaled Radial Dead Zone
		local inputAxisMagnitude: number = currentMoveVector.Magnitude
		if inputAxisMagnitude < self.radiusOfDeadZone then
			currentMoveVector = Vector3.zero
		else
			currentMoveVector = currentMoveVector.Unit*(
				1 - math.max(0, (self.radiusOfMaxSpeed - currentMoveVector.Magnitude)/self.radiusOfMaxSpeed)
			)
			currentMoveVector = Vector3.new(currentMoveVector.X, 0, currentMoveVector.Y)
		end
		
		self.moveVector = currentMoveVector
	end
	
	
	function DynamicThumbstick:LayoutMiddleImages(startPos: Vector3, endPos: Vector3)
		local startDist = (self.thumbstickSize / 2) + self.middleSize
		local vector = endPos - startPos
		local distAvailable = vector.Magnitude - (self.thumbstickRingSize / 2) - self.middleSize
		local direction = vector.Unit
		
		local distNeeded = self.middleSpacing * NUM_MIDDLE_IMAGES
		local spacing = self.middleSpacing
		
		if distNeeded < distAvailable then
			spacing = distAvailable / NUM_MIDDLE_IMAGES
		end
		
		for i = 1, NUM_MIDDLE_IMAGES do
			local image = self.middleImages[i]
			local distWithout = startDist + (spacing * (i - 2))
			local currentDist = startDist + (spacing * (i - 1))
			
			if distWithout < distAvailable then
				local pos = endPos - direction * currentDist
				local exposedFraction = math.clamp(1 - ((currentDist - distAvailable) / spacing), 0, 1)
				
				image.Visible = true
				image.Position = UDim2.new(0, pos.X, 0, pos.Y)
				image.Size = UDim2.new(0, self.middleSize * exposedFraction, 0, self.middleSize * exposedFraction)
			else
				image.Visible = false
			end
		end
	end
	
	function DynamicThumbstick:MoveStick(pos)
		local vector2StartPosition = Vector2.new(self.moveTouchStartPosition.X, self.moveTouchStartPosition.Y)
		local startPos = vector2StartPosition - self.thumbstickFrame.AbsolutePosition
		local endPos = Vector2.new(pos.X, pos.Y) - self.thumbstickFrame.AbsolutePosition
		self.endImage.Position = UDim2.new(0, endPos.X, 0, endPos.Y)
		self:LayoutMiddleImages(startPos, endPos)
	end
	
	function DynamicThumbstick:BindContextActions()
		local function inputBegan(inputObject)
			if self.moveTouchObject then
				return Enum.ContextActionResult.Pass
			end
			
			if not self:InputInFrame(inputObject) then
				return Enum.ContextActionResult.Pass
			end
			
			if self.isFirstTouch then
				self.isFirstTouch = false
				local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,0,false,0)
				TweenService:Create(self.startImage, tweenInfo, {Size = UDim2.new(0, 0, 0, 0)}):Play()
				TweenService:Create(
					self.endImage,
					tweenInfo,
					{
						Size = UDim2.new(0, self.thumbstickSize, 0, self.thumbstickSize),
						ImageColor3 = Color3.new(0,0,0)
					}
				):Play()
			end
			
			self.moveTouchLockedIn = false
			self.moveTouchObject = inputObject
			self.moveTouchStartPosition = inputObject.Position
			self.moveTouchFirstChanged = true
			
			if FADE_IN_OUT_BACKGROUND then
				self:DoFadeInBackground()
			end
			
			return Enum.ContextActionResult.Pass
		end
		
		local function inputChanged(inputObject: InputObject)
			if inputObject == self.moveTouchObject then
				if self.moveTouchFirstChanged then
					self.moveTouchFirstChanged = false
					
					local startPosVec2 = Vector2.new(
						inputObject.Position.X - self.thumbstickFrame.AbsolutePosition.X,
						inputObject.Position.Y - self.thumbstickFrame.AbsolutePosition.Y
					)
					self.startImage.Visible = true
					self.startImage.Position = UDim2.new(0, startPosVec2.X, 0, startPosVec2.Y)
					self.endImage.Visible = true
					self.endImage.Position = self.startImage.Position
					
					self:FadeThumbstick(true)
					self:MoveStick(inputObject.Position)
				end
				
				self.moveTouchLockedIn = true
				
				local direction = Vector2.new(
					inputObject.Position.X - self.moveTouchStartPosition.X,
					inputObject.Position.Y - self.moveTouchStartPosition.Y
				)
				if math.abs(direction.X) > 0 or math.abs(direction.Y) > 0 then
					self:DoMove(direction)
					self:MoveStick(inputObject.Position)
				end
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end
		
		local function inputEnded(inputObject)
			if inputObject == self.moveTouchObject then
				self:OnInputEnded()
				if self.moveTouchLockedIn then
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end
		
		local function handleInput(actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				return inputBegan(inputObject)
			elseif inputState == Enum.UserInputState.Change then
				return inputChanged(inputObject)
			elseif inputState == Enum.UserInputState.End then
				return inputEnded(inputObject)
			elseif inputState == Enum.UserInputState.Cancel then
				self:OnInputEnded()
			end
		end
		
		ContextActionService:BindActionAtPriority(
			DYNAMIC_THUMBSTICK_ACTION_NAME,
			handleInput,
			false,
			DYNAMIC_THUMBSTICK_ACTION_PRIORITY,
			Enum.UserInputType.Touch)
	end
	
	function DynamicThumbstick:Create(parentFrame: GuiBase2d)
		if self.thumbstickFrame then
			self.thumbstickFrame:Destroy()
			self.thumbstickFrame = nil
			if self.onRenderSteppedConn then
				self.onRenderSteppedConn:Disconnect()
				self.onRenderSteppedConn = nil
			end
		end
		
		self.thumbstickSize = 45
		self.thumbstickRingSize = 20
		self.middleSize = 10
		self.middleSpacing = self.middleSize + 4
		self.radiusOfDeadZone = 2
		self.radiusOfMaxSpeed = 20
		
		local screenSize = parentFrame.AbsoluteSize
		local isBigScreen = math.min(screenSize.X, screenSize.Y) > 500
		if isBigScreen then
			self.thumbstickSize *= 2
			self.thumbstickRingSize *= 2
			self.middleSize *= 2
			self.middleSpacing *= 2
			self.radiusOfDeadZone *= 2
			self.radiusOfMaxSpeed *= 2
		end
		
		local function layoutThumbstickFrame(portraitMode)
			if portraitMode then
				self.thumbstickFrame.Size = UDim2.new(1, 0, 0.4, 0)
				self.thumbstickFrame.Position = UDim2.new(0, 0, 0.6, 0)
			else
				self.thumbstickFrame.Size = UDim2.new(0.4, 0, 2/3, 0)
				self.thumbstickFrame.Position = UDim2.new(0, 0, 1/3, 0)
			end
		end
		
		local thumbstickFrame = Instance.new("Frame")
		thumbstickFrame.BorderSizePixel = 0
		thumbstickFrame.Name = "DynamicThumbstickFrame"
		thumbstickFrame.Visible = false
		thumbstickFrame.BackgroundTransparency = 1.0
		thumbstickFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		thumbstickFrame.Active = false
		self.thumbstickFrame = thumbstickFrame
		layoutThumbstickFrame(false)
		
		local startImage = Instance.new("ImageLabel")
		startImage.Name = "ThumbstickStart"
		startImage.Visible = true
		startImage.BackgroundTransparency = 1
		startImage.Image = TOUCH_CONTROLS_SHEET
		startImage.ImageRectOffset = Vector2.new(1,1)
		startImage.ImageRectSize = Vector2.new(144, 144)
		startImage.ImageColor3 = Color3.new(0, 0, 0)
		startImage.AnchorPoint = Vector2.new(0.5, 0.5)
		startImage.Position = UDim2.new(0, self.thumbstickRingSize * 3.3, 1, -self.thumbstickRingSize * 2.8)
		startImage.Size = UDim2.new(0, self.thumbstickRingSize * 3.7, 0, self.thumbstickRingSize * 3.7)
		startImage.ZIndex = 10
		startImage.Parent = self.thumbstickFrame
		self.startImage = startImage
		
		local endImage = Instance.new("ImageLabel")
		endImage.Name = "ThumbstickEnd"
		endImage.Visible = true
		endImage.BackgroundTransparency = 1
		endImage.Image = TOUCH_CONTROLS_SHEET
		endImage.ImageRectOffset = Vector2.new(1,1)
		endImage.ImageRectSize =  Vector2.new(144, 144)
		endImage.AnchorPoint = Vector2.new(0.5, 0.5)
		endImage.Position = self.startImage.Position
		endImage.Size = UDim2.new(0, self.thumbstickSize * 0.8, 0, self.thumbstickSize * 0.8)
		endImage.ZIndex = 10
		endImage.Parent = self.thumbstickFrame
		self.endImage = endImage
		
		for i = 1, NUM_MIDDLE_IMAGES do
			local image = Instance.new("ImageLabel")
			image.Name = "ThumbstickMiddle"
			image.Visible = false
			image.BackgroundTransparency = 1
			image.Image = TOUCH_CONTROLS_SHEET
			image.ImageRectOffset = Vector2.new(1,1)
			image.ImageRectSize = Vector2.new(144, 144)
			image.ImageTransparency = MIDDLE_TRANSPARENCIES[i]
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.ZIndex = 9
			image.Parent = self.thumbstickFrame
			self.middleImages[i] = image
		end
		
		local camera = cameraHandler.CameraObject
		local function onViewportSizeChanged()
			local size = camera.ViewportSize
			local portraitMode = size.X < size.Y
			layoutThumbstickFrame(portraitMode)
		end
		
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportSizeChanged)
		onViewportSizeChanged()
		
		self.moveTouchStartPosition = nil
		
		self.startImageFadeTween = nil
		self.endImageFadeTween = nil
		self.middleImageFadeTweens = {}
		
		self.onRenderSteppedConn = RunService.RenderStepped:Connect(function()
			if self.tweenInAlphaStart ~= nil then
				local delta = tick() - self.tweenInAlphaStart
				
				local fadeInTime = (self.fadeInAndOutHalfDuration * 2 * self.fadeInAndOutBalance)
				
				self.thumbstickFrame.BackgroundTransparency = 1 - FADE_IN_OUT_MAX_ALPHA
					* math.min(delta / fadeInTime, 1)
				
				if delta > fadeInTime then
					self.tweenOutAlphaStart = tick()
					self.tweenInAlphaStart = nil
				end
				
			elseif self.tweenOutAlphaStart ~= nil then
				local delta = tick() - self.tweenOutAlphaStart
				
				local fadeOutTime = (self.fadeInAndOutHalfDuration * 2)
				- (self.fadeInAndOutHalfDuration * 2 * self.fadeInAndOutBalance)
				
				self.thumbstickFrame.BackgroundTransparency = 1 - FADE_IN_OUT_MAX_ALPHA
					+ FADE_IN_OUT_MAX_ALPHA * math.min(delta / fadeOutTime, 1)
				
				if delta > fadeOutTime  then
					self.tweenOutAlphaStart = nil
				end
			end
		end)
		
		self.onTouchEndedConn = UserInputService.TouchEnded:Connect(function(inputObject: InputObject)
			if inputObject == self.moveTouchObject then
				self:OnInputEnded()
			end
		end)
		
		GuiService.MenuOpened:Connect(function()
			if self.moveTouchObject then
				self:OnInputEnded()
			end
		end)
		
		local playerGui = localPlayerD.PlayerGui
		
		local playerGuiChangedConn = nil
		local originalScreenOrientationWasLandscape =
			playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.LandscapeLeft
			or playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.LandscapeRight
		
		local function longShowBackground()
			self.fadeInAndOutHalfDuration = 2.5
			self.fadeInAndOutBalance = 0.05
			self.tweenInAlphaStart = tick()
		end
		
		playerGuiChangedConn = playerGui:GetPropertyChangedSignal("CurrentScreenOrientation"):Connect(function()
			if (originalScreenOrientationWasLandscape
				and playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.Portrait)
			or (not originalScreenOrientationWasLandscape
				and playerGui.CurrentScreenOrientation ~= Enum.ScreenOrientation.Portrait) then
				
				playerGuiChangedConn:disconnect()
				longShowBackground()
				
				if originalScreenOrientationWasLandscape then
					self.hasFadedBackgroundInPortrait = true
				else
					self.hasFadedBackgroundInLandscape = true
				end
			end
		end)
		
		self.thumbstickFrame.Parent = parentFrame
		
		if game:IsLoaded() then
			longShowBackground()
		else
			coroutine.wrap(function()
				game.Loaded:Wait()
				longShowBackground()
			end)()
		end
	end
	
end

local Keyboard = setmetatable({}, BaseCharacterController) do
	Keyboard.__index = Keyboard
	
	--[[
		Keyboard Character Control - This module handles controlling your avatar from a keyboard

		2018 PlayerScripts Update - AllYourBlox
	--]]
	
	function Keyboard.new(CONTROL_ACTION_PRIORITY)
		local self = setmetatable(BaseCharacterController.new() :: any, Keyboard)
		
		self.CONTROL_ACTION_PRIORITY = CONTROL_ACTION_PRIORITY
		
		self.textFocusReleasedConn = nil
		self.textFocusGainedConn = nil
		self.windowFocusReleasedConn = nil
		
		self.forwardValue  = 0
		self.backwardValue = 0
		self.leftValue = 0
		self.rightValue = 0
		
		self.jumpEnabled = true
		
		return self
	end
	
	function Keyboard:Enable(enable: boolean)
		if not UserInputService.KeyboardEnabled then
			return false
		end
		
		if enable == self.enabled then
			-- Module is already in the state being requested. True is returned here since the module will be in the state
			-- expected by the code that follows the Enable() call. This makes more sense than returning false to indicate
			-- no action was necessary. False indicates failure to be in requested/expected state.
			return true
		end
		
		self.forwardValue  = 0
		self.backwardValue = 0
		self.leftValue = 0
		self.rightValue = 0
		self.moveVector = Vector3.zero
		self.jumpRequested = false
		self:UpdateJump()
		
		if enable then
			self:BindContextActions()
			self:ConnectFocusEventListeners()
		else
			self:UnbindContextActions()
			self:DisconnectFocusEventListeners()
		end
		
		self.enabled = enable
		return true
	end
	
	function Keyboard:UpdateMovement(inputState)
		if inputState == Enum.UserInputState.Cancel then
			self.moveVector = Vector3.zero
		else
			self.moveVector = Vector3.new(
				self.leftValue + self.rightValue,
				0,
				self.forwardValue + self.backwardValue
			)
		end
	end
	
	function Keyboard:UpdateJump()
		self.isJumping = self.jumpRequested
	end
	
	function Keyboard:BindContextActions()
		
		-- Note: In the previous version of this code, the movement values were not zeroed-out on UserInputState. Cancel, now they are,
		-- which fixes them from getting stuck on.
		-- We return ContextActionResult.Pass here for legacy reasons.
		-- Many games rely on gameProcessedEvent being false on UserInputService.InputBegan for these control actions.
		local handleMoveForward = function(actionName, inputState, inputObject)
			self.forwardValue = (inputState == Enum.UserInputState.Begin) and -1 or 0
			self:UpdateMovement(inputState)
			return Enum.ContextActionResult.Pass
		end
		
		local handleMoveBackward = function(actionName, inputState, inputObject)
			self.backwardValue = (inputState == Enum.UserInputState.Begin) and 1 or 0
			self:UpdateMovement(inputState)
			return Enum.ContextActionResult.Pass
		end
		
		local handleMoveLeft = function(actionName, inputState, inputObject)
			self.leftValue = (inputState == Enum.UserInputState.Begin) and -1 or 0
			self:UpdateMovement(inputState)
			return Enum.ContextActionResult.Pass
		end
		
		local handleMoveRight = function(actionName, inputState, inputObject)
			self.rightValue = (inputState == Enum.UserInputState.Begin) and 1 or 0
			self:UpdateMovement(inputState)
			return Enum.ContextActionResult.Pass
		end
		
		local handleJumpAction = function(actionName, inputState, inputObject)
			self.jumpRequested = self.jumpEnabled and (inputState == Enum.UserInputState.Begin)
			self:UpdateJump()
			return Enum.ContextActionResult.Pass
		end
		
		-- TODO: Revert to KeyCode bindings so that in the future the abstraction layer from actual keys to
		-- movement direction is done in Lua
		ContextActionService:BindActionAtPriority("moveForwardAction", handleMoveForward, false,
			self.CONTROL_ACTION_PRIORITY, Enum.PlayerActions.CharacterForward)
		ContextActionService:BindActionAtPriority("moveBackwardAction", handleMoveBackward, false,
			self.CONTROL_ACTION_PRIORITY, Enum.PlayerActions.CharacterBackward)
		ContextActionService:BindActionAtPriority("moveLeftAction", handleMoveLeft, false,
			self.CONTROL_ACTION_PRIORITY, Enum.PlayerActions.CharacterLeft)
		ContextActionService:BindActionAtPriority("moveRightAction", handleMoveRight, false,
			self.CONTROL_ACTION_PRIORITY, Enum.PlayerActions.CharacterRight)
		ContextActionService:BindActionAtPriority("jumpAction", handleJumpAction, false,
			self.CONTROL_ACTION_PRIORITY, Enum.PlayerActions.CharacterJump)
	end
	
	function Keyboard:UnbindContextActions()
		ContextActionService:UnbindAction("moveForwardAction")
		ContextActionService:UnbindAction("moveBackwardAction")
		ContextActionService:UnbindAction("moveLeftAction")
		ContextActionService:UnbindAction("moveRightAction")
		ContextActionService:UnbindAction("jumpAction")
	end
	
	function Keyboard:ConnectFocusEventListeners()
		local function onFocusReleased()
			self.moveVector = Vector3.zero
			self.forwardValue  = 0
			self.backwardValue = 0
			self.leftValue = 0
			self.rightValue = 0
			self.jumpRequested = false
			self:UpdateJump()
		end
		
		local function onTextFocusGained(textboxFocused)
			self.jumpRequested = false
			self:UpdateJump()
		end
		
		self.textFocusReleasedConn = UserInputService.TextBoxFocusReleased:Connect(onFocusReleased)
		self.textFocusGainedConn = UserInputService.TextBoxFocused:Connect(onTextFocusGained)
		self.windowFocusReleasedConn = UserInputService.WindowFocused:Connect(onFocusReleased)
	end
	
	function Keyboard:DisconnectFocusEventListeners()
		if self.textFocusReleasedConn then
			self.textFocusReleasedConn:Disconnect()
			self.textFocusReleasedConn = nil
		end
		if self.textFocusGainedConn then
			self.textFocusGainedConn:Disconnect()
			self.textFocusGainedConn = nil
		end
		if self.windowFocusReleasedConn then
			self.windowFocusReleasedConn:Disconnect()
			self.windowFocusReleasedConn = nil
		end
	end
end

local Gamepad = setmetatable({}, BaseCharacterController) do
	Gamepad.__index = Gamepad
	
	--[[
		Gamepad Character Control - This module handles controlling your avatar using a game console-style controller

		2018 PlayerScripts Update - AllYourBlox
	--]]
	
	local NONE = Enum.UserInputType.None
	local thumbstickDeadzone = 0.2
	
	function Gamepad.new(CONTROL_ACTION_PRIORITY)
		local self = setmetatable(BaseCharacterController.new() :: any, Gamepad)
		
		self.CONTROL_ACTION_PRIORITY = CONTROL_ACTION_PRIORITY
		
		self.forwardValue  = 0
		self.backwardValue = 0
		self.leftValue = 0
		self.rightValue = 0
		
		self.activeGamepad = NONE	-- Enum.UserInputType.Gamepad1, 2, 3...
		self.gamepadConnectedConn = nil
		self.gamepadDisconnectedConn = nil
		return self
	end
	
	function Gamepad:Enable(enable: boolean): boolean
		if not UserInputService.GamepadEnabled then
			return false
		end
		
		if enable == self.enabled then
			-- Module is already in the state being requested. True is returned here since the module will be in the state
			-- expected by the code that follows the Enable() call. This makes more sense than returning false to indicate
			-- no action was necessary. False indicates failure to be in requested/expected state.
			return true
		end
		
		self.forwardValue  = 0
		self.backwardValue = 0
		self.leftValue = 0
		self.rightValue = 0
		self.moveVector = Vector3.zero
		self.isJumping = false
		
		if enable then
			self.activeGamepad = self:GetHighestPriorityGamepad()
			if self.activeGamepad ~= NONE then
				self:BindContextActions()
				self:ConnectGamepadConnectionListeners()
			else
				-- No connected gamepads, failure to enable
				return false
			end
		else
			self:UnbindContextActions()
			self:DisconnectGamepadConnectionListeners()
			self.activeGamepad = NONE
		end
		
		self.enabled = enable
		return true
	end
	
	-- This function selects the lowest number gamepad from the currently-connected gamepad
	-- and sets it as the active gamepad
	function Gamepad:GetHighestPriorityGamepad()
		local connectedGamepads = UserInputService:GetConnectedGamepads()
		local bestGamepad = NONE -- Note that this value is higher than all valid gamepad values
		for _, gamepad in next, connectedGamepads do
			if gamepad.Value < bestGamepad.Value then
				bestGamepad = gamepad
			end
		end
		return bestGamepad
	end
	
	function Gamepad:BindContextActions()
		
		if self.activeGamepad == NONE then
			-- There must be an active gamepad to set up bindings
			return false
		end
		
		local handleJumpAction = function(actionName, inputState, inputObject)
			self.isJumping = (inputState == Enum.UserInputState.Begin)
			return Enum.ContextActionResult.Sink
		end
		
		local handleThumbstickInput = function(actionName, inputState, inputObject)
			
			if inputState == Enum.UserInputState.Cancel then
				self.moveVector = Vector3.zero
				return Enum.ContextActionResult.Sink
			end
			
			if self.activeGamepad ~= inputObject.UserInputType then
				return Enum.ContextActionResult.Pass
			end
			
			if inputObject.KeyCode ~= Enum.KeyCode.Thumbstick1 then return end
			
			if inputObject.Position.magnitude > thumbstickDeadzone then
				self.moveVector = Vector3.new(inputObject.Position.X, 0, -inputObject.Position.Y)
			else
				self.moveVector = Vector3.zero
			end
			
			return Enum.ContextActionResult.Sink
		end
		
		ContextActionService:BindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
		ContextActionService:BindActionAtPriority("jumpAction", handleJumpAction, false,
			self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.ButtonA)
		ContextActionService:BindActionAtPriority("moveThumbstick", handleThumbstickInput, false,
			self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.Thumbstick1)
		
		return true
	end
	
	function Gamepad:UnbindContextActions()
		if self.activeGamepad ~= NONE then
			ContextActionService:UnbindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
		end
		ContextActionService:UnbindAction("moveThumbstick")
		ContextActionService:UnbindAction("jumpAction")
	end
	
	function Gamepad:OnNewGamepadConnected()
		-- A new gamepad has been connected.
		local bestGamepad: Enum.UserInputType = self:GetHighestPriorityGamepad()
		
		if bestGamepad == self.activeGamepad then
			-- A new gamepad was connected, but our active gamepad is not changing
			return
		end
		
		if bestGamepad == NONE then
			-- There should be an active gamepad when GamepadConnected fires, so this should not
			-- normally be hit. If there is no active gamepad, unbind actions but leave
			-- the module enabled and continue to listen for a new gamepad connection.
			warn("Gamepad:OnNewGamepadConnected found no connected gamepads")
			self:UnbindContextActions()
			return
		end
		
		if self.activeGamepad ~= NONE then
			-- Switching from one active gamepad to another
			self:UnbindContextActions()
		end
		
		self.activeGamepad = bestGamepad
		self:BindContextActions()
	end
	
	function Gamepad:OnCurrentGamepadDisconnected()
		if self.activeGamepad ~= NONE then
			ContextActionService:UnbindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
		end
		
		local bestGamepad = self:GetHighestPriorityGamepad()
		
		if self.activeGamepad ~= NONE and bestGamepad == self.activeGamepad then
			warn("Gamepad:OnCurrentGamepadDisconnected found the supposedly disconnected gamepad in connectedGamepads.")
			self:UnbindContextActions()
			self.activeGamepad = NONE
			return
		end
		
		if bestGamepad == NONE then
			-- No active gamepad, unbinding actions but leaving gamepad connection listener active
			self:UnbindContextActions()
			self.activeGamepad = NONE
		else
			-- Set new gamepad as active and bind to tool activation
			self.activeGamepad = bestGamepad
			ContextActionService:BindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
		end
	end
	
	function Gamepad:ConnectGamepadConnectionListeners()
		self.gamepadConnectedConn = UserInputService.GamepadConnected:Connect(function(gamepadEnum)
			self:OnNewGamepadConnected()
		end)
		
		self.gamepadDisconnectedConn = UserInputService.GamepadDisconnected:Connect(function(gamepadEnum)
			if self.activeGamepad == gamepadEnum then
				self:OnCurrentGamepadDisconnected()
			end
		end)
		
	end
	
	function Gamepad:DisconnectGamepadConnectionListeners()
		if self.gamepadConnectedConn then
			self.gamepadConnectedConn:Disconnect()
			self.gamepadConnectedConn = nil
		end
		
		if self.gamepadDisconnectedConn then
			self.gamepadDisconnectedConn:Disconnect()
			self.gamepadDisconnectedConn = nil
		end
	end
	
end

local TouchJump = setmetatable({}, BaseCharacterController) do
	TouchJump.__index = TouchJump
	
	--[[
		// FileName: TouchJump
		// Version 1.0
		// Written by: jmargh
		// Description: Implements jump controls for touch devices. Use with Thumbstick and Thumbpad
	--]]
	
	local TOUCH_CONTROL_SHEET = "rbxasset://textures/ui/Input/TouchControlsSheetV2.png"
	
	function TouchJump.new()
		local self = setmetatable(BaseCharacterController.new() :: any, TouchJump)
		
		self.parentUIFrame = nil
		self.jumpButton = nil
		self.characterAddedConn = nil
		self.humanoidStateEnabledChangedConn = nil
		self.humanoidJumpPowerConn = nil
		self.humanoidParentConn = nil
		self.externallyEnabled = false
		self.jumpPower = 0
		self.jumpStateEnabled = true
		self.isJumping = false
		self.humanoid = nil -- saved reference because property change connections are made using it
		
		return self
	end
	
	function TouchJump:EnableButton(enable)
		if enable then
			if not self.jumpButton then
				self:Create()
			end
			local humanoid = localPlayerD.Humanoid
			if humanoid and self.externallyEnabled then
				if self.externallyEnabled then
					if humanoid.JumpPower > 0 then
						self.jumpButton.Visible = true
					end
				end
			end
		else
			self.jumpButton.Visible = false
			self.isJumping = false
			self.jumpButton.ImageRectOffset = Vector2.new(1, 146)
		end
	end
	
	function TouchJump:UpdateEnabled()
		if self.jumpPower > 0 and self.jumpStateEnabled then
			self:EnableButton(true)
		else
			self:EnableButton(false)
		end
	end
	
	function TouchJump:HumanoidChanged(prop)
		local humanoid = localPlayerD.Humanoid
		if humanoid then
			if prop == "JumpPower" then
				self.jumpPower =  humanoid.JumpPower
				self:UpdateEnabled()
			end
		end
	end
	
	function TouchJump:HumanoidStateEnabledChanged(state, isEnabled)
		if state == Enum.HumanoidStateType.Jumping then
			self.jumpStateEnabled = isEnabled
			self:UpdateEnabled()
		end
	end
	
	function TouchJump:CharacterAdded(char)
		self.humanoid = char:FindFirstChildOfClass("Humanoid")
		while not self.humanoid do
			char.ChildAdded:wait()
			self.humanoid = char:FindFirstChildOfClass("Humanoid")
		end
		
		self.humanoidJumpPowerConn = self.humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
			self.jumpPower = self.humanoid.JumpPower
			self:UpdateEnabled()
		end)
		
		self.humanoidParentConn = self.humanoid:GetPropertyChangedSignal("Parent"):Connect(function()
			if not self.humanoid.Parent then
				self.humanoidJumpPowerConn:Disconnect()
				self.humanoidJumpPowerConn = nil
				self.humanoidParentConn:Disconnect()
				self.humanoidParentConn = nil
			end
		end)
		
		self.humanoidStateEnabledChangedConn = self.humanoid.StateEnabledChanged:Connect(function(state, enabled)
			self:HumanoidStateEnabledChanged(state, enabled)
		end)
		
		self.jumpPower = self.humanoid.JumpPower
		self.jumpStateEnabled = self.humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		self:UpdateEnabled()
	end
	
	function TouchJump:SetupCharacterAddedFunction()
		self.characterAddedConn = localPlayer.CharacterAdded:Connect(function(char)
			self:CharacterAdded(char)
		end)
		if localPlayer.Character then
			self:CharacterAdded(localPlayer.Character)
		end
	end
	
	function TouchJump:Enable(enable, parentFrame)
		if parentFrame then
			self.parentUIFrame = parentFrame
		end
		self.externallyEnabled = enable
		self:EnableButton(enable)
	end
	
	function TouchJump:Create()
		if not self.parentUIFrame then
			return
		end
		
		if self.jumpButton then
			self.jumpButton:Destroy()
			self.jumpButton = nil
		end
		
		local minAxis = math.min(self.parentUIFrame.AbsoluteSize.x, self.parentUIFrame.AbsoluteSize.y)
		local isSmallScreen = minAxis <= 500
		local jumpButtonSize = isSmallScreen and 70 or 120
		
		self.jumpButton = Instance.new("ImageButton")
		self.jumpButton.Name = "JumpButton"
		self.jumpButton.Visible = false
		self.jumpButton.BackgroundTransparency = 1
		self.jumpButton.Image = TOUCH_CONTROL_SHEET
		self.jumpButton.ImageRectOffset = Vector2.new(1, 146)
		self.jumpButton.ImageRectSize = Vector2.new(144, 144)
		self.jumpButton.Size = UDim2.new(0, jumpButtonSize, 0, jumpButtonSize)
		
		self.jumpButton.Position = isSmallScreen
			and UDim2.new(1, -(jumpButtonSize * 1.5 - 10), 1, -jumpButtonSize - 20)
			or UDim2.new(1, -(jumpButtonSize * 1.5 - 10), 1, -jumpButtonSize * 1.75)
		
		local touchObject: InputObject? = nil
		self.jumpButton.InputBegan:Connect(function(inputObject)
			--A touch that starts elsewhere on the screen will be sent to a frame's InputBegan event
			--if it moves over the frame. So we check that this is actually a new touch (inputObject.UserInputState ~= Enum.UserInputState.Begin)
			if touchObject or inputObject.UserInputType ~= Enum.UserInputType.Touch
				or inputObject.UserInputState ~= Enum.UserInputState.Begin then
				return
			end
			
			touchObject = inputObject
			self.jumpButton.ImageRectOffset = Vector2.new(146, 146)
			self.isJumping = true
		end)
		
		local OnInputEnded = function()
			touchObject = nil
			self.isJumping = false
			self.jumpButton.ImageRectOffset = Vector2.new(1, 146)
		end
		
		self.jumpButton.InputEnded:Connect(function(inputObject: InputObject)
			if inputObject == touchObject then
				OnInputEnded()
			end
		end)
		
		GuiService.MenuOpened:Connect(function()
			if touchObject then
				OnInputEnded()
			end
		end)
		
		if not self.characterAddedConn then
			self:SetupCharacterAddedFunction()
		end
		
		self.jumpButton.Parent = self.parentUIFrame
	end
	
end

local TouchThumbstick = setmetatable({}, BaseCharacterController) do
	TouchThumbstick.__index = TouchThumbstick
	
	local TOUCH_CONTROL_SHEET = "rbxasset://textures/ui/TouchControlsSheet.png"
	
	function TouchThumbstick.new()
		local self = setmetatable(BaseCharacterController.new() :: any, TouchThumbstick)
		
		self.isFollowStick = false
		
		self.thumbstickFrame = nil
		self.moveTouchObject = nil
		self.onTouchMovedConn = nil
		self.onTouchEndedConn = nil
		self.screenPos = nil
		self.stickImage = nil
		self.thumbstickSize = nil -- Float
		
		return self
	end
	
	function TouchThumbstick:Enable(enable: boolean?, uiParentFrame)
		-- If nil, return false (invalid argument)
		if enable == nil then return false end
		
		-- Force anything non-nil to boolean before comparison
		enable = enable and true or false
		
		-- If no state change, return true indicating already in requested state
		if self.enabled == enable then return true end
		
		self.moveVector = Vector3.zero
		self.isJumping = false
		
		if enable then
			-- Enable
			if not self.thumbstickFrame then
				self:Create(uiParentFrame)
			end
			self.thumbstickFrame.Visible = true
		else
			-- Disable
			self.thumbstickFrame.Visible = false
			self:OnInputEnded()
		end
		self.enabled = enable
	end
	
	function TouchThumbstick:OnInputEnded()
		self.thumbstickFrame.Position = self.screenPos
		self.stickImage.Position = UDim2.new(
			0,
			self.thumbstickFrame.Size.X.Offset / 2 - self.thumbstickSize / 4,
			0,
			self.thumbstickFrame.Size.Y.Offset / 2 - self.thumbstickSize / 4
		)
		
		self.moveVector = Vector3.zero
		self.isJumping = false
		self.thumbstickFrame.Position = self.screenPos
		self.moveTouchObject = nil
	end
	
	function TouchThumbstick:Create(parentFrame)
		
		if self.thumbstickFrame then
			self.thumbstickFrame:Destroy()
			self.thumbstickFrame = nil
			if self.onTouchMovedConn then
				self.onTouchMovedConn:Disconnect()
				self.onTouchMovedConn = nil
			end
			if self.onTouchEndedConn then
				self.onTouchEndedConn:Disconnect()
				self.onTouchEndedConn = nil
			end
		end
		
		local minAxis = math.min(parentFrame.AbsoluteSize.X, parentFrame.AbsoluteSize.Y)
		local isSmallScreen = minAxis <= 500
		self.thumbstickSize = isSmallScreen and 70 or 120
		self.screenPos = isSmallScreen
			and UDim2.new(0, (self.thumbstickSize / 2) - 10, 1, -self.thumbstickSize - 20)
			or UDim2.new(0, self.thumbstickSize / 2, 1, -self.thumbstickSize * 1.75)
		
		self.thumbstickFrame = Instance.new("Frame")
		self.thumbstickFrame.Name = "ThumbstickFrame"
		self.thumbstickFrame.Active = true
		self.thumbstickFrame.Visible = false
		self.thumbstickFrame.Size = UDim2.new(0, self.thumbstickSize, 0, self.thumbstickSize)
		self.thumbstickFrame.Position = self.screenPos
		self.thumbstickFrame.BackgroundTransparency = 1
		
		local outerImage = Instance.new("ImageLabel")
		outerImage.Name = "OuterImage"
		outerImage.Image = TOUCH_CONTROL_SHEET
		outerImage.ImageRectOffset = Vector2.zero
		outerImage.ImageRectSize = Vector2.new(220, 220)
		outerImage.BackgroundTransparency = 1
		outerImage.Size = UDim2.new(0, self.thumbstickSize, 0, self.thumbstickSize)
		outerImage.Position = UDim2.new(0, 0, 0, 0)
		outerImage.Parent = self.thumbstickFrame
		
		self.stickImage = Instance.new("ImageLabel")
		self.stickImage.Name = "StickImage"
		self.stickImage.Image = TOUCH_CONTROL_SHEET
		self.stickImage.ImageRectOffset = Vector2.new(220, 0)
		self.stickImage.ImageRectSize = Vector2.new(111, 111)
		self.stickImage.BackgroundTransparency = 1
		self.stickImage.Size = UDim2.new(0, self.thumbstickSize / 2, 0, self.thumbstickSize / 2)
		self.stickImage.Position = UDim2.new(
			0,
			self.thumbstickSize / 2 - self.thumbstickSize / 4,
			0,
			self.thumbstickSize / 2 - self.thumbstickSize / 4
		)
		self.stickImage.ZIndex = 2
		self.stickImage.Parent = self.thumbstickFrame
		
		local centerPosition = nil
		local deadZone = 0.05
		
		local function DoMove(direction: Vector2)
			
			local currentMoveVector = direction / (self.thumbstickSize/2)
			
			-- Scaled Radial Dead Zone
			local inputAxisMagnitude = currentMoveVector.magnitude
			if inputAxisMagnitude < deadZone then
				currentMoveVector = Vector3.zero
			else
				currentMoveVector = currentMoveVector.unit * ((inputAxisMagnitude - deadZone) / (1 - deadZone))
				-- NOTE: Making currentMoveVector a unit vector will cause the player to instantly go max speed
				-- must check for zero length vector is using unit
				currentMoveVector = Vector3.new(currentMoveVector.X, 0, currentMoveVector.Y)
			end
			
			self.moveVector = currentMoveVector
		end
		
		local function MoveStick(pos: Vector3)
			local relativePosition = Vector2.new(pos.X - centerPosition.X, pos.Y - centerPosition.Y)
			local length = relativePosition.magnitude
			local maxLength = self.thumbstickFrame.AbsoluteSize.X/2
			if self.isFollowStick and length > maxLength then
				local offset = relativePosition.unit * maxLength
				self.thumbstickFrame.Position = UDim2.new(
					0, pos.X - self.thumbstickFrame.AbsoluteSize.X/2 - offset.X,
					0, pos.Y - self.thumbstickFrame.AbsoluteSize.Y/2 - offset.Y)
			else
				length = math.min(length, maxLength)
				relativePosition = relativePosition.unit * length
			end
			self.stickImage.Position = UDim2.new(
				0,
				relativePosition.X + self.stickImage.AbsoluteSize.X / 2,
				0,
				relativePosition.Y + self.stickImage.AbsoluteSize.Y / 2
			)
		end
		
		-- input connections
		self.thumbstickFrame.InputBegan:Connect(function(inputObject: InputObject)
			--A touch that starts elsewhere on the screen will be sent to a frame's InputBegan event
			--if it moves over the frame. So we check that this is actually a new touch (inputObject.UserInputState ~= Enum.UserInputState.Begin)
			if self.moveTouchObject or inputObject.UserInputType ~= Enum.UserInputType.Touch
				or inputObject.UserInputState ~= Enum.UserInputState.Begin then
				return
			end
			
			self.moveTouchObject = inputObject
			self.thumbstickFrame.Position = UDim2.new(
				0,
				inputObject.Position.X - self.thumbstickFrame.Size.X.Offset / 2,
				0,
				inputObject.Position.Y - self.thumbstickFrame.Size.Y.Offset / 2
			)
			
			centerPosition = Vector2.new(
				self.thumbstickFrame.AbsolutePosition.X + self.thumbstickFrame.AbsoluteSize.X / 2,
				self.thumbstickFrame.AbsolutePosition.Y + self.thumbstickFrame.AbsoluteSize.Y / 2
			)
			
			local direction = Vector2.new(
				inputObject.Position.X - centerPosition.X,
				inputObject.Position.Y - centerPosition.Y
			)
		end)
		
		self.onTouchMovedConn = UserInputService.TouchMoved:Connect(
			function(inputObject: InputObject, isProcessed: boolean)
				if inputObject == self.moveTouchObject then
					centerPosition = Vector2.new(
						self.thumbstickFrame.AbsolutePosition.X + self.thumbstickFrame.AbsoluteSize.X / 2,
						self.thumbstickFrame.AbsolutePosition.Y + self.thumbstickFrame.AbsoluteSize.Y / 2
					)
					local direction = Vector2.new(
						inputObject.Position.X - centerPosition.X,
						inputObject.Position.Y - centerPosition.Y
					)
					DoMove(direction)
					MoveStick(inputObject.Position)
				end
			end
		)
		
		self.onTouchEndedConn = UserInputService.TouchEnded:Connect(function(inputObject, isProcessed)
			if inputObject == self.moveTouchObject then
				self:OnInputEnded()
			end
		end)
		
		GuiService.MenuOpened:Connect(function()
			if self.moveTouchObject then
				self:OnInputEnded()
			end
		end)
		
		self.thumbstickFrame.Parent = parentFrame
	end
	
end


local ControlModule = {} do
	ControlModule.__index = ControlModule
	
	--[[
		ControlModule - This ModuleScript implements a singleton class to manage the
		selection, activation, and deactivation of the current character movement controller.
		This script binds to RenderStepped at Input priority and calls the Update() methods
		on the active controller instances.

		The character controller ModuleScripts implement classes which are instantiated and
		activated as-needed, they are no longer all instantiated up front as they were in
		the previous generation of PlayerScripts.

		2018 PlayerScripts Update - AllYourBlox
	--]]
	
	-- Roblox User Input Control Modules - each returns a new() constructor function used to create controllers as needed
	-- Keyboard, Gamepad, DynamicThumbstick, TouchThumbstick
	
	local HideUserControlsWhenMenuOpen = false
	
	local CONTROL_ACTION_PRIORITY = Enum.ContextActionPriority.Default.Value
	
	-- Mapping from movement mode and lastInputType enum values to control modules to avoid huge if elseif switching
	local movementEnumToModuleMap = {
		[Enum.TouchMovementMode.DPad] = DynamicThumbstick,
		[Enum.DevTouchMovementMode.DPad] = DynamicThumbstick,
		[Enum.TouchMovementMode.Thumbpad] = DynamicThumbstick,
		[Enum.DevTouchMovementMode.Thumbpad] = DynamicThumbstick,
		[Enum.TouchMovementMode.Thumbstick] = TouchThumbstick,
		[Enum.DevTouchMovementMode.Thumbstick] = TouchThumbstick,
		[Enum.TouchMovementMode.DynamicThumbstick] = DynamicThumbstick,
		[Enum.DevTouchMovementMode.DynamicThumbstick] = DynamicThumbstick,
		
		-- Current default
		[Enum.TouchMovementMode.Default] = DynamicThumbstick,
		
		[Enum.ComputerMovementMode.Default] = Keyboard,
		[Enum.ComputerMovementMode.KeyboardMouse] = Keyboard,
		[Enum.DevComputerMovementMode.KeyboardMouse] = Keyboard,
		[Enum.DevComputerMovementMode.Scriptable] = nil,
	}
	
	-- Keyboard controller is really keyboard and mouse controller
	local computerInputTypeToModuleMap = {
		[Enum.UserInputType.Keyboard] = Keyboard,
		[Enum.UserInputType.MouseButton1] = Keyboard,
		[Enum.UserInputType.MouseButton2] = Keyboard,
		[Enum.UserInputType.MouseButton3] = Keyboard,
		[Enum.UserInputType.MouseWheel] = Keyboard,
		[Enum.UserInputType.MouseMovement] = Keyboard,
		[Enum.UserInputType.Gamepad1] = Gamepad,
		[Enum.UserInputType.Gamepad2] = Gamepad,
		[Enum.UserInputType.Gamepad3] = Gamepad,
		[Enum.UserInputType.Gamepad4] = Gamepad,
	}
	
	local lastInputType
	
	function ControlModule.new()
		local self = setmetatable({}, ControlModule)
		
		-- The Modules above are used to construct controller instances as-needed, and this
		-- table is a map from Module to the instance created from it
		self.controllers = {}
		
		self.activeControlModule = nil	-- Used to prevent unnecessarily expensive checks on each input event
		self.activeController = nil
		self.touchJumpController = nil
		self.moveFunction = localPlayer.Move
		
		self.lastInputType = Enum.UserInputType.None
		self.controlsEnabled = true
		
		self.touchControlFrame = nil
		
		if HideUserControlsWhenMenuOpen then
			GuiService.MenuOpened:Connect(function()
				if self.touchControlFrame and self.touchControlFrame.Visible then
					self.touchControlFrame.Visible = false
				end
			end)
			
			GuiService.MenuClosed:Connect(function()
				if self.touchControlFrame then
					self.touchControlFrame.Visible = true
				end
			end)
		end
		
		UserInputService.LastInputTypeChanged:Connect(function(newLastInputType)
			self:OnLastInputTypeChanged(newLastInputType)
		end)
		
		
		UserGameSettings:GetPropertyChangedSignal("TouchMovementMode"):Connect(function()
			self:OnTouchMovementModeChange()
		end)
		
		UserGameSettings:GetPropertyChangedSignal("ComputerMovementMode"):Connect(function()
			self:OnComputerMovementModeChange()
		end)
		
		--[[ Touch Device UI ]]--
		self.touchGui = nil
		
		GuiService:GetPropertyChangedSignal("TouchControlsEnabled"):Connect(function()
			self:UpdateTouchGuiVisibility()
			self:UpdateActiveControlModuleEnabled()
		end)
		
		if localPlayerD.PlayerGui then
			self:OnPlayerGuiAdded()
		end
		
		return self
	end
	
	function ControlModule:OnPlayerGuiAdded()
		if UserInputService.TouchEnabled then
			self:CreateTouchGuiContainer()
			self:OnLastInputTypeChanged(UserInputService:GetLastInputType())
		else
			self:OnLastInputTypeChanged(UserInputService:GetLastInputType())
		end
	end
	
	function ControlModule:GetActiveController()
		return self.activeController
	end
	
	-- Checks for conditions for enabling/disabling the active controller and updates whether the active controller is enabled/disabled
	function ControlModule:UpdateActiveControlModuleEnabled()
		-- helpers for disable/enable
		local disable = function()
			self.activeController:Enable(false)
			
			if self.moveFunction then
				self.moveFunction(localPlayer, Vector3.zero, true)
			end
		end
		
		local enable = function()
			if self.touchControlFrame then
				self.activeController:Enable(true, self.touchControlFrame)
			else
				self.activeController:Enable(true)
			end
		end
		
		-- there is no active controller
		if not self.activeController then
			return
		end
		
		-- developer called ControlModule:Disable(), don't turn back on
		if not self.controlsEnabled then
			disable()
			return
		end
		
		-- GuiService.TouchControlsEnabled == false and the active controller is a touch controller,
		-- disable controls
		if not GuiService.TouchControlsEnabled
			and UserInputService.TouchEnabled
			and (self.activeControlModule == TouchThumbstick
				or self.activeControlModule == DynamicThumbstick)
		then
			disable()
			return
		end
		
		-- no settings prevent enabling controls
		enable()
	end
	
	function ControlModule:Enable(enable: boolean?)
		if enable == nil then
			enable = true
		end
		
		self.controlsEnabled = enable
		
		if not self.activeController then
			return
		end
		
		self:UpdateActiveControlModuleEnabled()
	end
	
	-- For those who prefer distinct functions
	function ControlModule:Disable()
		self.controlsEnabled = false
		
		self:UpdateActiveControlModuleEnabled()
	end
	
	
	-- Returns module (possibly nil) and success code to differentiate returning nil due to error vs Scriptable
	function ControlModule:SelectComputerMovementModule(): ({}?, boolean)
		if not (UserInputService.KeyboardEnabled or UserInputService.GamepadEnabled) then
			return nil, false
		end
		
		local computerModule
		local DevMovementMode = localPlayer.DevComputerMovementMode
		
		if DevMovementMode == Enum.DevComputerMovementMode.UserChoice then
			computerModule = computerInputTypeToModuleMap[lastInputType]
		else
			-- Developer has selected a mode that must be used.
			computerModule = movementEnumToModuleMap[DevMovementMode]
			
			-- computerModule is expected to be nil here only when developer has selected Scriptable
			if (not computerModule)
				and DevMovementMode ~= Enum.DevComputerMovementMode.Scriptable then
				warn("No character control module is associated with DevComputerMovementMode ", DevMovementMode)
			end
		end
		
		if computerModule then
			return computerModule, true
		elseif DevMovementMode == Enum.DevComputerMovementMode.Scriptable then
			-- Special case where nil is returned and we actually want to set self.activeController to nil for Scriptable
			return nil, true
		else
			-- This case is for when computerModule is nil because of an error and no suitable control module could
			-- be found.
			return nil, false
		end
	end
	
	-- Choose current Touch control module based on settings (user, dev)
	-- Returns module (possibly nil) and success code to differentiate returning nil due to error vs Scriptable
	function ControlModule:SelectTouchModule(): ({}?, boolean)
		if not UserInputService.TouchEnabled then
			return nil, false
		end
		
		local touchModule
		local DevMovementMode = localPlayer.DevTouchMovementMode
		
		if DevMovementMode == Enum.DevTouchMovementMode.UserChoice then
			touchModule = movementEnumToModuleMap[UserGameSettings.TouchMovementMode]
		elseif DevMovementMode == Enum.DevTouchMovementMode.Scriptable then
			return nil, true
		else
			touchModule = movementEnumToModuleMap[DevMovementMode]
		end
		
		return touchModule, true
	end
	
	local function calculateRawMoveVector(cameraRelativeMoveVector: Vector3): Vector3
		local camera = cameraHandler.CameraObject
		if not camera then
			return cameraRelativeMoveVector
		end
		
		if localPlayerD.Humanoid:GetState() == Enum.HumanoidStateType.Swimming then
			return camera.CFrame:VectorToWorldSpace(cameraRelativeMoveVector)
		end
		
		local cameraCFrame = camera.CFrame
		
		local c, s
		local _, _, _, R00, R01, R02, _, _, R12, _, _, R22 = cameraCFrame:GetComponents()
		if R12 < 1 and R12 > -1 then
			-- X and Z components from back vector.
			c = R22
			s = R02
		else
			-- In this case the camera is looking straight up or straight down.
			-- Use X components from right and up vectors.
			c = R00
			s = -R01*math.sign(R12)
		end
		local norm = math.sqrt(c*c + s*s)
		return Vector3.new(
			(c*cameraRelativeMoveVector.X + s*cameraRelativeMoveVector.Z)/norm,
			0,
			(c*cameraRelativeMoveVector.Z - s*cameraRelativeMoveVector.X)/norm
		)
	end
	
	function ControlModule:OnRenderStepped(dt)
		if self.activeController and self.activeController.enabled and localPlayerD.Humanoid then
			
			-- Now retrieve info from the controller
			local moveVector = self.activeController.moveVector
			local cameraRelative = self.activeController:IsMoveVectorCameraRelative()
			
			if cameraRelative then
				moveVector = calculateRawMoveVector(moveVector)
			end
			self.moveFunction(localPlayer, moveVector, false)
			
			-- And make them jump if needed
			localPlayerD.Humanoid.Jump = self.activeController:GetIsJumping()
				or (self.touchJumpController and self.touchJumpController:GetIsJumping())
		end
	end
	
	function ControlModule:UpdateTouchGuiVisibility()
		if self.touchGui then
			local doShow = localPlayerD.Humanoid and GuiService.TouchControlsEnabled
			self.touchGui.Enabled = not not doShow -- convert to bool
		end
	end
	
	-- Helper function to lazily instantiate a controller if it does not yet exist,
	-- disable the active controller if it is different from the on being switched to,
	-- and then enable the requested controller. The argument to this function must be
	-- a reference to one of the control modules, i.e. Keyboard, Gamepad, etc.
	
	-- This function should handle all controller enabling and disabling without relying on
	-- ControlModule:Enable() and Disable()
	function ControlModule:SwitchToController(controlModule)
		-- controlModule is invalid, just disable current controller
		if not controlModule then
			if self.activeController then
				self.activeController:Enable(false)
			end
			self.activeController = nil
			self.activeControlModule = nil
			return
		end
		
		-- first time switching to this control module, should instantiate it
		if not self.controllers[controlModule] then
			self.controllers[controlModule] = controlModule.new(CONTROL_ACTION_PRIORITY)
		end
		
		-- switch to the new controlModule
		if self.activeController ~= self.controllers[controlModule] then
			if self.activeController then
				self.activeController:Enable(false)
			end
			self.activeController = self.controllers[controlModule]
			self.activeControlModule = controlModule -- Only used to check if controller switch is necessary
			
			if self.touchControlFrame and (self.activeControlModule == TouchThumbstick
				or self.activeControlModule == DynamicThumbstick) then
				if not self.controllers[TouchJump] then
					self.controllers[TouchJump] = TouchJump.new()
				end
				self.touchJumpController = self.controllers[TouchJump]
				self.touchJumpController:Enable(true, self.touchControlFrame)
			else
				if self.touchJumpController then
					self.touchJumpController:Enable(false)
				end
			end
			
			self:UpdateActiveControlModuleEnabled()
		end
	end
	
	function ControlModule:OnLastInputTypeChanged(newLastInputType)
		if lastInputType == newLastInputType then
			warn("LastInputType Change listener called with current type.")
		end
		lastInputType = newLastInputType
		
		if lastInputType == Enum.UserInputType.Touch then
			-- TODO: Check if touch module already active
			local touchModule, success = self:SelectTouchModule()
			if success then
				while not self.touchControlFrame do
					wait()
				end
				self:SwitchToController(touchModule)
			end
		elseif computerInputTypeToModuleMap[lastInputType] ~= nil then
			local computerModule = self:SelectComputerMovementModule()
			if computerModule then
				self:SwitchToController(computerModule)
			end
		end
		
		self:UpdateTouchGuiVisibility()
	end
	
	-- Called when any relevant values of GameSettings or LocalPlayer change, forcing re-evalulation of
	-- current control scheme
	function ControlModule:OnComputerMovementModeChange()
		local controlModule, success =  self:SelectComputerMovementModule()
		if success then
			self:SwitchToController(controlModule)
		end
	end
	
	function ControlModule:OnTouchMovementModeChange()
		local touchModule, success = self:SelectTouchModule()
		if success then
			while not self.touchControlFrame do
				wait()
			end
			self:SwitchToController(touchModule)
		end
	end
	
	function ControlModule:CreateTouchGuiContainer()
		if self.touchGui then self.touchGui:Destroy() end
		
		-- Container for all touch device guis
		self.touchGui = Instance.new("ScreenGui")
		self.touchGui.Name = "TouchGui"
		self.touchGui.ResetOnSpawn = false
		self.touchGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		self:UpdateTouchGuiVisibility()
		
		self.touchControlFrame = Instance.new("Frame")
		self.touchControlFrame.Name = "TouchControlFrame"
		self.touchControlFrame.Size = UDim2.new(1, 0, 1, 0)
		self.touchControlFrame.BackgroundTransparency = 1
		self.touchControlFrame.Parent = self.touchGui
		
		self.touchGui.Parent = assert(localPlayerD.PlayerGui)
	end
	
end



local PlayerModule = {} do
	PlayerModule.__index = PlayerModule
	
	function PlayerModule.new()
		local self = setmetatable({},PlayerModule)
		
		cameraModule = CameraModule.new()
		controlModule = ControlModule.new()
		
		self.Camera = cameraModule
		self.Control = controlModule
		
		RunService.RenderStepped:Connect(function(dt)
			self.Camera:Update(dt)
			self.Control:OnRenderStepped(dt)
		end)
		
		return self
	end
	
end

return PlayerModule.new()