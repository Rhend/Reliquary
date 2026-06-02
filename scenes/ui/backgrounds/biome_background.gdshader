// ============================================================
// biome_background.gdshader - Fond anime parametrique de biome.
//
// Un seul shader pour Foret (silhouettes d'arbres) et Ville (immeubles +
// fenetres). Tout est pilote par uniformes (palette, densite, zone).
//
// canvas_item / GL Compatibility. IMPORTANT : commentaires en ASCII pur,
// le parseur de shaders Godot n'accepte pas l'UTF-8 dans la source.
// ============================================================
shader_type canvas_item;

uniform int   u_mode          = 0;     // 0 = foret, 1 = ville
uniform vec4  sky_top    : source_color = vec4(0.04, 0.06, 0.10, 1.0);
uniform vec4  sky_bottom : source_color = vec4(0.06, 0.12, 0.10, 1.0);
uniform vec4  layer_far  : source_color = vec4(0.06, 0.11, 0.10, 1.0);
uniform vec4  layer_mid  : source_color = vec4(0.04, 0.08, 0.07, 1.0);
uniform vec4  layer_near : source_color = vec4(0.01, 0.03, 0.02, 1.0);
uniform vec4  fog_color  : source_color = vec4(0.30, 0.45, 0.40, 1.0);
uniform vec4  accent     : source_color = vec4(0.70, 0.95, 0.50, 1.0); // lucioles / fenetres
uniform float fog_density    = 0.45;
uniform float zone_darken    = 0.0;    // 0 = Surface .. 1 = Abysse
uniform float anim_speed     = 1.0;
uniform float detail_density = 1.0;
uniform float glow_amount    = 1.0;    // intensite lucioles / fenetres (0 = aucune)
uniform int   split_side     = 0;      // 0 = plein ecran ; 1 = cote heros (gauche) ; 2 = cote creature (droite)
uniform float split_tilt     = 0.12;   // inclinaison de la diagonale (calee sur le separateur VS)

float hash(float x)  { return fract(sin(x * 127.1) * 43758.5453); }
float hash2(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Skyline foret : sommets triangulaires de hauteur variable.
float forest_line(float x, float freq, float h, float seed) {
	float xp = x * freq + seed;
	float i  = floor(xp);
	float f  = fract(xp);
	float top = h * (0.55 + 0.45 * hash(i + seed));
	float tri = 1.0 - abs(f - 0.5) * 2.0;
	tri = pow(max(tri, 0.0), 1.4);
	return top * tri;
}

// Skyline ville : creneaux rectangulaires de hauteur variable par immeuble.
float city_line(float x, float freq, float h, float seed) {
	float i = floor(x * freq + seed);
	return h * (0.30 + 0.70 * hash(i * 1.7 + seed));
}

void fragment() {
	vec2 uv = UV;

	// Decoupe diagonale (cote heros / creature). Diagonale quasi-verticale
	// inclinee comme le separateur VS (haut -> droite, bas -> gauche).
	float a = 1.0;
	if (split_side != 0) {
		float d = (uv.x - 0.5) + split_tilt * (uv.y - 0.5);
		float s = smoothstep(-0.012, 0.012, d);  // 0 = gauche (heros), 1 = droite (creature)
		if (split_side == 1) {
			a = 1.0 - s;
		} else {
			a = s;
		}
	}

	float t  = TIME * anim_speed;
	float yb = 1.0 - uv.y;  // 0 en bas, 1 en haut

	// Ciel degrade
	vec3 col = mix(sky_top.rgb, sky_bottom.rgb, uv.y);

	// Silhouettes parallax (loin -> proche)
	float dd = detail_density;
	float lf;
	float lm;
	float ln;
	if (u_mode == 0) {
		lf = 0.14 + forest_line(uv.x + t * 0.004,  8.0 * dd, 0.12, 3.1);
		lm = 0.18 + forest_line(uv.x + t * 0.011, 12.0 * dd, 0.18, 7.7);
		ln = 0.22 + forest_line(uv.x + t * 0.020, 18.0 * dd, 0.26, 1.3);
	} else {
		lf = 0.16 + city_line(uv.x + t * 0.004, 10.0 * dd, 0.16, 3.1);
		lm = 0.20 + city_line(uv.x + t * 0.011, 16.0 * dd, 0.24, 7.7);
		ln = 0.24 + city_line(uv.x + t * 0.020, 24.0 * dd, 0.34, 1.3);
	}
	if (yb < lf) { col = layer_far.rgb; }
	if (yb < lm) { col = layer_mid.rgb; }
	if (yb < ln) { col = layer_near.rgb; }

	// Fenetres tamisees facon torches / bougies (ville uniquement) : rares et douces
	if (u_mode == 1 && yb < ln) {
		vec2 g    = vec2(uv.x * 30.0 * dd, yb * 22.0);
		vec2 cell = floor(g);
		vec2 fc   = fract(g);
		float lit  = step(0.80, hash2(cell));
		float in_w = step(0.30, fc.x) * step(fc.x, 0.70)
				   * step(0.32, fc.y) * step(fc.y, 0.68);
		float flick = 0.5 + 0.5 * sin(t * 1.5 + hash2(cell) * 31.0);
		col = mix(col, accent.rgb, lit * in_w * flick * 0.55 * glow_amount);
	}

	// Rue pavee (ville uniquement) : bande de premier plan en bas, rangees decalees
	if (u_mode == 1 && yb < 0.12) {
		float row = floor(yb * 10.0);
		float ox  = mod(row, 2.0) * 0.5;
		vec2  pc  = vec2(fract(uv.x * 15.0 + ox), fract(yb * 10.0));
		float bump  = smoothstep(0.5, 0.18, distance(pc, vec2(0.5)));
		float shade = 0.55 + 0.45 * hash2(vec2(floor(uv.x * 15.0 + ox), row));
		vec3  stone = vec3(0.12, 0.10, 0.08) * shade;
		col = mix(vec3(0.015, 0.012, 0.010), stone, bump);  // joints sombres entre paves
	}

	// Lucioles derivantes (foret uniquement)
	if (u_mode == 0) {
		for (int k = 0; k < 7; k++) {
			float fk = float(k);
			float px = fract(hash(fk * 3.3) + t * 0.02 * (0.5 + hash(fk)));
			float py = 0.16 + 0.34 * hash(fk * 5.1) + 0.03 * sin(t * 1.5 + fk);
			vec2  pos = vec2(px, 1.0 - py);
			float dist_f = distance(uv, pos);
			float glow   = smoothstep(0.018, 0.0, dist_f);
			float pulse  = 0.5 + 0.5 * sin(t * 3.0 + fk * 2.0);
			col += accent.rgb * glow * pulse * 0.9 * glow_amount;
		}
	}

	// Brouillard bas, derivant
	float fog_n = 0.5 + 0.5 * sin(uv.x * 7.0 + t * 0.4) * sin(uv.x * 13.0 - t * 0.25);
	float fog = fog_density * (1.0 + zone_darken)
			* smoothstep(0.35, 0.0, uv.y) * (0.6 + 0.4 * fog_n);
	col = mix(col, fog_color.rgb, clamp(fog, 0.0, 0.85));

	// Assombrissement par zone (Surface -> Abysse)
	col *= (1.0 - 0.55 * zone_darken);

	// Vignette + grain
	float vig = 1.0 - smoothstep(0.35, 1.15, distance(uv, vec2(0.5)));
	col *= mix(0.55, 1.0, vig);
	col += (hash2(uv * 1024.0 + t) - 0.5) * 0.025;

	COLOR = vec4(col, a);
}
