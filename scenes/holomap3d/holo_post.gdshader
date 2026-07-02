// ============================================================
// holo_post.gdshader - Post-process plein ecran (grade hologramme cyberpunk).
//
// ColorRect plein ecran sur un CanvasLayer AU-DESSUS du rendu 3D. Lit l'image
// deja rendue (glow 3D compris) via hint_screen_texture et applique, dans l'ordre :
//   1. distorsion de bord (ondulation) + GLITCH par tranches (rafales rares),
//   2. ABERRATION CHROMATIQUE (separation RVB croissante vers les bords),
//   3. SCANLINES defilantes,
//   4. FLICKER temporel doux + RESPIRATION lente (l'hologramme « vit »),
//   5. VIGNETTE (coins assombris -> focus central, ecran cathodique).
// Tout est non-epileptogene (amplitudes faibles, glitch bref et espace).
//
// canvas_item / GL Compatibility. IMPORTANT : commentaires ASCII pur.
// ============================================================
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float scanline_intensity = 0.05;   // 0 = pas de scanlines
uniform float scanline_count     = 240.0;
uniform float scanline_speed     = 0.6;
uniform float flicker_amplitude  = 0.015;   // scintillement global doux
uniform float distortion_amplitude = 0.0015; // ondulation de bord
uniform float aberration = 0.0016;          // separation chromatique (UV)
uniform float vignette_force = 0.35;        // assombrissement des coins
uniform float glitch_force = 0.6;           // rafales de decalage par tranches
uniform float breathe_amp = 0.02;           // respiration lumineuse lente

float h11(float x) {
	return fract(sin(x * 12.9898) * 43758.5453);
}

float flicker(float t) {
	float a = 0.5 + 0.5 * sin(t * 6.30);
	float b = 0.5 + 0.5 * sin(t * 2.10 + 1.7);
	float c = 0.5 + 0.5 * sin(t * 11.3 + 4.2);
	return (a * 0.5 + b * 0.3 + c * 0.2);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float edge = clamp(length(uv - vec2(0.5)) * 1.6, 0.0, 1.0);

	// 1a. Distorsion de bord : ondulation horizontale croissante vers les bords.
	float wobble = sin(uv.y * 70.0 + TIME * 3.0) * distortion_amplitude * edge;
	vec2 uvw = vec2(uv.x + wobble, uv.y);

	// 1b. Glitch : rafale breve et RARE qui decale des tranches horizontales en X.
	float burst = step(0.965, h11(floor(TIME * 2.3)));       // ~rare et bref
	float band = floor(uv.y * 36.0);
	float slice = h11(band + floor(TIME * 9.0)) - 0.5;
	uvw.x += glitch_force * burst * slice * 0.05;

	// 2. Aberration chromatique : R/B ecartes le long du rayon, surtout aux bords
	// (presque nulle au centre -> les lignes ne doublent pas, focus net).
	vec2 dir = normalize(uv - vec2(0.5) + vec2(1e-5));
	float ab = aberration * (0.12 + 1.3 * edge * edge);
	float r = texture(screen_tex, uvw + dir * ab).r;
	float g = texture(screen_tex, uvw).g;
	float b = texture(screen_tex, uvw - dir * ab).b;
	vec3 col = vec3(r, g, b);

	// 3. Scanlines defilantes.
	float sl = sin((uv.y * scanline_count - TIME * scanline_speed * scanline_count) * 0.5);
	col *= 1.0 - scanline_intensity * (0.5 - 0.5 * sl);

	// 4. Flicker global + respiration lente (l'hologramme palpite).
	col *= 1.0 - flicker_amplitude * flicker(TIME);
	col *= 1.0 + breathe_amp * sin(TIME * 0.8);

	// 5. Vignette : coins assombris -> focus central.
	col *= 1.0 - vignette_force * edge * edge;

	// 6. Tramage leger (~+-1/255, anime) : casse le BANDING 8-bit des degrades
	// sombres (halo d'horizon, vignette) sans grain visible.
	col += (h11(dot(uv, vec2(419.17, 863.61)) + fract(TIME * 0.7) * 17.0) - 0.5) * (2.0 / 255.0);

	COLOR = vec4(col, 1.0);
}
