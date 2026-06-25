// ============================================================
// holo_post_container.gdshader - Post-process pour SubViewportContainer.
//
// Variante de holo_post : quand la scene 3D est embarquee dans un SubViewport
// (HoloMap3DOverlay), le post s'applique sur le CONTENEUR, qui echantillonne
// TEXTURE = image rendue du viewport (et non le screen texture). Memes effets :
// scanlines defilantes, flicker, distorsion de bord. Le glow vient du
// WorldEnvironment a l'interieur du viewport.
//
// canvas_item / GL Compatibility. IMPORTANT : commentaires ASCII pur.
// ============================================================
shader_type canvas_item;

uniform float scanline_intensity = 0.28;
uniform float scanline_count     = 240.0;
uniform float scanline_speed     = 0.6;
uniform float flicker_amplitude  = 0.04;
uniform float distortion_amplitude = 0.0;   // 0 = pas d'ondulation

float flicker(float t) {
	float a = 0.5 + 0.5 * sin(t * 6.30);
	float b = 0.5 + 0.5 * sin(t * 2.10 + 1.7);
	float c = 0.5 + 0.5 * sin(t * 11.3 + 4.2);
	return (a * 0.5 + b * 0.3 + c * 0.2);
}

void fragment() {
	vec2 uv = UV;

	// Distorsion de bord : ondulation horizontale croissante vers les bords.
	float edge   = clamp(length(uv - vec2(0.5)) * 1.6, 0.0, 1.0);
	float wobble = sin(uv.y * 70.0 + TIME * 3.0) * distortion_amplitude * edge;
	vec4 src = texture(TEXTURE, vec2(uv.x + wobble, uv.y));
	vec3 col = src.rgb;

	// Scanlines defilantes.
	float sl = sin((uv.y * scanline_count - TIME * scanline_speed * scanline_count) * 0.5);
	col *= 1.0 - scanline_intensity * (0.5 - 0.5 * sl);

	// Flicker global doux (non epileptogene).
	col *= 1.0 - flicker_amplitude * flicker(TIME);

	COLOR = vec4(col, src.a);
}
