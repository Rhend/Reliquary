// ============================================================
// holo_post.gdshader - Post-process plein ecran (scanlines/flicker/distorsion).
//
// Applique a un ColorRect plein ecran sur un CanvasLayer AU-DESSUS du rendu 3D.
// Lit l'image deja rendue (glow 3D compris) via hint_screen_texture et applique
// scanlines defilantes, flicker temporel doux et distorsion de bord. Le glow
// est gere en amont par le WorldEnvironment ; ce post ne fait que l'habillage.
//
// canvas_item / GL Compatibility. IMPORTANT : commentaires ASCII pur.
// ============================================================
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float scanline_intensity = 0.30;
uniform float scanline_count     = 240.0;
uniform float scanline_speed     = 0.6;
uniform float flicker_amplitude  = 0.05;
uniform float distortion_amplitude = 0.0;   // 0 = pas d'ondulation

float flicker(float t) {
	float a = 0.5 + 0.5 * sin(t * 6.30);
	float b = 0.5 + 0.5 * sin(t * 2.10 + 1.7);
	float c = 0.5 + 0.5 * sin(t * 11.3 + 4.2);
	return (a * 0.5 + b * 0.3 + c * 0.2);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Distorsion de bord : ondulation horizontale croissante vers les bords.
	float edge   = clamp(length(uv - vec2(0.5)) * 1.6, 0.0, 1.0);
	float wobble = sin(uv.y * 70.0 + TIME * 3.0) * distortion_amplitude * edge;
	vec3 col = texture(screen_tex, vec2(uv.x + wobble, uv.y)).rgb;

	// Scanlines defilantes.
	float sl   = sin((uv.y * scanline_count - TIME * scanline_speed * scanline_count) * 0.5);
	col *= 1.0 - scanline_intensity * (0.5 - 0.5 * sl);

	// Flicker global doux (non epileptogene).
	col *= 1.0 - flicker_amplitude * flicker(TIME);

	COLOR = vec4(col, 1.0);
}
