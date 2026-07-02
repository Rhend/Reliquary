// ============================================================
// holo_neon.gdshader - Materiau NEON (aretes emissives "vivantes").
//
// Variante de holo_line pour les accents neon (enseignes, cretes de toit,
// marquages, couronnes). Trois ingredients qui font un vrai neon :
//   1. COEUR BLANC SURCHAUFFE : la couleur est tiree vers le blanc et
//      poussee en HDR bien au-dessus du seuil de glow -> a l'ecran le coeur
//      sature vers le blanc, et c'est le BLOOM qui peint le halo colore
//      autour (les canaux forts dominent le flou).
//   2. RESPIRATION : pulsation lente et legere de l'intensite, dephasee
//      spatialement (toute la carte ne respire pas en meme temps).
//   3. GRESILLEMENT (flicker d'amorcage) : rarement, un element "decroche"
//      une fraction de seconde. Probabilite = flicker_base partout
//      + flicker_periph ponderee par la distance au centre (la peripherie
//      pauvre gresille, le coeur corpo est impeccable).
//
// Uniforms fog/reveal/focus IDENTIQUES a holo_line (les rails de HoloMap3D
// poussent ces parametres sur tous les materiaux de lignes sans distinction).
// IMPORTANT : commentaires ASCII pur.
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float emission_strength = 4.2;  // gain HDR fort (coeur qui clippe au blanc)
uniform float alpha_mult = 1.0;
uniform float fog_debut = 16.0;
uniform float fog_fin = 30.0;
uniform float fog_min = 0.25;
uniform float reveal_r = 100000.0;
uniform vec2  focus_pos = vec2(0.0);
uniform float focus_force = 0.0;
uniform float focus_rayon = 2.2;
// --- Neon ---
uniform float coeur_blanc = 0.35;       // part de blanc injectee dans le coeur (0..1)
uniform float respiration_amp = 0.10;   // amplitude de la pulsation lente (+-10 %)
uniform float respiration_freq = 1.5;   // rad/s (~4.2 s par cycle)
uniform float flicker_base = 0.0;       // proba de gresillement partout (0..1)
uniform float flicker_periph = 0.0;     // proba ADDITIONNELLE en peripherie (0..1)
uniform float rich_rmax = 12.0;         // rayon du gradient de richesse (= demi-carte)

varying vec3 w_pos;

float h11(float p) { return fract(sin(p * 127.1) * 43758.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dxz = length(w_pos.xz);
	if (dxz > reveal_r) {
		discard;
	}
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	float front = smoothstep(reveal_r - 0.6, reveal_r, dxz);
	float foc = focus_force * (1.0 - smoothstep(0.0, focus_rayon, distance(w_pos.xz, focus_pos)));

	// 2. Respiration : phase tiree d'une cellule spatiale (~1.5 u) -> les tubes
	// d'un meme element respirent ensemble, les elements entre eux sont dephases.
	vec2 cell = floor(w_pos.xz / 1.5);
	float phase = h21(cell) * 6.2831;
	float inten = 1.0 + respiration_amp * sin(TIME * respiration_freq + phase);

	// 3. Gresillement : evenement RARE. Fenetres de 4 s par cellule ; si la
	// cellule tire une panne, elle ne dure que 0.25-0.6 s en DEBUT de fenetre
	// (le reste de la fenetre, le tube brille normalement). proba = chance de
	// panne par fenetre de 4 s -> 0.2 = un decrochage toutes les ~20 s.
	// Cellule de flicker LARGE (3 u) : un element entier decroche d'un bloc,
	// pas un patchwork de segments qui scintillent.
	float periph = smoothstep(0.70, 1.00, dxz / max(rich_rmax, 0.001));
	float proba = clamp(flicker_base + flicker_periph * periph, 0.0, 0.6);
	if (proba > 0.001) {
		vec2 cellf = floor(w_pos.xz / 3.0);
		float slot = floor(TIME * 0.25);
		float roll = h21(cellf + vec2(slot * 0.613, slot * 0.171));
		if (roll < proba) {
			float tin = fract(TIME * 0.25) * 4.0;              // secondes ecoulees dans la fenetre
			float dur = 0.25 + 0.35 * h11(roll * 51.0);        // panne de 0.25 a 0.6 s
			if (tin < dur) {
				float j = h11(floor(TIME * 34.0) + h21(cellf) * 97.0);
				inten *= mix(0.10, 0.55, step(0.5, j));        // crachote entre 10 % et 55 %
			}
		}
	}

	// 1. Coeur blanc : le blanc s'ajoute proportionnellement a l'intensite
	// courante (un tube en panne retombe sur sa couleur de gaz, pas du blanc).
	vec3 base = mix(COLOR.rgb, vec3(1.0), coeur_blanc * clamp(inten, 0.0, 1.0));
	float boost = 1.0 + 1.4 * foc + 2.5 * front;
	vec3 c = base * emission_strength * inten * fade * boost;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = COLOR.a * alpha_mult * fade * (1.0 + 0.5 * foc + front);
}
