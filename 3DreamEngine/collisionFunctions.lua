--[[
#part of the 3DreamEngine by Luke100000
collisionFunctions.lua - contains collision and physics library relevant functions
--]]

local self = _3DreamEngine

--get the collision data from a mesh
--it moves the collider to its bounding box center based on its initial transform
function self:getCollisionData(obj)
	local n = { }
	
	--data required by the collision extension
	n.typ = "mesh"
	n.boundary = 0
	n.name = obj.name
	n.group = obj.group
	
	--offset, a transformation will be directly applied
	n.transform = obj.boundingBox and obj.boundingBox.center or vec3(0, 0, 0)
	
	if obj.transform then
		n.transform = obj.transform * n.transform
	end
	
	n.transformInverse = -n.transform
	
	--data
	n.faces = { }
	n.normals = { }
	n.edges = { }
	n.point = vec3(0, 0, 0)
	
	--transform vertices
	local vertices = { }
	for d,s in ipairs(obj.vertices) do
		vertices[d] = (obj.transform and obj.transform * vec3(s) or vec3(s)) - n.transform
	end
	
	local hashes = { }
	for d,s in ipairs(obj.faces) do
		--vertices
		local a = vertices[s[1]]
		local b = vertices[s[2]]
		local c = vertices[s[3]]
		
		--edges
		for i = 1, 3 do
			local n1 = s[i % 3 + 1]
			local n2 = s[(i+1) % 3 + 1]
			
			local id = math.min(n1, n2) * 9999 + math.max(n1, n2)
			if not hashes[id] then
				table.insert(n.edges, {vertices[n1], vertices[n2]})
				hashes[id] = true
			end
		end
		
		--face normal
		local normal = (b-a):cross(c-a):normalize()
		table.insert(n.normals, normal)
		
		n.point = a
		
		--boundary
		n.boundary = math.max(n.boundary, a:length(), b:length(), c:length())
		
		--face
		table.insert(n.faces, {a, b, c})
	end
	
	return n
end

--find the vertices which is most likely its bottom
local findBottom = function(groupVertices, vertices, v)
	local best = v.y
	local bestV = math.huge
	local threshold = 0.01^2
	for d,i in ipairs(groupVertices) do
		local s = vertices[i]
		if s ~= v then
			local dist = (s.x - v.x)^2 + (s.z - v.z)^2
			local score = 0.0001 * (s.y - v.y)^2
			if dist < threshold and score < bestV then
				bestV = score
				best = s.y
			end
		end
	end
	return best
end

--receives an array of faces defined by three indices and an array with vertices and returns an array of connected subsets and an array of subset vertices indices
--connected sets are defined by a single shared vertex, recognized by its reference
function self:groupVertices(faces, vertices)
	--initilize group indices
	local groupIndices = { }
	for d,s in ipairs(vertices) do
		groupIndices[s] = d
	end
	
	--group vertices
	local active
	local found = true
	while found do
		found = false
		active = { }
		for _,s in ipairs(faces) do
			local a = vertices[s[1]]
			local b = vertices[s[2]]
			local c = vertices[s[3]]
			
			local ga = groupIndices[a]
			local gb = groupIndices[b]
			local gc = groupIndices[c]
			
			local min = math.min(ga, gb, gc)
			local max = math.max(ga, gb, gc)
			
			if min == max then
				active[ga] = true
			else
				groupIndices[a] = min
				groupIndices[b] = min
				groupIndices[c] = min
				found = true
			end
		end
	end
	
	--split into groups
	local groups = { }
	local groupVertices = { }
	local ID = 0
	for group,_ in pairs(active) do
		ID = ID + 1
		groups[ID] = { }
		for _,s in ipairs(faces) do
			local a = vertices[s[1]]
			if groupIndices[a] == group then
				table.insert(groups[ID], s)
			end
		end
		
		groupVertices[ID] = { }
		for d,s in ipairs(vertices) do
			if groupIndices[s] == group then
				table.insert(groupVertices[ID], d)
			end
		end
	end
	
	return groups, groupVertices
end

--preprocess subObject and link required data
function self:getPhysicsData(obj)
	local p = { }
	p.groups, p.groupVertices = self:groupVertices(obj.faces, obj.vertices)
	p.vertices = obj.vertices
	p.normals = obj.normals
	p.transform = obj.transform or mat4.getIdentity()
	p.name = obj.name
	p.group = obj.group
	return p
end

function self:getPhysicsObject(phy)
	local n = { }
	
	n.typ = "triangle"
	n.objects = { }
	n.normals = { }
	n.heights = { }
	n.thickness = { }
	
	--to make is theoretically possible to reuse the physicsData
	local groups = table.copy(phy.groups)
	
	--transform vertices
	local transformed = { }
	local vertices = { }
	for d,s in ipairs(phy.vertices) do
		if not transformed[s] then
			transformed[s] = phy.transform * vec3(s)
		end
		vertices[d] = transformed[s]
	end
	
	--transform normals
	local transformed = { }
	local normals = { }
	local subm = phy.transform:subm()
	for d,s in ipairs(phy.normals) do
		if not transformed[s] then
			transformed[s] = subm * vec3(s)
		end
		normals[d] = transformed[s]
	end
	
	--look for highest and lowest value, or triangulate the face it is in
	local height = { }
	local threshold = 0.01
	for d,s in ipairs(vertices) do
		for i,v in ipairs(vertices) do
			if i > d then break end
			local dist = (s.x-v.x)^2 + (s.z-v.z)^2
			if dist < threshold then
				height[d] = math.abs(v.y - s.y, 0)
				height[i] = math.abs(s.y - v.y, 0)
				break
			end
		end
		
		--no opposite vertex found
		if not height[d] then
			for _,group in ipairs(groups) do
				for faceID,face in ipairs(group) do
					--vertices
					local a = vertices[face[1]]
					local b = vertices[face[2]]
					local c = vertices[face[3]]
					
					local w1, w2, w3 = self:getBarycentric(x, y, a.x, a.y, b.x, b.y, c.x, c.y)
					local inside = w1 > 0 and w2 > 0 and w3 > 0 and w1 < 1 and w2 < 1 and w3 < 1
					if inside then
						table.remove(group, faceID)
						
						table.insert(group, {face[1], face[2], d})
						table.insert(group, {face[2], face[3], d})
						table.insert(group, {face[3], face[1], d})
						
						local h = a.y * w1 + b.y * w2 + c.y * w3
						height[d] = math.abs(h - s.y, 0)
						height[i] = math.abs(s.y - h, 0)
						
						goto done
					end
				end
			end
			::done::
		end
		
		--corner
		if not height[d] then
			height[d] = 0
		end
	end
	
	--get most likely vertex to reconstruct order
	local function smallest(x, y, x1, y1, x2, y2, x3, y3)
		local d1 = math.abs(x1 - x) + math.abs(y1 - y)
		local d2 = math.abs(x2 - x) + math.abs(y2 - y)
		local d3 = math.abs(x3 - x) + math.abs(y3 - y)
		local min = math.min(d1, d2, d3)
		return d1 == min and 1 or d2 == min and 2 or 3
	end
	
	--create polygons
	for gID,group in ipairs(groups) do
		for _,face in ipairs(group) do
			--vertices
			local a = vertices[face[1]]
			local b = vertices[face[2]]
			local c = vertices[face[3]]
			
			local normal = (b-a):cross(c-a):normalize()
			
			--verify
			if normal.y > 0 then
				local ok, shape = pcall(love.physics.newPolygonShape, a.x, a.z, b.x, b.z, c.x, c.z)
				
				if ok then
					--reconstruct the order, since the polygon might have restructured itself
					local x1, y1, x2, y2, x3, y3 = shape:getPoints()
					local translation = {
						smallest(a.x, a.z, x1, y1, x2, y2, x3, y3),
						smallest(b.x, b.z, x1, y1, x2, y2, x3, y3),
						smallest(c.x, c.z, x1, y1, x2, y2, x3, y3),
					}
					
					--add shape
					table.insert(n.objects, shape)
					
					--face normal
					table.insert(n.normals, {
						normals[face[translation[1]]],
						normals[face[translation[2]]],
						normals[face[translation[3]]],
					})
					
					local abc = {a, b, c}
					
					--triangle height
					table.insert(n.heights, {
						abc[translation[1]].y,
						abc[translation[2]].y,
						abc[translation[3]].y,
					})
					
					--triangle thickness
					local v = phy.groupVertices[gID]
					table.insert(n.thickness, {
						findBottom(v, vertices, abc[translation[1]]),
						findBottom(v, vertices, abc[translation[2]]),
						findBottom(v, vertices, abc[translation[3]]),
					})
				end
			end
		end
	end
	
	return n
end