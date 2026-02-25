local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local activeTweens = {}

local function Tween(params)
	local object = params.Target
	local destination = params.Position
	local constantSpeed = params.ConstantSpeed or {false, 10}
	local easingStyle = params.EasingStyle or Enum.EasingStyle.Linear
	local easingDirection = params.EasingDirection or Enum.EasingDirection.Out
	local travelTime = params.Time or 3
	local showWaypoints = params.ShowWaypoints or false
	local callback = params.Callback

	if activeTweens[object] then
		activeTweens[object].conn:Disconnect()
		for _, m in pairs(activeTweens[object].markers) do
			if m and m.Parent then m:Destroy() end
		end
		activeTweens[object] = nil
	end

	local isModel = object:IsA("Model")
	local startPos = isModel and object:GetPivot().Position or object.Position
	local objectSize = isModel and object:GetExtentsSize() or object.Size
	local startCFrame = isModel and object:GetPivot() or object.CFrame
	local halfExtent = Vector3.new(
		math.max(objectSize.X, objectSize.Z) / 2 + 0.5,
		objectSize.Y / 2 + 0.5,
		math.max(objectSize.X, objectSize.Z) / 2 + 0.5
	)

	local ignoreList = {object}
	if isModel then
		for _, desc in pairs(object:GetDescendants()) do
			if desc:IsA("BasePart") then
				ignoreList[#ignoreList + 1] = desc
			end
		end
	end
	for _, desc in pairs(workspace:GetDescendants()) do
		if desc:IsA("BasePart") and (desc.Position - destination).Magnitude < 3 then
			local isObj = false
			if isModel then
				if desc:IsDescendantOf(object) then isObj = true end
			else
				if desc == object then isObj = true end
			end
			if not isObj then
				ignoreList[#ignoreList + 1] = desc
			end
		end
	end

	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = ignoreList
	rp.FilterType = Enum.RaycastFilterType.Exclude

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = ignoreList
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local function positionBlocked(pos)
		return #workspace:GetPartBoundsInBox(
			CFrame.new(pos),
			objectSize + Vector3.new(0.4, 0.4, 0.4),
			overlapParams
		) > 0
	end

	local function singleRayBlocked(from, to)
		local dir = to - from
		if dir.Magnitude < 0.01 then return false end
		local hit = workspace:Raycast(from, dir, rp)
		if hit then
			return (hit.Position - from).Magnitude < dir.Magnitude - 0.1
		end
		return false
	end

	local function segmentBlocked(from, to)
		local dir = to - from
		if dir.Magnitude < 0.01 then return false end

		if singleRayBlocked(from, to) then return true end

		local forward = dir.Unit
		local right, up
		if math.abs(forward.Y) > 0.95 then
			right = Vector3.new(1, 0, 0)
		else
			right = forward:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude < 0.001 then
				right = Vector3.new(1, 0, 0)
			else
				right = right.Unit
			end
		end
		up = right:Cross(forward)
		if up.Magnitude < 0.001 then
			up = Vector3.new(0, 1, 0)
		else
			up = up.Unit
		end

		local hx = halfExtent.X * 0.8
		local hy = halfExtent.Y * 0.8

		local offsets = {
			right * hx + up * hy,
			right * -hx + up * hy,
			right * hx + up * -hy,
			right * -hx + up * -hy,
			right * hx,
			right * -hx,
			up * hy,
			up * -hy,
			right * hx * 0.5 + up * hy * 0.5,
			right * -hx * 0.5 + up * hy * 0.5,
			right * hx * 0.5 + up * -hy * 0.5,
			right * -hx * 0.5 + up * -hy * 0.5,
		}

		for _, offset in ipairs(offsets) do
			local h = workspace:Raycast(from + offset, dir, rp)
			if h then
				if (h.Position - (from + offset)).Magnitude < dir.Magnitude - 0.1 then
					return true
				end
			end
		end

		local mid = from:Lerp(to, 0.5)
		if positionBlocked(mid) then return true end

		if dir.Magnitude > 4 then
			local q1 = from:Lerp(to, 0.25)
			local q3 = from:Lerp(to, 0.75)
			if positionBlocked(q1) then return true end
			if positionBlocked(q3) then return true end
		end

		if dir.Magnitude > 8 then
			for frac = 0.125, 0.875, 0.125 do
				local pt = from:Lerp(to, frac)
				if positionBlocked(pt) then return true end
			end
		end

		return false
	end

	local function segmentBlockedDense(from, to, stepSize)
		stepSize = stepSize or 1.5
		local dir = to - from
		if dir.Magnitude < 0.01 then return false end

		if singleRayBlocked(from, to) then return true end

		local steps = math.ceil(dir.Magnitude / stepSize)
		for i = 0, steps do
			local t = i / math.max(steps, 1)
			local pt = from:Lerp(to, t)
			if positionBlocked(pt) then return true end
		end

		return segmentBlocked(from, to)
	end

	local function applyEase(t)
		local function eIn(x)
			if easingStyle == Enum.EasingStyle.Linear then return x
			elseif easingStyle == Enum.EasingStyle.Quad then return x * x
			elseif easingStyle == Enum.EasingStyle.Cubic then return x * x * x
			elseif easingStyle == Enum.EasingStyle.Quart then return x * x * x * x
			elseif easingStyle == Enum.EasingStyle.Quint then return x * x * x * x * x
			elseif easingStyle == Enum.EasingStyle.Sine then return 1 - math.cos(x * math.pi / 2)
			elseif easingStyle == Enum.EasingStyle.Exponential then return x == 0 and 0 or 2 ^ (10 * (x - 1))
			elseif easingStyle == Enum.EasingStyle.Circular then return 1 - math.sqrt(1 - x * x)
			elseif easingStyle == Enum.EasingStyle.Back then return x * x * (2.70158 * x - 1.70158)
			elseif easingStyle == Enum.EasingStyle.Elastic then
				if x == 0 or x == 1 then return x end
				return -(2 ^ (10 * x - 10)) * math.sin((x * 10 - 10.75) * 2.094)
			elseif easingStyle == Enum.EasingStyle.Bounce then
				x = 1 - x
				if x < 0.3636 then return 1 - 7.5625 * x * x
				elseif x < 0.7272 then return 1 - (7.5625 * (x - 0.5454) ^ 2 + 0.75)
				elseif x < 0.909 then return 1 - (7.5625 * (x - 0.8181) ^ 2 + 0.9375)
				else return 1 - (7.5625 * (x - 0.9545) ^ 2 + 0.984375) end
			end
			return x
		end
		if easingDirection == Enum.EasingDirection.In then return eIn(t)
		elseif easingDirection == Enum.EasingDirection.Out then return 1 - eIn(1 - t)
		else return t < 0.5 and eIn(t * 2) / 2 or 1 - eIn((1 - t) * 2) / 2 end
	end

	local function tryPathfinding()
		local configs = {
			{AgentRadius = math.max(objectSize.X, objectSize.Z) / 2 + 1, AgentHeight = objectSize.Y + 1, WaypointSpacing = 2},
			{AgentRadius = math.max(objectSize.X, objectSize.Z) / 2 + 0.5, AgentHeight = objectSize.Y, WaypointSpacing = 3},
			{AgentRadius = math.max(objectSize.X, objectSize.Z) / 2, AgentHeight = objectSize.Y, WaypointSpacing = 4},
			{AgentRadius = 1, AgentHeight = objectSize.Y, WaypointSpacing = 4},
		}

		for _, cfg in ipairs(configs) do
			local agentParams = {
				AgentRadius = cfg.AgentRadius,
				AgentHeight = cfg.AgentHeight,
				AgentCanJump = true,
				AgentCanClimb = true,
				WaypointSpacing = cfg.WaypointSpacing,
			}

			local path = PathfindingService:CreatePath(agentParams)
			local success, _ = pcall(function()
				path:ComputeAsync(startPos, destination)
			end)

			if success and path.Status == Enum.PathStatus.Success then
				local wps = path:GetWaypoints()
				local points = {}
				for _, wp in ipairs(wps) do
					points[#points + 1] = wp.Position
				end

				local valid = true
				for i = 2, #points do
					if segmentBlocked(points[i - 1], points[i]) then
						valid = false
						break
					end
				end

				if valid and #points >= 2 then
					return points
				end
			end
		end

		return nil
	end

	local function tryAStar(gridSize)
		local dirs26 = {}
		for x = -1, 1 do
			for y = -1, 1 do
				for z = -1, 1 do
					if not (x == 0 and y == 0 and z == 0) then
						dirs26[#dirs26 + 1] = {x, y, z, math.sqrt(x * x + y * y + z * z)}
					end
				end
			end
		end

		local gs = gridSize

		local function gWorld(gx, gy, gz)
			return Vector3.new(gx * gs, gy * gs, gz * gs)
		end

		local nbCache = {}
		local function nodeBlk(gx, gy, gz)
			local k = gx * 73856093 + gy * 19349663 + gz * 83492791
			if nbCache[k] ~= nil then return nbCache[k] end
			local w = gWorld(gx, gy, gz)
			local checkSize = objectSize + Vector3.new(gs * 0.3, gs * 0.3, gs * 0.3)
			local result = #workspace:GetPartBoundsInBox(CFrame.new(w), checkSize, overlapParams) > 0
			nbCache[k] = result
			return result
		end

		local function edgeClear(x1, y1, z1, x2, y2, z2)
			return not singleRayBlocked(gWorld(x1, y1, z1), gWorld(x2, y2, z2))
		end

		local sx = math.round(startPos.X / gs)
		local sy = math.round(startPos.Y / gs)
		local sz = math.round(startPos.Z / gs)
		local ex = math.round(destination.X / gs)
		local ey = math.round(destination.Y / gs)
		local ez = math.round(destination.Z / gs)

		local function nudgeOut(nx, ny, nz)
			if not nodeBlk(nx, ny, nz) then return nx, ny, nz end
			for r = 1, 8 do
				for _, d in ipairs(dirs26) do
					local tx, ty, tz = nx + d[1] * r, ny + d[2] * r, nz + d[3] * r
					if not nodeBlk(tx, ty, tz) then
						return tx, ty, tz
					end
				end
			end
			return nx, ny, nz
		end

		sx, sy, sz = nudgeOut(sx, sy, sz)
		ex, ey, ez = nudgeOut(ex, ey, ez)

		local heap = {}
		local hn = 0
		local function heapPush(n)
			hn = hn + 1; heap[hn] = n
			local i = hn
			while i > 1 do
				local p = math.floor(i / 2)
				if heap[p].f > heap[i].f then
					heap[p], heap[i] = heap[i], heap[p]; i = p
				else break end
			end
		end
		local function heapPop()
			if hn == 0 then return nil end
			local top = heap[1]; heap[1] = heap[hn]; heap[hn] = nil; hn = hn - 1
			local i = 1
			while true do
				local lc, rc, s = i * 2, i * 2 + 1, i
				if lc <= hn and heap[lc].f < heap[s].f then s = lc end
				if rc <= hn and heap[rc].f < heap[s].f then s = rc end
				if s == i then break end
				heap[i], heap[s] = heap[s], heap[i]; i = s
			end
			return top
		end

		local function hashKey(gx, gy, gz)
			return gx * 73856093 + gy * 19349663 + gz * 83492791
		end

		local sk = hashKey(sx, sy, sz)
		local gScore = {[sk] = 0}
		local parentMap = {}
		local gPos = {[sk] = {sx, sy, sz}}
		local closed = {}

		heapPush({x = sx, y = sy, z = sz, k = sk, f = 0})

		local found = false
		local foundKey = nil
		local earlyExitToDestination = false
		local maxIter = 100000

		for _iter = 1, maxIter do
			if hn == 0 then break end
			local cur = heapPop()
			if not cur then break end
			if closed[cur.k] then continue end
			closed[cur.k] = true

			if cur.x == ex and cur.y == ey and cur.z == ez then
				found = true; foundKey = cur.k; break
			end

			local distToEnd = math.abs(cur.x - ex) + math.abs(cur.y - ey) + math.abs(cur.z - ez)
			if distToEnd <= 5 then
				local cw = gWorld(cur.x, cur.y, cur.z)
				if not segmentBlocked(cw, destination) then
					found = true; foundKey = cur.k; earlyExitToDestination = true; break
				end
			end

			local cg = gScore[cur.k]

			for _, d in ipairs(dirs26) do
				local nx, ny, nz = cur.x + d[1], cur.y + d[2], cur.z + d[3]
				local nk = hashKey(nx, ny, nz)
				if closed[nk] then continue end
				if nodeBlk(nx, ny, nz) then continue end

				local dominated = false
				if d[1] ~= 0 and d[2] ~= 0 then
					if nodeBlk(cur.x + d[1], cur.y, cur.z) or nodeBlk(cur.x, cur.y + d[2], cur.z) then dominated = true end
				end
				if d[1] ~= 0 and d[3] ~= 0 then
					if nodeBlk(cur.x + d[1], cur.y, cur.z) or nodeBlk(cur.x, cur.y, cur.z + d[3]) then dominated = true end
				end
				if d[2] ~= 0 and d[3] ~= 0 then
					if nodeBlk(cur.x, cur.y + d[2], cur.z) or nodeBlk(cur.x, cur.y, cur.z + d[3]) then dominated = true end
				end
				if d[1] ~= 0 and d[2] ~= 0 and d[3] ~= 0 then
					if nodeBlk(cur.x + d[1], cur.y, cur.z)
						or nodeBlk(cur.x, cur.y + d[2], cur.z)
						or nodeBlk(cur.x, cur.y, cur.z + d[3])
						or nodeBlk(cur.x + d[1], cur.y + d[2], cur.z)
						or nodeBlk(cur.x + d[1], cur.y, cur.z + d[3])
						or nodeBlk(cur.x, cur.y + d[2], cur.z + d[3]) then
						dominated = true
					end
				end
				if dominated then continue end

				if not edgeClear(cur.x, cur.y, cur.z, nx, ny, nz) then continue end

				local ng = cg + d[4]
				if not gScore[nk] or ng < gScore[nk] then
					gScore[nk] = ng
					parentMap[nk] = cur.k
					gPos[nk] = {nx, ny, nz}
					local dx2, dy2, dz2 = math.abs(nx - ex), math.abs(ny - ey), math.abs(nz - ez)
					local h = math.sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2)
					heapPush({x = nx, y = ny, z = nz, k = nk, f = ng + h * 1.001})
				end
			end
		end

		if found and foundKey then
			local rev = {}
			local tk = foundKey
			while tk do
				local g = gPos[tk]
				if g then rev[#rev + 1] = gWorld(g[1], g[2], g[3]) end
				tk = parentMap[tk]
			end
			local chain = {}
			for i = #rev, 1, -1 do chain[#chain + 1] = rev[i] end
			if earlyExitToDestination then
				chain[#chain + 1] = destination
			end
			return chain
		end

		return nil
	end

	local function tryWallHug()
		local stepSize = math.max(objectSize.X, objectSize.Z) * 0.8 + 0.5
		local maxSteps = 500

		local bestPath = nil
		local bestDist = math.huge

		local dodgeDirs = {}
		local mainDir = (destination - startPos)
		local mainFlat = Vector3.new(mainDir.X, 0, mainDir.Z)
		if mainFlat.Magnitude < 0.1 then mainFlat = Vector3.new(1, 0, 0) end
		mainFlat = mainFlat.Unit

		for angle = 0, 315, 45 do
			local rad = math.rad(angle)
			local rotated = Vector3.new(
				mainFlat.X * math.cos(rad) - mainFlat.Z * math.sin(rad),
				0,
				mainFlat.X * math.sin(rad) + mainFlat.Z * math.cos(rad)
			)
			dodgeDirs[#dodgeDirs + 1] = rotated
		end

		for _, initialDodge in ipairs(dodgeDirs) do
			local points = {startPos}
			local pos = startPos
			local heading = (destination - startPos)
			heading = Vector3.new(heading.X, 0, heading.Z)
			if heading.Magnitude > 0.1 then heading = heading.Unit else heading = initialDodge end

			local stuckTotal = 0

			for _step = 1, maxSteps do
				if not segmentBlocked(pos, destination) then
					points[#points + 1] = destination
					local totalLen = 0
					for i = 2, #points do
						totalLen = totalLen + (points[i] - points[i - 1]).Magnitude
					end
					if totalLen < bestDist then
						bestDist = totalLen
						bestPath = {}
						for _, p in ipairs(points) do bestPath[#bestPath + 1] = p end
					end
					break
				end

				local fwd = pos + heading * stepSize
				if not segmentBlocked(pos, fwd) and not positionBlocked(fwd) then
					pos = fwd
					points[#points + 1] = pos
					stuckTotal = 0

					local toGoal = destination - pos
					local flatGoal = Vector3.new(toGoal.X, 0, toGoal.Z)
					if flatGoal.Magnitude > 0.5 then
						heading = flatGoal.Unit
					end
				else
					local foundDir = false
					local bestAngle = nil
					local bestAngleDist = math.huge

					for angleDeg = 15, 180, 15 do
						for _, sign in ipairs({1, -1}) do
							local rad = math.rad(angleDeg * sign)
							local rotated = Vector3.new(
								heading.X * math.cos(rad) - heading.Z * math.sin(rad),
								0,
								heading.X * math.sin(rad) + heading.Z * math.cos(rad)
							)
							local testPos = pos + rotated * stepSize
							if not segmentBlocked(pos, testPos) and not positionBlocked(testPos) then
								local distToGoal = (testPos - destination).Magnitude
								if distToGoal < bestAngleDist then
									bestAngleDist = distToGoal
									bestAngle = rotated
								end
								if not foundDir then foundDir = true end
							end
						end
					end

					if not foundDir then
						for yOff = -2, 2 do
							if yOff ~= 0 then
								local upPos = pos + Vector3.new(0, yOff * stepSize, 0)
								if not segmentBlocked(pos, upPos) and not positionBlocked(upPos) then
									local fwdFromUp = upPos + heading * stepSize
									if not segmentBlocked(upPos, fwdFromUp) and not positionBlocked(fwdFromUp) then
										points[#points + 1] = upPos
										points[#points + 1] = fwdFromUp
										pos = fwdFromUp
										foundDir = true
										break
									end
								end
							end
						end
					end

					if foundDir and bestAngle then
						heading = bestAngle
						local testPos = pos + heading * stepSize
						if not segmentBlocked(pos, testPos) and not positionBlocked(testPos) then
							pos = testPos
							points[#points + 1] = pos
						end
						stuckTotal = 0
					else
						stuckTotal = stuckTotal + 1
						if stuckTotal > 20 then break end
					end
				end

				if (pos - destination).Magnitude < stepSize then
					if not segmentBlocked(pos, destination) then
						points[#points + 1] = destination
						local totalLen = 0
						for i = 2, #points do
							totalLen = totalLen + (points[i] - points[i - 1]).Magnitude
						end
						if totalLen < bestDist then
							bestDist = totalLen
							bestPath = {}
							for _, p in ipairs(points) do bestPath[#bestPath + 1] = p end
						end
						break
					end
				end
			end
		end

		return bestPath
	end

	local function tryBreadcrumbFlood()
		local stepSize = math.max(objectSize.X, objectSize.Z) + 1
		local maxNodes = 30000

		local queue = {}
		local qHead = 1
		local visited = {}
		local parentBc = {}
		local posBc = {}

		local function posKey(p)
			local gx = math.round(p.X / stepSize)
			local gy = math.round(p.Y / stepSize)
			local gz = math.round(p.Z / stepSize)
			return gx .. "," .. gy .. "," .. gz
		end

		local sk = posKey(startPos)
		queue[1] = {pos = startPos, key = sk}
		visited[sk] = true
		posBc[sk] = startPos

		local foundKey = nil
		local nodeCount = 0

		local dirs = {}
		for x = -1, 1 do
			for y = -1, 1 do
				for z = -1, 1 do
					if not (x == 0 and y == 0 and z == 0) then
						dirs[#dirs + 1] = Vector3.new(x, y, z) * stepSize
					end
				end
			end
		end

		while qHead <= #queue and nodeCount < maxNodes do
			local cur = queue[qHead]
			qHead = qHead + 1
			nodeCount = nodeCount + 1

			if not segmentBlocked(cur.pos, destination) then
				foundKey = cur.key
				break
			end

			for _, d in ipairs(dirs) do
				local np = cur.pos + d
				local nk = posKey(np)
				if visited[nk] then continue end
				if positionBlocked(np) then visited[nk] = true; continue end
				if segmentBlocked(cur.pos, np) then visited[nk] = true; continue end

				visited[nk] = true
				parentBc[nk] = cur.key
				posBc[nk] = np
				queue[#queue + 1] = {pos = np, key = nk}
			end
		end

		if foundKey then
			local rev = {}
			local tk = foundKey
			while tk do
				if posBc[tk] then rev[#rev + 1] = posBc[tk] end
				tk = parentBc[tk]
			end
			rev[#rev + 1] = startPos

			local chain = {}
			for i = #rev, 1, -1 do chain[#chain + 1] = rev[i] end
			chain[#chain + 1] = destination
			return chain
		end

		return nil
	end

	local function simplifyPath(points)
		if #points <= 2 then return points end

		local simp = {points[1]}
		local i = 1
		while i < #points do
			local best = i + 1
			for j = #points, i + 2, -1 do
				if not segmentBlockedDense(points[i], points[j], 1.0) then
					best = j
					break
				end
			end
			simp[#simp + 1] = points[best]
			i = best
		end
		return simp
	end

	local function catmullRom(p0, p1, p2, p3, t)
		local t2 = t * t
		local t3 = t2 * t
		return 0.5 * (
			(2 * p1) +
			(-p0 + p2) * t +
			(2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
			(-p0 + 3 * p1 - 3 * p2 + p3) * t3
		)
	end

	local function catmullRomV3(p0, p1, p2, p3, t)
		return Vector3.new(
			catmullRom(p0.X, p1.X, p2.X, p3.X, t),
			catmullRom(p0.Y, p1.Y, p2.Y, p3.Y, t),
			catmullRom(p0.Z, p1.Z, p2.Z, p3.Z, t)
		)
	end

	local function splineSmoothPath(points, subdivisions)
		if #points < 3 then return points end
		subdivisions = subdivisions or 6

		local ctrl = {}
		ctrl[1] = points[1] + (points[1] - points[2])
		for i = 1, #points do
			ctrl[#ctrl + 1] = points[i]
		end
		ctrl[#ctrl + 1] = points[#points] + (points[#points] - points[#points - 1])

		local smoothed = {points[1]}

		for i = 2, #ctrl - 2 do
			local p0 = ctrl[i - 1]
			local p1 = ctrl[i]
			local p2 = ctrl[i + 1]
			local p3 = ctrl[i + 2]

			for s = 1, subdivisions do
				local t = s / subdivisions
				local pt = catmullRomV3(p0, p1, p2, p3, t)
				smoothed[#smoothed + 1] = pt
			end
		end

		smoothed[1] = points[1]
		smoothed[#smoothed] = points[#points]

		return smoothed
	end

	local function safeSmooth(points, subdivisions)
		subdivisions = subdivisions or 8

		local smoothed = splineSmoothPath(points, subdivisions)

		local safe = {smoothed[1]}
		for i = 2, #smoothed do
			if not segmentBlocked(safe[#safe], smoothed[i]) and not positionBlocked(smoothed[i]) then
				safe[#safe + 1] = smoothed[i]
			else
				local bestOrigIdx = 1
				local bestDist = math.huge
				for j = 1, #points do
					local d = (points[j] - smoothed[i]).Magnitude
					if d < bestDist then
						bestDist = d; bestOrigIdx = j
					end
				end

				local fallback = points[bestOrigIdx]
				if not segmentBlocked(safe[#safe], fallback) then
					safe[#safe + 1] = fallback
				else
					local stepDir = (fallback - safe[#safe])
					if stepDir.Magnitude > 0.5 then
						local microSteps = math.ceil(stepDir.Magnitude / 1.0)
						for ms = 1, microSteps do
							local microPt = safe[#safe]:Lerp(fallback, ms / microSteps)
							if not positionBlocked(microPt) and not segmentBlocked(safe[#safe], microPt) then
								safe[#safe + 1] = microPt
							else
								break
							end
						end
					end
				end
			end
		end

		if (safe[#safe] - points[#points]).Magnitude > 0.3 then
			if not segmentBlocked(safe[#safe], points[#points]) then
				safe[#safe + 1] = points[#points]
			end
		end
		safe[1] = points[1]
		safe[#safe] = points[#points]

		return safe
	end

	local function repairSegment(from, to)
		local dir = to - from
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		local perp
		if flatDir.Magnitude > 0.1 then
			perp = Vector3.new(-flatDir.Unit.Z, 0, flatDir.Unit.X)
		else
			perp = Vector3.new(1, 0, 0)
		end

		local mid = from:Lerp(to, 0.5)

		for dist = 2, 30, 1.5 do
			for _, sign in ipairs({1, -1}) do
				for yOff = -2, 2 do
					local offset = perp * (dist * sign) + Vector3.new(0, yOff * 2, 0)
					local detourPt = mid + offset

					if not positionBlocked(detourPt)
						and not segmentBlocked(from, detourPt)
						and not segmentBlocked(detourPt, to) then
						return {detourPt}
					end

					local d1 = from:Lerp(to, 0.33) + offset
					local d2 = from:Lerp(to, 0.66) + offset
					if not positionBlocked(d1) and not positionBlocked(d2)
						and not segmentBlocked(from, d1)
						and not segmentBlocked(d1, d2)
						and not segmentBlocked(d2, to) then
						return {d1, d2}
					end

					local d0 = from:Lerp(to, 0.25) + offset * 0.5
					local dm = mid + offset
					local d3 = from:Lerp(to, 0.75) + offset * 0.5
					if not positionBlocked(d0) and not positionBlocked(dm) and not positionBlocked(d3)
						and not segmentBlocked(from, d0)
						and not segmentBlocked(d0, dm)
						and not segmentBlocked(dm, d3)
						and not segmentBlocked(d3, to) then
						return {d0, dm, d3}
					end
				end
			end
		end

		return nil
	end

	local waypoints

	if not segmentBlocked(startPos, destination) then
		waypoints = {startPos, destination}
	else

		waypoints = tryPathfinding()

		if not waypoints then
			local gridSizes = {10, 8, 6, 4, 3, 2, 1.5}
			for _, gs in ipairs(gridSizes) do
				local chain = tryAStar(gs)
				if chain and #chain >= 2 then
					local valid = true
					for i = 2, #chain do
						if positionBlocked(chain[i]) then
							valid = false; break
						end
					end
					if valid then
						waypoints = chain
						break
					end
				end
			end
		end

		if waypoints and #waypoints >= 2 then
			local raw = {startPos}
			for _, p in ipairs(waypoints) do
				if (p - raw[#raw]).Magnitude > 0.3 then
					raw[#raw + 1] = p
				end
			end
			if (raw[#raw] - destination).Magnitude > 0.3 then
				raw[#raw + 1] = destination
			end
			raw[#raw] = destination
			waypoints = raw
		end

		if not waypoints then
			local hugPath = tryWallHug()
			if hugPath and #hugPath >= 2 then
				waypoints = hugPath
			end
		end

		if not waypoints then
			local bfPath = tryBreadcrumbFlood()
			if bfPath and #bfPath >= 2 then
				waypoints = bfPath
			end
		end

		if not waypoints then
			warn("[SmartTween] All 4 pathfinding methods failed.")
			if callback then callback() end
			return {Cancel = function() end, Points = {startPos}}
		end
	end

	local repaired = {waypoints[1]}
	for i = 2, #waypoints do
		local prev = repaired[#repaired]
		local curr = waypoints[i]

		if not segmentBlocked(prev, curr) then
			repaired[#repaired + 1] = curr
		else
			local detour = repairSegment(prev, curr)
			if detour then
				for _, dp in ipairs(detour) do
					repaired[#repaired + 1] = dp
				end
				repaired[#repaired + 1] = curr
			else
				local stepDir = curr - prev
				local numMicro = math.ceil(stepDir.Magnitude / 0.5)
				local lastGood = prev
				for ms = 1, numMicro do
					local microPt = prev:Lerp(curr, ms / numMicro)
					if not segmentBlocked(lastGood, microPt) and not positionBlocked(microPt) then
						lastGood = microPt
						repaired[#repaired + 1] = microPt
					else
						local found = false
						for ox = -2, 2 do
							for oz = -2, 2 do
								if ox ~= 0 or oz ~= 0 then
									local offset = Vector3.new(ox, 0, oz)
									local testPt = microPt + offset
									if not positionBlocked(testPt) and not segmentBlocked(lastGood, testPt) then
										lastGood = testPt
										repaired[#repaired + 1] = testPt
										found = true
										break
									end
								end
							end
							if found then break end
						end
					end
				end
				if not segmentBlocked(repaired[#repaired], curr) then
					repaired[#repaired + 1] = curr
				end
			end
		end
	end

	if (repaired[#repaired] - destination).Magnitude > 0.5 then
		if not segmentBlocked(repaired[#repaired], destination) then
			repaired[#repaired + 1] = destination
		end
	end
	repaired[1] = startPos
	repaired[#repaired] = destination
	waypoints = repaired

	waypoints = simplifyPath(waypoints)
	waypoints[1] = startPos
	waypoints[#waypoints] = destination

	if #waypoints >= 3 then
		waypoints = safeSmooth(waypoints, 10)
	end

	local clean = {waypoints[1]}
	for i = 2, #waypoints do
		if (waypoints[i] - clean[#clean]).Magnitude > 0.15 then
			clean[#clean + 1] = waypoints[i]
		end
	end
	waypoints = clean

	if #waypoints < 2 then
		waypoints = {startPos, destination}
	end

	waypoints[1] = startPos
	waypoints[#waypoints] = destination

	local markers = {}
	if showWaypoints then
		for _, c in pairs(workspace:GetChildren()) do
			if c.Name:sub(1, 12) == "SmartTweenWP" then c:Destroy() end
		end
		for i, pos in ipairs(waypoints) do
			local m = Instance.new("Part")
			m.Name = "SmartTweenWP_" .. i
			m.Anchored = true
			m.CanCollide = false
			m.CastShadow = false
			m.Material = Enum.Material.Neon
			m.Shape = Enum.PartType.Ball
			m.Transparency = 0.3
			m.Size = Vector3.new(1.2, 1.2, 1.2)
			m.Position = pos
			if i == 1 then
				m.Color = Color3.fromRGB(0, 120, 255)
			elseif i == #waypoints then
				m.Color = Color3.fromRGB(255, 0, 0)
			else
				local frac = (i - 1) / (#waypoints - 1)
				m.Color = Color3.fromRGB(
					math.floor(frac * 255),
					math.floor((1 - frac) * 255),
					100
				)
			end
			m.Parent = workspace
			markers[i] = m
		end
	end

	local totalDist = 0
	local segLens = {}
	local cumDist = {0}
	for i = 2, #waypoints do
		local l = (waypoints[i] - waypoints[i - 1]).Magnitude
		segLens[i] = l
		totalDist = totalDist + l
		cumDist[i] = totalDist
	end

	if totalDist < 0.01 then
		for _, m in pairs(markers) do if m and m.Parent then m:Destroy() end end
		if callback then callback() end
		return {Cancel = function() end, Points = waypoints}
	end

	local totalTime = constantSpeed[1] and totalDist / math.max(constantSpeed[2], 0.1) or travelTime
	local elapsed = 0
	local lastIdx = 1
	local curSeg = 2
	local conn

	local signal = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
	conn = signal:Connect(function(dt)
		if not object or not object.Parent then
			conn:Disconnect()
			for _, m in pairs(markers) do if m and m.Parent then m:Destroy() end end
			activeTweens[object] = nil
			return
		end

		elapsed = math.min(elapsed + dt, totalTime)
		local td = applyEase(elapsed / totalTime) * totalDist

		while curSeg < #waypoints and cumDist[curSeg] < td do curSeg = curSeg + 1 end
		while curSeg > 2 and cumDist[curSeg - 1] > td do curSeg = curSeg - 1 end

		local segStart = cumDist[curSeg - 1] or 0
		local segLen = segLens[curSeg] or 0
		local segT = segLen > 0 and (td - segStart) / segLen or 0
		local pos = waypoints[curSeg - 1]:Lerp(waypoints[curSeg], math.clamp(segT, 0, 1))

		if showWaypoints then
			for i = lastIdx, curSeg - 1 do
				if markers[i] and markers[i].Parent then
					markers[i]:Destroy()
					markers[i] = nil
				end
			end
			lastIdx = curSeg
		end

		if isModel then
			object:PivotTo(CFrame.new(pos) * startCFrame.Rotation)
		else
			object.CFrame = CFrame.new(pos) * startCFrame.Rotation
		end

		if elapsed >= totalTime then
			local finalPos = waypoints[#waypoints]
			if isModel then
				object:PivotTo(CFrame.new(finalPos) * startCFrame.Rotation)
			else
				object.CFrame = CFrame.new(finalPos) * startCFrame.Rotation
			end
			for _, m in pairs(markers) do if m and m.Parent then m:Destroy() end end
			conn:Disconnect()
			activeTweens[object] = nil
			if callback then callback() end
		end
	end)

	activeTweens[object] = {conn = conn, markers = markers}
	return {
		Cancel = function()
			conn:Disconnect()
			for _, m in pairs(markers) do if m and m.Parent then m:Destroy() end end
			activeTweens[object] = nil
		end,
		Points = waypoints
	}
end

local function Cancel(obj)
	if activeTweens[obj] then
		activeTweens[obj].conn:Disconnect()
		for _, m in pairs(activeTweens[obj].markers) do if m and m.Parent then m:Destroy() end end
		activeTweens[obj] = nil
	end
end

local function CancelAll()
	for _, data in pairs(activeTweens) do
		data.conn:Disconnect()
		for _, m in pairs(data.markers) do if m and m.Parent then m:Destroy() end end
	end
	activeTweens = {}
end

SmartTween = setmetatable({Tween = Tween, Cancel = Cancel, CancelAll = CancelAll}, {
	__call = function(_, p) return Tween(p) end
})
