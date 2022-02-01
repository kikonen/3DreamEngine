local sh = { }

sh.type = "pixel"

sh.meshType = "textured"

function sh:getId(dream, mat, shadow)
	if shadow then
		return (mat.discard and 1 or 0)
	else
		return (mat.tex_normal and 1 or 0) * 2^1 + (mat.tex_emission and 1 or 0) * 2^2 + (mat.discard and not mat.dither and 1 or 0) * 2^3 + (mat.dither and 1 or 0) * 2^4
	end
end

function sh:buildDefines(dream, mat, shadow)
	return [[
		]] .. (mat.tex_normal and "#define TEX_NORMAL\n" or "") .. [[
		]] .. (mat.tex_normal and "#define TANGENT\n" or "") .. [[
		
		]] .. (mat.tex_emission and "#define TEX_EMISSION\n" or "") .. [[
		]] .. (mat.tex_material and "#define TEX_MATERIAL\n" or "") .. [[
		
		]] .. ((not shadow and (mat.discard and not mat.dither) or shadow and mat.discard) and "#define DISCARD\n" or "") .. [[
		]] .. ((not shadow and mat.dither) and "#define DITHER\n" or "") .. [[
		
		#ifdef PIXEL
		extern Image tex_albedo;
		extern vec4 color_albedo;
		
		#ifdef TEX_MATERIAL
		extern Image tex_material;
		#endif
		extern vec2 color_material;
		
		#ifdef TEX_NORMAL
		extern Image tex_normal;
		#endif
		
		#ifdef TEX_EMISSION
		extern Image tex_emission;
		#endif
		extern vec3 color_emission;
		
		#endif
	]]
end

function sh:buildPixel(dream, mat)
	return [[
	//color
	vec4 c = gammaCorrectedTexel(tex_albedo, VaryingTexCoord.xy) * color_albedo;
	albedo = c.rgb;
	alpha = c.a;
	
#ifdef DISCARD
	if (alpha < 0.5) {
		discard;
	}
#endif

#ifdef DITHER
	if (alpha < fract(love_PixelCoord.x * 0.37 + love_PixelCoord.y * 73.73 + depth * 3.73)) {
		discard;
	}
#endif

#ifndef ALPHA_PASS
	alpha = 1.0;
#endif
	
	//material
#ifdef TEX_MATERIAL
	vec3 material = Texel(tex_material, VaryingTexCoord.xy).xyz;
	roughness = material.x * color_material.x;
	metallic = material.y * color_material.y;
	ao = material.z;
#else
	roughness = color_material.x;
	metallic = color_material.y;
#endif
	
	//emission
#ifdef TEX_EMISSION
	emission = gammaCorrectedTexel(tex_emission, VaryingTexCoord.xy).rgb * color_emission;
#else
	emission = color_albedo.rgb * color_emission;
#endif

	//normal
#ifdef TEX_NORMAL
	normal = Texel(tex_normal, VaryingTexCoord.xy).xyz * vec3(2.0) - vec3(1.0);
	normal = normalize(TBN * normal);
#else
	normal = normalize(VaryingNormal);
#endif
	]]
end

function sh:buildVertex(dream, mat)
	return ""
end

function sh:perShader(dream, shaderObject)

end

function sh:perMaterial(dream, shaderObject, material)
	local shader = shaderObject.shader
	
	local tex = dream.textures
	
	shader:send("tex_albedo", dream:getImage(material.tex_albedo) or tex.default)
	shader:send("color_albedo", material.color)
	
	if shader:hasUniform("tex_material") then
		shader:send("tex_material", dream:getImage(material.tex_material) or tex.default)
	end
	shader:send("color_material", {material.roughness, material.metallic})
	
	if shader:hasUniform("tex_normal") then
		shader:send("tex_normal", dream:getImage(material.tex_normal) or tex.default_normal)
	end
	
	if shader:hasUniform("tex_emission") then
		shader:send("tex_emission", dream:getImage(material.tex_emission) or tex.default)
	end
	
	shader:send("color_emission", material.emission)
end

function sh:perTask(dream, shaderObject, task)

end

return sh