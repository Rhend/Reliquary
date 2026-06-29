// ============================================================
// holo_parc.gdshader - Surface de PARC (nappe verte vivante : herbe holo).
//
// Appliquee aux tuiles de parc (PRIMITIVE_TRIANGLES) du gabarit. Signature visuelle
// du parc (comme l'eau coule et la route a son trafic) : une LUEUR QUI PULSE. Un fond
// vert de TOUFFES organiques (bruit continu en coords MONDE -> continu d'une tuile a
// l'autre), sur lequel des taches lumineuses GONFLENT puis REFLUENT au passage d'une
// onde douce qui traverse la zone. Additif HDR doux + brume + reveal, coherent avec
// les autres shaders holo.
//
// IMPORTANT : commentaires ASCII pur (parseur de shaders Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4  parc_color : source_color = vec4(0.22, 0.52, 0.30, 1.0);
uniform float echelle = 5.5;      // densite des touffes d'herbe
uniform float vitesse = 0.20;     // vitesse de la brise (fremissement du fond)
uniform float emission = 1.0;     // gain HDR global
uniform float pulse_vitesse = 1.4;        // vitesse de l'onde de pulsation
uniform float pulse_echelle = 0.9;        // frequence spatiale du pulse (taille des bouffees)
uniform vec2  pulse_dir = vec2(1.0, 0.6); // sens de propagation du pulse (monde XZ)
uniform float fog_debut = 22.0;
uniform float fog_fin = 46.0;
uniform float fog_min = 0.25;
uniform float reveal_r = 100000.0;

varying vec3 w_pos;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Bruit de valeur 2D lisse (touffes continues d'une tuile a l'autre).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (length(w_pos.xz) > reveal_r) {
		discard;
	}
	vec2 p = w_pos.xz;
	float t = TIME * vitesse;
	// Fond : touffes d'herbe organiques (2 octaves de bruit + leger fremissement).
	float clumps = vnoise(p * echelle + vec2(sin(t), cos(t * 0.8)) * 0.18);
	clumps = clumps * 0.6 + vnoise(p * echelle * 2.4 - vec2(t * 0.3, 0.0)) * 0.4;

	// LUEUR QUI PULSE : une onde douce traverse le parc (pulse_dir) ET chaque touffe
	// respire a sa propre phase -> des taches lumineuses qui gonflent puis refluent.
	float phase = dot(p, normalize(pulse_dir)) * pulse_echelle - TIME * pulse_vitesse + clumps * 3.0;
	float pulse = pow(0.5 + 0.5 * sin(phase), 2.2);          // bouffees douces et nettes
	float glow = smoothstep(0.42, 0.92, clumps) * pulse;     // les touffes s'allument au passage

	float base = 0.26;
	vec3 col = parc_color.rgb * (base + 0.45 * clumps + 1.3 * glow) * emission;
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	col *= fade;
	ALBEDO = col;
	EMISSION = col;
	ALPHA = (0.28 + glow * 0.6) * fade;
}
