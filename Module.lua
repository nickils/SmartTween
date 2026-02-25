local RunService = game:GetService("RunService")
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
		for _, m in activeTweens[object].markers do
			if m and m.Parent then m:Destroy() end
		end
		activeTweens[object] = nil
	end

	local isModel = object:IsA("Model")
	local startPos = isModel and object:GetPivot().Position or object.Position
	local objectSize = isModel and object:GetExtentsSize() or object.Size
	local startCFrame = isModel and object:GetPivot() or object.CFrame

	-- build ignore list
	local ignoreList = {object}
	for _, desc in workspace:GetDescendants() do
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

	local function hitTest(from, to)
		local dir = to - from
		if dir.Magnitude < 0.01 then return false end
		local hit = workspace:Raycast(from, dir, rp)
		if hit then
			local hitDist = (hit.Position - from).Magnitude
			local totalDist = dir.Magnitude
			if hitDist < totalDist - 0.1 then
				return true, hit
			end
		end
		return false, nil
	end

	local function applyEase(t)
		local function eIn(x)
			if easingStyle == Enum.EasingStyle.Linear then return x
			elseif easingStyle == Enum.EasingStyle.Quad then return x*x
			elseif easingStyle == Enum.EasingStyle.Cubic then return x*x*x
			elseif easingStyle == Enum.EasingStyle.Quart then return x*x*x*x
			elseif easingStyle == Enum.EasingStyle.Quint then return x*x*x*x*x
			elseif easingStyle == Enum.EasingStyle.Sine then return 1-math.cos(x*math.pi/2)
			elseif easingStyle == Enum.EasingStyle.Exponential then return x==0 and 0 or 2^(10*(x-1))
			elseif easingStyle == Enum.EasingStyle.Circular then return 1-math.sqrt(1-x*x)
			elseif easingStyle == Enum.EasingStyle.Back then return x*x*(2.70158*x-1.70158)
			elseif easingStyle == Enum.EasingStyle.Elastic then
				if x==0 or x==1 then return x end
				return -(2^(10*x-10))*math.sin((x*10-10.75)*2.094)
			elseif easingStyle == Enum.EasingStyle.Bounce then
				x=1-x
				if x<0.3636 then return 1-7.5625*x*x
				elseif x<0.7272 then return 1-(7.5625*(x-0.5454)^2+0.75)
				elseif x<0.909 then return 1-(7.5625*(x-0.8181)^2+0.9375)
				else return 1-(7.5625*(x-0.9545)^2+0.984375) end
			end
			return x
		end
		if easingDirection == Enum.EasingDirection.In then return eIn(t)
		elseif easingDirection == Enum.EasingDirection.Out then return 1-eIn(1-t)
		else return t<0.5 and eIn(t*2)/2 or 1-eIn((1-t)*2)/2 end
	end

	-- use roblox PathfindingService as primary method
	local PathfindingService = game:GetService("PathfindingService")

	local function tryPathfinding()
		local agentParams = {
			AgentRadius = math.max(objectSize.X, objectSize.Z) / 2,
			AgentHeight = objectSize.Y,
			AgentCanJump = false,
			AgentCanClimb = false,
			WaypointSpacing = 4,
		}

		local path = PathfindingService:CreatePath(agentParams)

		local success, err = pcall(function()
			path:ComputeAsync(startPos, destination)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			local points = {}
			for _, wp in waypoints do
				points[#points + 1] = wp.Position
			end
			return points
		end

		return nil
	end

	-- manual pathfinding with raycasts
	local function tryManualPath()
		local dirs26 = {}
		for x=-1,1 do for y=-1,1 do for z=-1,1 do
					if not(x==0 and y==0 and z==0) then
						dirs26[#dirs26+1] = {x,y,z,math.sqrt(x*x+y*y+z*z)}
					end
				end end end

		local gridSizes = {6, 4, 3, 2}

		for _, gs in gridSizes do
			local function gWorld(gx,gy,gz)
				return Vector3.new(gx*gs, gy*gs, gz*gs)
			end

			local nbCache = {}
			local function nodeBlk(gx,gy,gz)
				local k = gx..","..gy..","..gz
				if nbCache[k] ~= nil then return nbCache[k] end
				local w = gWorld(gx,gy,gz)
				local op2 = OverlapParams.new()
				op2.FilterDescendantsInstances = ignoreList
				op2.FilterType = Enum.RaycastFilterType.Exclude
				local r = #workspace:GetPartBoundsInBox(CFrame.new(w), objectSize + Vector3.new(0.5,0.5,0.5), op2) > 0
				nbCache[k] = r
				return r
			end

			local function edgeClear(x1,y1,z1,x2,y2,z2)
				local a = gWorld(x1,y1,z1)
				local b = gWorld(x2,y2,z2)
				local blocked, _ = hitTest(a, b)
				return not blocked
			end

			local sx = math.round(startPos.X/gs)
			local sy = math.round(startPos.Y/gs)
			local sz = math.round(startPos.Z/gs)
			local ex = math.round(destination.X/gs)
			local ey = math.round(destination.Y/gs)
			local ez = math.round(destination.Z/gs)

			if nodeBlk(sx,sy,sz) then
				for r=1,5 do
					local done=false
					for _,d in dirs26 do
						if not nodeBlk(sx+d[1]*r,sy+d[2]*r,sz+d[3]*r) then
							sx,sy,sz=sx+d[1]*r,sy+d[2]*r,sz+d[3]*r
							done=true break
						end
					end
					if done then break end
				end
			end

			if nodeBlk(ex,ey,ez) then
				for r=1,5 do
					local done=false
					for _,d in dirs26 do
						if not nodeBlk(ex+d[1]*r,ey+d[2]*r,ez+d[3]*r) then
							ex,ey,ez=ex+d[1]*r,ey+d[2]*r,ez+d[3]*r
							done=true break
						end
					end
					if done then break end
				end
			end

			-- A*
			local heap = {}
			local hn = 0
			local function push(n)
				hn=hn+1 heap[hn]=n
				local i=hn
				while i>1 do
					local p=math.floor(i/2)
					if heap[p].f>heap[i].f then heap[p],heap[i]=heap[i],heap[p] i=p
					else break end
				end
			end
			local function pop()
				if hn==0 then return nil end
				local top=heap[1] heap[1]=heap[hn] heap[hn]=nil hn=hn-1
				local i=1
				while true do
					local l,r,s=i*2,i*2+1,i
					if l<=hn and heap[l].f<heap[s].f then s=l end
					if r<=hn and heap[r].f<heap[s].f then s=r end
					if s==i then break end
					heap[i],heap[s]=heap[s],heap[i] i=s
				end
				return top
			end

			local sk = sx..","..sy..","..sz
			local gScore = {[sk]=0}
			local parent = {}
			local gPos = {[sk]={sx,sy,sz}}
			local closed = {}

			push({x=sx,y=sy,z=sz,k=sk,f=0})

			local found = false
			local foundKey = nil
			local maxIter = 60000

			for _=1,maxIter do
				if hn==0 then break end
				local cur = pop()
				if not cur then break end
				if closed[cur.k] then continue end
				closed[cur.k] = true

				if cur.x==ex and cur.y==ey and cur.z==ez then
					found=true foundKey=cur.k break
				end

				local md = math.abs(cur.x-ex)+math.abs(cur.y-ey)+math.abs(cur.z-ez)
				if md<=3 then
					local cw = gWorld(cur.x,cur.y,cur.z)
					local isHit, _ = hitTest(cw, destination)
					if not isHit then
						found=true foundKey=cur.k break
					end
				end

				local cg = gScore[cur.k]

				for _,d in dirs26 do
					local nx,ny,nz = cur.x+d[1],cur.y+d[2],cur.z+d[3]
					local nk = nx..","..ny..","..nz
					if closed[nk] then continue end
					if nodeBlk(nx,ny,nz) then continue end

					if d[1]~=0 and d[2]~=0 and (nodeBlk(cur.x+d[1],cur.y,cur.z) or nodeBlk(cur.x,cur.y+d[2],cur.z)) then continue end
					if d[1]~=0 and d[3]~=0 and (nodeBlk(cur.x+d[1],cur.y,cur.z) or nodeBlk(cur.x,cur.y,cur.z+d[3])) then continue end
					if d[2]~=0 and d[3]~=0 and (nodeBlk(cur.x,cur.y+d[2],cur.z) or nodeBlk(cur.x,cur.y,cur.z+d[3])) then continue end

					if not edgeClear(cur.x,cur.y,cur.z,nx,ny,nz) then continue end

					local ng = cg + d[4]
					if not gScore[nk] or ng<gScore[nk] then
						gScore[nk] = ng
						parent[nk] = cur.k
						gPos[nk] = {nx,ny,nz}
						local dx,dy,dz = math.abs(nx-ex),math.abs(ny-ey),math.abs(nz-ez)
						push({x=nx,y=ny,z=nz,k=nk,f=ng+math.sqrt(dx*dx+dy*dy+dz*dz)})
					end
				end
			end

			if found and foundKey then
				local rev = {}
				local tk = foundKey
				while tk do
					local g = gPos[tk]
					if g then rev[#rev+1] = gWorld(g[1],g[2],g[3]) end
					tk = parent[tk]
				end
				local chain = {}
				for i=#rev,1,-1 do chain[#chain+1]=rev[i] end
				return chain
			end
		end

		return nil
	end

	local isHit, _ = hitTest(startPos, destination)

	local waypoints

	if not isHit then
		waypoints = {startPos, destination}
	else
		local pfPath = tryPathfinding()

		if pfPath and #pfPath >= 2 then
			local allClear = true
			for i = 2, #pfPath do
				local blocked, _ = hitTest(pfPath[i-1], pfPath[i])
				if blocked then
					allClear = false
					break
				end
			end
			if allClear then
				waypoints = pfPath
			end
		end

		if not waypoints then
			local chain = tryManualPath()
			if chain then
				local raw = {startPos}
				for _, p in chain do
					if (p-raw[#raw]).Magnitude > 0.3 then
						raw[#raw+1] = p
					end
				end
				if (raw[#raw]-destination).Magnitude > 0.3 then
					raw[#raw+1] = destination
				end
				raw[#raw] = destination

				-- simplify
				local simp = {raw[1]}
				local i = 1
				while i < #raw do
					local best = i+1
					for j=#raw,i+2,-1 do
						local blocked, _ = hitTest(raw[i], raw[j])
						if not blocked then
							best=j break
						end
					end
					simp[#simp+1] = raw[best]
					i = best
				end
				simp[1] = startPos
				simp[#simp] = destination

				-- smooth
				if #simp >= 3 then
					for pass=1,3 do
						local new = {simp[1]}
						for idx=1,#simp-1 do
							local a,b = simp[idx], simp[idx+1]
							local q = a:Lerp(b, 0.25)
							local r = a:Lerp(b, 0.75)
							local qHit,_ = hitTest(new[#new], q)
							if not qHit then new[#new+1] = q end
							local rHit,_ = hitTest(new[#new], r)
							if not rHit then new[#new+1] = r
							else
								local bHit,_ = hitTest(new[#new], b)
								if not bHit then new[#new+1] = b end
							end
						end
						if (new[#new]-simp[#simp]).Magnitude > 0.1 then
							new[#new+1] = simp[#simp]
						end
						new[1] = simp[1]
						new[#new] = simp[#simp]
						simp = new
					end
				end

				waypoints = simp
			end
		end

		if not waypoints then
			warn("[SmartTween] No valid path found! Object will not move through walls.")
			if callback then callback() end
			return {Cancel = function() end, Points = {startPos}}
		end

		local verified = {waypoints[1]}
		for i = 2, #waypoints do
			local isBlocked, _ = hitTest(verified[#verified], waypoints[i])
			if not isBlocked then
				verified[#verified+1] = waypoints[i]
			end
		end
		if (verified[#verified]-destination).Magnitude > 1 then
			warn("[SmartTween] Path incomplete - stopping at last safe point")
		end
		waypoints = verified
	end

	-- dedup
	local clean = {waypoints[1]}
	for i=2,#waypoints do
		if (waypoints[i]-clean[#clean]).Magnitude > 0.3 then
			clean[#clean+1] = waypoints[i]
		end
	end
	waypoints = clean

	-- markers
	local markers = {}
	if showWaypoints then
		for _, c in workspace:GetChildren() do
			if c.Name:sub(1,12) == "SmartTweenWP" then c:Destroy() end
		end
		for i, pos in waypoints do
			local m = Instance.new("Part")
			m.Name = "SmartTweenWP_"..i
			m.Anchored = true
			m.CanCollide = false
			m.CastShadow = false
			m.Material = Enum.Material.Neon
			m.Shape = Enum.PartType.Ball
			m.Transparency = 0
			m.Size = Vector3.new(2,2,2)
			m.Position = pos
			if i==1 then m.Color=Color3.fromRGB(0,120,255)
			elseif i==#waypoints then m.Color=Color3.fromRGB(255,0,0)
			else m.Color=Color3.fromRGB(0,255,0) end
			m.Parent = workspace
			markers[i] = m
		end
	end

	-- tween
	local totalDist = 0
	local segLens = {}
	local cumDist = {0}
	for i=2,#waypoints do
		local l = (waypoints[i]-waypoints[i-1]).Magnitude
		segLens[i] = l
		totalDist = totalDist+l
		cumDist[i] = totalDist
	end

	if totalDist < 0.01 then
		for _,m in markers do if m and m.Parent then m:Destroy() end end
		if callback then callback() end
		return {Cancel=function()end, Points=waypoints}
	end

	local totalTime = constantSpeed[1] and totalDist/math.max(constantSpeed[2],0.1) or travelTime
	local elapsed = 0
	local lastIdx = 1
	local curSeg = 2
	local conn

	conn = (RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat):Connect(function(dt)
		elapsed = math.min(elapsed+dt, totalTime)
		local td = applyEase(elapsed/totalTime) * totalDist

		while curSeg < #waypoints and cumDist[curSeg] < td do curSeg=curSeg+1 end
		while curSeg > 2 and cumDist[curSeg-1] > td do curSeg=curSeg-1 end

		local segStart = cumDist[curSeg-1] or 0
		local l = segLens[curSeg] or 0
		local segT = l>0 and (td-segStart)/l or 0
		local pos = waypoints[curSeg-1]:Lerp(waypoints[curSeg], math.clamp(segT,0,1))

		if showWaypoints then
			for i=lastIdx, curSeg-1 do
				if markers[i] and markers[i].Parent then
					markers[i]:Destroy()
					markers[i] = nil
				end
			end
			lastIdx = curSeg
		end

		if isModel then object:PivotTo(CFrame.new(pos)*startCFrame.Rotation)
		else object.CFrame = CFrame.new(pos)*startCFrame.Rotation end

		if elapsed >= totalTime then
			local finalPos = waypoints[#waypoints]
			if isModel then object:PivotTo(CFrame.new(finalPos)*startCFrame.Rotation)
			else object.CFrame = CFrame.new(finalPos)*startCFrame.Rotation end
			for _,m in markers do if m and m.Parent then m:Destroy() end end
			conn:Disconnect()
			activeTweens[object] = nil
			if callback then callback() end
		end
	end)

	activeTweens[object] = {conn=conn, markers=markers}
	return {
		Cancel = function()
			conn:Disconnect()
			for _,m in markers do if m and m.Parent then m:Destroy() end end
			activeTweens[object] = nil
		end,
		Points = waypoints
	}
end

local function Cancel(obj)
	if activeTweens[obj] then
		activeTweens[obj].conn:Disconnect()
		for _,m in activeTweens[obj].markers do if m and m.Parent then m:Destroy() end end
		activeTweens[obj] = nil
	end
end

local function CancelAll()
	for _,data in activeTweens do
		data.conn:Disconnect()
		for _,m in data.markers do if m and m.Parent then m:Destroy() end end
	end
	activeTweens = {}
end

SmartTween = setmetatable({Tween=Tween, Cancel=Cancel, CancelAll=CancelAll}, {
	__call = function(_,p) return Tween(p) end
})
