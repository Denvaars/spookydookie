shader_type spatial;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap;
uniform sampler2D noise_texture : source_color, filter_linear_mipmap;
uniform sampler2D path_texture : source_color, filter_linear_mipmap;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.3;
uniform float path_blend_sharpness : hint_range(0.0, 1.0) = 0.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.95;

// LOD settings
uniform float lod_near_distance : hint_range(0.0, 50.0) = 5.0;
uniform float lod_far_distance : hint_range(0.0, 50.0) = 15.0;
uniform vec3 camera_position;

varying vec3 world_pos;

void vertex() {
	// Calculate world position in vertex shader
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Calculate distance from camera to fragment using world position from vertex shader
	float distance_to_camera = length(world_pos - camera_position);

	// Sample textures with distance-based LOD
	vec4 grass_color;
	vec4 path_color;

	if (distance_to_camera < lod_near_distance) {
		// 0-5m: Full quality, no LOD
		grass_color = texture(grass_texture, UV);
		path_color = texture(path_texture, UV);
	} else if (distance_to_camera < lod_far_distance) {
		// 5-15m: Medium LOD (bias 0.5 to 3.5) - more aggressive blur
		float t = (distance_to_camera - lod_near_distance) / (lod_far_distance - lod_near_distance);
		float lod_bias = mix(2, 4, t);
		grass_color = textureLod(grass_texture, UV, lod_bias);
		path_color = textureLod(path_texture, UV, lod_bias);
	} else {
		// 15m+: High LOD with very aggressive blur (bias 3.5 to 6.0)
		float t = clamp((distance_to_camera - lod_far_distance) / 30.0, 0.0, 1.0);
		float lod_bias = mix(5, 10, t);
		grass_color = textureLod(grass_texture, UV, lod_bias);
		path_color = textureLod(path_texture, UV, lod_bias);
	}

	vec4 noise_color = texture(noise_texture, UV2);

	// Get path blend from vertex color (red channel)
	float path_blend = clamp(COLOR.r, 0.0, 1.0);

	// Simple smoothstep for sharp edges (no pow() to avoid GPU precision issues)
	path_blend = smoothstep(0.0, 1.0, path_blend);

	// Blend grass and path first
	vec3 terrain_color = mix(grass_color.rgb, path_color.rgb, path_blend);

	// Apply noise with varying strength: +0.2 on grass, base strength on path
	// path_blend = 0.0 (grass) -> add 0.2 to noise strength
	// path_blend = 1.0 (path) -> use base noise strength
	float actual_noise_strength = noise_strength + (1.0 - path_blend) * 0.2;
	vec3 final_color = mix(terrain_color, terrain_color * noise_color.rgb, actual_noise_strength);

	ALBEDO = final_color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
