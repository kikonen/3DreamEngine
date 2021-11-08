--[[
#part of the 3DreamEngine by Luke100000
bufferFunctions.lua - contains library relevant functions with focus on buffer modifications
--]]

local lib = _3DreamEngine

function lib:applyTransform(s, transform)
	if type(s) == "userdata" then
		--parse mesh format
		local f = s:getVertexFormat()
		local indices = { }
		local index = 1
		for d,s in ipairs(f) do
			indices[s[1]] = index
			index = index + s[3]
		end
		
		--normal transformation
		local subm = transform:subm()
		
		for i = 1, s:getVertexCount() do
			local data = {s:getVertex(i)}
			
			--transform vertices
			local p = indices.VertexPosition
			if p then
				data[p], data[p+1], data[p+2] = transform * vec3(data[p], data[p+1], data[p+2])
			end
			
			--transform normals
			local p = indices.VertexNormal
			if p then
				data[p], data[p+1], data[p+2] = subm * vec3(data[p], data[p+1], data[p+2])
			end
			
			s:setVertex(i, unpack(data))
		end
	elseif s.class == "mesh" then
		if s then
			self:applyTransform(s.mesh, s.transform)
		else
			assert(s.vertices and s.normals, "object has been cleaned up!")
			
			--normal transforation
			local subm = transform:subm()
			
			for i = 1, #s.vertices do
				--transform vertices
				s.vertices[i] = transform * vec3(s.vertices[i])
				
				--transform normals
				s.normals[i] = subm * vec3(s.normals[i])
			end
		end
		s.transform = nil
	elseif s.class == "object" then
		for d,s in ipairs(s) do
			self:applyTransform(s)
		end
	else
		error("mesh, object or mesh expected")
	end
end

--merge all meshes of an object and concatenate all buffer together
--it uses a material of one random mesh and therefore either requires baking afterwards or only identical materials in the first place
--it returns a cloned object with only one mesh
function lib:mergeMeshes(obj)
	local final = obj:clone()
	local o = self:newMesh("merged", false, final.args.meshType)
	final.meshes = {merged = o}
	
	local s = obj.meshes[next(obj.meshes)]
	o.material = s.material
	
	--objects with skinning information should not get transformed
	if o.joints then
		o.transform = s.transform
	end
	
	--get valid objects
	local meshes = { }
	for d,s in pairs(obj.meshes) do
		if not s.LOD_max or s.LOD_max >= math.huge then
			if s.tags.merge ~= false then
				meshes[d] = s
			end
		end
	end
	
	--check which buffers are necessary
	local buffers = {
		"vertices",
		"normals",
		"texCoords",
		"colors",
		"weights",
		"joints",
	}
	local found = { }
	for d,s in pairs(meshes) do
		for _,buffer in pairs(buffers) do
			if s[buffer] then
				found[buffer] = true
			end
		end
	end
	
	assert(found.vertices, "object has been cleaned up!")
	
	local defaults = {
		vertices = vec3(0, 0, 0),
		normals = vec3(0, 0, 0),
		texCoords = vec2(0, 0),
	}
	
	--merge buffers
	local startIndices = { }
	for d,s in pairs(meshes) do
		local index = #o.vertices
		startIndices[d] = index
		
		local transform, transformNormal
		if not s.joints then
			transform = s.transform
			transformNormal = transform and transform:subm()
		end
		
		for buffer,_ in pairs(found) do
			o[buffer] = o[buffer] or { }
			for i = 1, #s.vertices do
				local v = s[buffer] and s[buffer][i] or defaults[buffer] or false
				
				if transform then
					if buffer == "vertices" then
						v = transform * vec3(v)
					elseif buffer == "normals" then
						v = transformNormal * vec3(v)
					end
				end
				
				o[buffer][index + i] = v
			end
		end
	end
	
	--merge faces
	for d,s in pairs(meshes) do
		for _,face in ipairs(s.faces) do
			local i = startIndices[d]
			table.insert(o.faces, {face[1] + i, face[2] + i, face[3] + i})
		end
	end
	
	final:updateBoundingBox()
	
	return final
end

--takes an final and face table and generates the mesh and vertexMap
--note that .3do files has it's own mesh loader
function lib:createMesh(obj)
	if obj.class == "object" then
		if not obj.linked then
			for d,o in pairs(obj.meshes) do
				lib:createMesh(o)
			end
			
			for d,o in pairs(obj.objects) do
				lib:createMesh(o)
			end
		end
	elseif obj.class == "mesh" then
		if not obj.faces then
			return
		end
		
		--set up vertex map
		local vertexMap = { }
		for d,f in ipairs(obj.faces) do
			table.insert(vertexMap, f[1])
			table.insert(vertexMap, f[2])
			table.insert(vertexMap, f[3])
		end
		
		--create mesh
		local meshFormat = self.meshFormats[obj.meshType]
		local meshLayout = meshFormat.meshLayout
		obj.mesh = love.graphics.newMesh(meshLayout, #obj.vertices, "triangles", "static")
		
		--vertex map
		obj.mesh:setVertexMap(vertexMap)
		
		--fill vertices
		meshFormat:create(obj)
	else
		error("object or mesh expected")
	end
end