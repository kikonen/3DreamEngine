#pragma language glsl3

varying float VaryingEmission;
varying float VaryingDistortion;
varying vec3 VertexPos;
varying float depth;

//setting specific defines
#import globalDefines


#ifdef PIXEL
extern highp vec3 viewPos;

#ifdef TEX_EMISSION
extern Image tex_emission;
#endif

#ifdef TEX_DISORTION
extern Image tex_distortion;
#endif

#import fog

#ifdef EXPOSURE_ENABLED
extern float exposure;
#endif

#ifdef GAMMA_ENABLED
extern float gamma;
#endif

//uniforms required by the lighting
#import lightingSystemInit

extern vec3 ambient;

extern Image MainTex;

void effect() {
	vec3 viewVec = normalize(VertexPos - viewPos);
	
	//fetch color
	vec4 albedo = Texel(MainTex, VaryingTexCoord.xy);

#ifdef DEPTH_ENABLED
	if (albedo.a <= 0.5) {
		discard;
	} else {
		albedo.a = 1.0;
	}
#endif
	
	//emission
#ifdef TEX_EMISSION
	vec3 emission = Texel(tex_emission, VaryingTexCoord.xy).rgb;
	vec3 col = emission * VaryingEmission;
#else
	vec3 col = albedo.rgb * VaryingEmission;
#endif
	
#ifdef TEX_DISORTION
	vec2 distortion = (Texel(tex_distortion, VaryingTexCoord.xy).xy * 2.0 - 1.0) * VaryingDistortion;
#else
	vec2 distortion = vec2(0.0);
#endif
	
	//forward lighting
	albedo *= VaryingColor;
	if (length(albedo.rgb) > 0.0) {
		vec3 light = vec3(0.0);
#import lightingSystem
		col += light * albedo.rgb * albedo.a;
	}
	
	//ambient lighting
	col += ambient;
	
	//fog (TODO moving this to vertex had negative results, requires further testing)
#ifdef FOG_ENABLED
	vec4 fogColor = getFog(depth, viewVec, viewPos);
	col = mix(col, fogColor.rgb, fogColor.a);
#endif

	//exposure
#ifdef EXPOSURE_ENABLED
	col = vec3(1.0) - exp(-col * exposure);
#endif
	
	//gamma correction
#ifdef GAMMA_ENABLED
	col = pow(col, vec3(1.0 / gamma));
#endif

#ifdef REFRACTIONS_ENABLED
	//to allow distortion blending we use premultiplied alpha blending, which required manual rgb math here
	col *= albedo.a;
	
	love_Canvases[1] = vec4(distortion, 0.0, 0.0);
#endif

	//depth
#ifdef DEPTH_ENABLED
	love_Canvases[1] = vec4(depth, 0.0, 0.0, 1.0);
#endif
	
	//color
	love_Canvases[0] = vec4(col, albedo.a);
}
#endif

#ifdef VERTEX

#ifdef SINGLE
extern vec3 InstanceCenter;
extern float InstanceEmission;
extern float InstanceDistortion;
#else
attribute vec3 InstanceCenter;
attribute float InstanceEmission;
attribute float InstanceDistortion;
attribute vec2 InstanceSize;
attribute float InstanceRotation;
attribute vec2 InstanceTexScale;
attribute vec2 InstanceTexOffset;
attribute vec4 InstanceColor;
#endif

extern mat4 transformProj;
extern vec3 up;
extern vec3 right;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
#ifdef SINGLE
	VaryingTexCoord = vec4(VertexTexCoord.x, 1.0 - VertexTexCoord.y, 0.0, 0.0);
	
	VertexPos = InstanceCenter + (right * vertex_position.x + up * vertex_position.y);
#else
	VaryingTexCoord = vec4(VertexTexCoord.xy * InstanceTexScale + InstanceTexOffset, 0.0, 0.0);
	VaryingColor = InstanceColor;
	
	//rotate
	float c = cos(InstanceRotation);
	float s = sin(InstanceRotation);
	vec2 p = vec2(
		vertex_position.x * c - vertex_position.y * s,
		vertex_position.x * s + vertex_position.y * c
	);
	
	VertexPos = InstanceCenter + (right * p.x * InstanceSize.x + up * p.y * InstanceSize.y);
#endif

	VaryingEmission = InstanceEmission;
	VaryingDistortion = InstanceDistortion;
	
	vec4 vPos = transformProj * vec4(VertexPos, 1.0);
	
	//extract and pass depth
	depth = vPos.z;
	
	return vPos;
}
#endif