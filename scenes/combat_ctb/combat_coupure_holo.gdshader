// ============================================================
// combat_coupure_holo.gdshader - Coupure holographique du split de combat.
//
// Remplace l'ancienne ligne de separation (2 traits pleins) : chaque zone de
// combat (heros / adverse) s'arrete un peu avant l'axe de split, laissant un
// vide holographique entre les deux. Ce shader peint EXCLUSIVEMENT ce vide :
// fond uni, glow ambiant, ticks de scanline, sweep vertical, accents
// magenta, point emetteur, et les deux bordures (contour + coeur degrade +
// flux anime). Rien de tout ca ne deborde jamais sur les decors des deux
// cotes — le vide est le seul endroit ou ce shader dessine quoi que ce soit.
//
// Reprend l'AXE DE SPLIT EXISTANT (meme formule que
// CombatFondScinde.x_frontiere, bande_vs_px identique) : gap_frac ajoute
// juste un vide de chaque cote au lieu d'un contact direct entre decors.
// Geometrie du split INCHANGEE — seul ce traitement visuel change.
//
// IMPORTANT : commentaires ASCII pur (parseur de shaders Godot).
// ============================================================
shader_type canvas_item;

uniform vec2  rect_size   = vec2(1280.0, 720.0); // taille reelle du noeud, mise a jour au resize
uniform float bande_vs_px = 80.0;                // meme pente que le split existant
uniform float gap_frac    = 0.009;               // demi-largeur du vide (fraction de la largeur ecran)

// Couleurs (toutes source_color ; le ton le plus clair reste un cyan teinte,
// jamais du blanc pur).
uniform vec4 col_fond    : source_color = vec4(0.0588, 0.0667, 0.0980, 1.0); // #0F1119
uniform vec4 col_glow    : source_color = vec4(0.3412, 0.9098, 1.0000, 1.0); // #57E8FF
uniform vec4 col_tick    : source_color = vec4(0.9098, 0.9765, 1.0000, 1.0); // #E8F9FF
uniform vec4 col_sweep   : source_color = vec4(0.6235, 0.9490, 1.0000, 1.0); // #9FF2FF
uniform vec4 col_magenta : source_color = vec4(0.8392, 0.1412, 0.5608, 1.0); // #D6248F (flux routes HoloMap)
uniform vec4 col_contour : source_color = vec4(0.0196, 0.0431, 0.0706, 1.0); // #050B12
uniform vec4 col_flux    : source_color = vec4(0.4980, 0.9490, 1.0000, 1.0); // #7FF2FF
// Coeur en degrade de chaque bordure (extremite haute -> extremite basse ;
// col_glow reste le coeur commun vers 45% de la hauteur).
uniform vec4 col_bord_g_haut : source_color = vec4(0.5608, 0.4824, 0.8706, 1.0); // #8F7BDE
uniform vec4 col_bord_g_bas  : source_color = vec4(0.4353, 0.3725, 0.7882, 1.0); // #6F5FC9
uniform vec4 col_bord_d_haut : source_color = vec4(0.2471, 0.8392, 0.6902, 1.0); // #3FD6B0
uniform vec4 col_bord_d_bas  : source_color = vec4(0.1843, 0.6824, 0.5608, 1.0); // #2FAE8F

// Timings (secondes), cf. spec "coupure holographique".
uniform float dur_flicker  = 3.4;
uniform float dur_sweep    = 4.5;
uniform float dur_emetteur = 2.6;
uniform float dur_flux_g   = 1.5;
uniform float dur_flux_d   = 1.7;

float hash(float x) { return fract(sin(x * 127.1) * 43758.5453); }

// Position X de l'axe de split a une hauteur uv_y donnee (0 haut, 1 bas) —
// meme formule que CombatFondScinde.x_frontiere (y/h remplace par uv_y).
float axe_x(float uv_y) {
	return rect_size.x * 0.5 + bande_vs_px * (0.5 - uv_y);
}

// Flicker irregulier mais STRICTEMENT periodique (harmoniques du fondamental
// 1/dur_flicker) : plusieurs pics/creux inegaux, jamais de saut en boucle.
float flicker(float t) {
	float w = TAU / dur_flicker;
	float raw = 0.45 * sin(w * t)
			+ 0.25 * sin(2.0 * w * t + 1.3)
			+ 0.18 * sin(3.0 * w * t + 2.7)
			+ 0.12 * sin(5.0 * w * t + 0.6);
	return clamp(0.5 + 0.6 * raw, 0.0, 1.0);
}

// Pulse ease-in-out en boucle continue (0 -> 1 -> 0 sans jamais sauter).
float pulse_ease(float t, float duree) {
	float phase = fract(t / duree);
	return 0.5 - 0.5 * cos(phase * TAU);
}

float glow_ambiant(float dx, float gap_px) {
	float t = clamp(1.0 - abs(dx) / gap_px, 0.0, 1.0);
	return pow(t, 1.6);
}

// Ticks de scanline : petits traits diagonaux repartis en cellules
// irregulieres (grille + hash, meme principe que les fenetres tamisees de
// biome_background.gdshader) plutot qu'une grille parfaite.
float ticks_scanline(float dx, float y, float gap_px) {
	float cell_h = 34.0;
	float cell = floor(y / cell_h);
	if (hash(cell * 3.7 + 11.0) < 0.35) {
		return 0.0;
	}
	float cy = (cell + 0.25 + 0.5 * hash(cell * 1.9 + 5.0)) * cell_h;
	float cx = (hash(cell * 2.3 + 2.0) - 0.5) * 1.1 * gap_px;
	vec2  rel = vec2(dx - cx, y - cy);
	float ca = 0.70710678; // cos/sin de 45 deg
	vec2  rot = vec2(rel.x * ca - rel.y * ca, rel.x * ca + rel.y * ca);
	float in_len = smoothstep(2.0, 1.2, abs(rot.x));
	float in_w   = smoothstep(0.6, 0.2, abs(rot.y));
	return in_len * in_w;
}

float accent_glow(float dy, float dx, float gap_px) {
	float band = exp(-pow(dy / 9.0, 2.0));
	float fall = 1.0 - smoothstep(gap_px * 0.3, gap_px, abs(dx));
	return band * fall;
}

float sweep(vec2 px, float dx, float gap_px) {
	float phase = fract(TIME / dur_sweep);
	// Fondu en entree/sortie : la bande s'efface juste avant de reboucler,
	// plutot que de sauter du bas au haut.
	float envelope = smoothstep(0.0, 0.06, phase) * smoothstep(1.0, 0.94, phase);
	float y_pos = phase * rect_size.y;
	float band = exp(-pow((px.y - y_pos) / 20.0, 2.0));
	float fall = 1.0 - smoothstep(gap_px * 0.2, gap_px, abs(dx));
	return band * fall * envelope;
}

// Point emetteur, tout en haut du gap sur l'axe (y=0) : pulse echelle +
// opacite, suggere que toute la coupure est projetee depuis ce point.
float emetteur(vec2 px) {
	vec2  centre = vec2(axe_x(0.0), 0.0);
	float p = pulse_ease(TIME, dur_emetteur);
	float r = 3.0 + 2.5 * p;
	float d = distance(px, centre);
	return (smoothstep(r, 0.0, d) + 0.4 * smoothstep(r * 2.2, 0.0, d)) * (0.35 + 0.65 * p);
}

// Une bordure du vide (contour sombre + coeur degrade + flux anime).
// d_edge = distance signee au centre du trait ; y_frac = UV.y (0..1) pour le
// degrade vertical ; px_y = position absolue (px) pour la phase du flux.
// Reprend la technique de flux anime des routes HoloMap (holo_route.gdshader,
// pulse qui se deplace via TIME) — un mod() sur la coordonnee le long du
// trait plutot qu'une gaussienne etroite, meme principe.
vec4 bord(float d_edge, float px_y, float y_frac, float dur_flux,
		vec4 col_haut, vec4 col_bas) {
	float ax = abs(d_edge);
	float contour_px = rect_size.x * 0.0025;
	float core_px    = rect_size.x * 0.0012;

	vec3  col = vec3(0.0);
	float alpha = 0.0;

	// Contour sombre, derriere : encaisse le trait dans le fond.
	float a_contour = smoothstep(contour_px, contour_px - 1.5, ax) * 0.85;
	col = mix(col, col_contour.rgb, a_contour);
	alpha = max(alpha, a_contour);

	// Coeur en degrade : violet/teal aux extremites, cyan commun vers 45%.
	vec3 core_col;
	if (y_frac < 0.45) {
		core_col = mix(col_haut.rgb, col_glow.rgb, y_frac / 0.45);
	} else {
		core_col = mix(col_glow.rgb, col_bas.rgb, clamp((y_frac - 0.45) / 0.55, 0.0, 1.0));
	}
	float a_core = smoothstep(core_px, core_px - 1.2, ax);
	col = mix(col, core_col, a_core);
	alpha = max(alpha, a_core);

	// Flux qui coule : tirets courts, defilement continu (decalage anime).
	float period    = 28.0;
	float dash_len  = 2.0;
	float speed     = period / dur_flux;
	float local     = mod(px_y - TIME * speed, period);
	float soft_dash = smoothstep(dash_len, 0.0, local);
	float flux_w    = core_px * 1.8;
	float a_flux    = soft_dash * smoothstep(flux_w, flux_w - 1.2, ax);
	col = mix(col, col_flux.rgb, a_flux);
	alpha = max(alpha, a_flux);

	return vec4(col, alpha);
}

void fragment() {
	vec2  px     = UV * rect_size;
	float y_frac = UV.y;
	float dx     = px.x - axe_x(y_frac);
	float ax     = abs(dx);
	float gap_px = gap_frac * rect_size.x;

	if (ax > gap_px + 8.0) {
		discard;
	}

	float fl = flicker(TIME);

	vec3  col   = vec3(0.0);
	float alpha = 0.0;

	// 1. Fond uni.
	float a_fond = smoothstep(gap_px, gap_px - 1.5, ax);
	col = mix(col, col_fond.rgb, a_fond);
	alpha = max(alpha, a_fond);

	// 2. Glow ambiant.
	float g = glow_ambiant(dx, gap_px) * 0.5 * fl * a_fond;
	col = mix(col, col_glow.rgb, g);
	alpha = max(alpha, g);

	// 3. Ticks de scanline.
	float tk = ticks_scanline(dx, px.y, gap_px) * mix(0.25, 0.5, fl) * a_fond;
	col = mix(col, col_tick.rgb, tk);
	alpha = max(alpha, tk);

	// 4. Sweep.
	float sw = sweep(px, dx, gap_px) * a_fond;
	col = mix(col, col_sweep.rgb, sw);
	alpha = max(alpha, sw);

	// 5. Accents magenta.
	float acc = max(accent_glow(px.y - rect_size.y * 0.18, dx, gap_px),
			max(accent_glow(px.y - rect_size.y * 0.50, dx, gap_px),
					accent_glow(px.y - rect_size.y * 0.82, dx, gap_px)));
	acc *= fl * 0.7 * a_fond;
	col = mix(col, col_magenta.rgb, acc);
	alpha = max(alpha, acc);

	// 6. Point emetteur (haut du gap, sur l'axe).
	float em = emetteur(px);
	col = mix(col, col_magenta.rgb, em);
	alpha = max(alpha, em);

	// Bordures : centre gauche a dx=-gap_px (cote heros), centre droite a
	// dx=+gap_px (cote adverse).
	vec4 bg = bord(dx + gap_px, px.y, y_frac, dur_flux_g, col_bord_g_haut, col_bord_g_bas);
	col = mix(col, bg.rgb, bg.a);
	alpha = max(alpha, bg.a);

	vec4 bd = bord(dx - gap_px, px.y, y_frac, dur_flux_d, col_bord_d_haut, col_bord_d_bas);
	col = mix(col, bd.rgb, bd.a);
	alpha = max(alpha, bd.a);

	COLOR = vec4(col, alpha);
}
