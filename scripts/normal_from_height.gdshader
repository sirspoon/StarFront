shader_type canvas_item;
// Works out a normal map for one map tile from its height map (big shapes) and
// its colour (fine detail: lighter stones read as raised, cracks as sunken).

uniform sampler2D height_tex : filter_linear;
uniform sampler2D albedo_tex : filter_linear;
uniform vec2 texel;
uniform float strength = 10.0;  // how steep the height map's slopes are
uniform float detail = 3.5;    // how much relief the colour detail adds
uniform float flip_y = -1.0;  // Godot reads green as "facing up the screen"

float h(vec2 uv) {
	vec3 a = texture(albedo_tex, uv).rgb;
	float lum = dot(a, vec3(0.299, 0.587, 0.114));
	return texture(height_tex, uv).r * strength + lum * detail;
}

void fragment() {
	vec2 uv = UV;
	vec2 dx = vec2(texel.x, 0.0);
	vec2 dy = vec2(0.0, texel.y);
	// Sobel over a 3x3 neighbourhood: smooths out single-pixel noise
	float tl = h(uv - dx - dy), t = h(uv - dy), tr = h(uv + dx - dy);
	float l = h(uv - dx), r = h(uv + dx);
	float bl = h(uv - dx + dy), b = h(uv + dy), br = h(uv + dx + dy);
	float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
	float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
	vec3 n = normalize(vec3(-gx, -gy * flip_y, 4.0));
	COLOR = vec4(n * 0.5 + 0.5, 1.0);
}
