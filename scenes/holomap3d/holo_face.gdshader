// ============================================================
// holo_face.gdshader - Facades holographiques VIVANTES (cyberpunk).
//
// Remplit les faces exterieures des batiments : corps sombre semi-transparent
// (ECRIT la profondeur -> occlusion anti-fouillis) MAIS parcouru de lumiere :
//   * teinte de DISTRICT (coeur cyan/blanc chaud -> peripherie froide/malade),
//     derivee de la distance au centre (meme loi que le gradient de richesse) ;
//   * BANDES D'ETAGE emissives (lignes horizontales) -> gratte-ciel habite ;
//   * PULSE de scan vertical qui remonte la facade (donnees qui circulent) ;
//   * FENETRES allumees (grille ambre chaude, scintillement doux).
// Les bandes/pulse ne s'appliquent qu'aux PAROIS (masque par la normale), pas
// aux toits. Tout reste sous le seuil de glow sauf les fenetres -> la ville
// brille sans avaler le wireframe.
//
// IMPORTANT : commentaires ASCII pur (parseur de shaders Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled;

uniform vec4  face_color : source_color = vec4(0.02, 0.03, 0.06, 1.0);
uniform float opacite = 0.5;
uniform float reveal_r = 100000.0;   // rayon de materialisation (intro)
uniform vec4  fenetre_color : source_color = vec4(0.95, 0.85, 0.55, 1.0); // ambre chaud
uniform float fenetre_densite = 0.16; // proportion de fenetres allumees
uniform float fenetre_taille = 0.16;  // taille d'une fenetre (unites monde)
uniform float fenetre_emission = 1.4; // gain d'emission des fenetres

// --- Teinte de district (gradient coeur -> peripherie) ---
uniform vec4  glow_coeur : source_color = vec4(0.35, 0.95, 1.00, 1.0); // cyan chaud (centre riche)
uniform vec4  glow_peripherie : source_color = vec4(0.16, 0.30, 0.52, 1.0); // bleu froid (abandon)
uniform float glow_force = 0.34;      // intensite de la lueur de structure
uniform float rich_coeur = 0.32;      // rayon (normalise) du coeur a pleine vie
uniform float rich_chute = 1.35;      // raideur de la chute vers la peripherie
uniform float rich_rmax = 10.0;       // demi-diagonale monde de la grille

// --- Bandes d'etage + pulse de scan ---
uniform float etage_haut = 0.14;      // hauteur monde d'un etage (periode des bandes)
uniform float etage_force = 0.5;      // intensite des lignes de plancher
uniform float pulse_vitesse = 0.16;   // vitesse de remontee du scan
uniform float pulse_force = 0.6;      // intensite du front lumineux

varying vec3 w_pos;
varying vec3 w_nrm;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Richesse 1 (coeur) -> 0 (peripherie), meme loi que HoloMap3D._richesse.
float richesse(vec2 xz) {
	float dn = length(xz) / max(0.001, rich_rmax);
	float t = clamp((dn - rich_coeur) / max(0.001, 1.0 - rich_coeur), 0.0, 1.0);
	return pow(1.0 - t, rich_chute);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	if (length(w_pos.xz) > reveal_r) {
		discard;
	}
	// Fenetres : grille sur les 2 axes tangents a la face (selon la normale).
	vec3 an = abs(w_nrm);
	vec2 uvw;
	if (an.x >= an.z && an.x >= an.y) {
		uvw = vec2(w_pos.z, w_pos.y);
	} else if (an.z >= an.x && an.z >= an.y) {
		uvw = vec2(w_pos.x, w_pos.y);
	} else {
		uvw = vec2(w_pos.x, w_pos.z); // toit
	}
	vec2 g = uvw / fenetre_taille;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float lit = step(1.0 - fenetre_densite, h21(cell));
	float win = step(0.25, f.x) * step(f.x, 0.78) * step(0.3, f.y) * step(f.y, 0.82);
	float tw = 0.55 + 0.45 * sin(TIME * 1.3 + h21(cell) * 53.0);
	float w = lit * win * tw;

	// District : teinte + vie qui decroissent vers la peripherie.
	float rich = richesse(w_pos.xz);
	vec3 tint = mix(glow_peripherie.rgb, glow_coeur.rgb, rich);
	float vie = mix(0.45, 1.0, rich);   // peripherie a l'abandon -> plus eteinte

	// Paroi (normale horizontale) vs TOIT (normale verticale) : les deux brillent,
	// mais differemment (barres d'etage sur les murs, balayage sur les toits).
	float mur = 1.0 - clamp(abs(normalize(w_nrm + vec3(0.0, 0.0001, 0.0)).y), 0.0, 1.0);
	float toit = 1.0 - mur;

	// Bandes d'etage (murs) : ligne emissive a chaque plancher (pic NET -> creve le
	// seuil de bloom -> vraies barres lumineuses, pas un voile).
	float fy = fract(w_pos.y / max(0.001, etage_haut));
	float bande = pow(smoothstep(0.30, 1.0, 1.0 - abs(fy - 0.5) * 2.0), 2.5);

	// Scan vertical (murs) : front lumineux qui remonte la facade en boucle.
	float vphase = fract(w_pos.y * 0.45 - TIME * pulse_vitesse);
	float vscan = exp(-pow((vphase - 0.5) / 0.16, 2.0));

	// Balayage de toit (XZ) : onde qui traverse les toits -> rooftops vivants vus
	// du dessus (la camera plonge -> on voit surtout les toits, jamais noirs).
	float rphase = fract((w_pos.x + w_pos.z) * 0.5 - TIME * pulse_vitesse * 1.3);
	float rscan = exp(-pow((rphase - 0.5) / 0.18, 2.0));

	// Corps VITRE : toute face porte une lueur de district (jamais de noir mort),
	// qui respire ; les barres/scan crevent le bloom par-dessus.
	float base = glow_force * (0.7 + 0.3 * sin(TIME * 0.7 + rich * 6.0));
	float wall_lum = mur * (etage_force * bande + pulse_force * vscan);
	float roof_lum = toit * (0.35 + pulse_force * 0.8 * rscan);
	float lum = (base + wall_lum + roof_lum) * vie;
	vec3 tintcol = tint * lum;
	vec3 windows = fenetre_color.rgb * w * fenetre_emission;

	// IMPORTANT (GL Compatibility) : en `unshaded`, la couleur VISIBLE vient de
	// ALBEDO ; EMISSION ne nourrit que le bloom. On met donc la lueur de district
	// dans ALBEDO (corps vitre coloré) ET dans EMISSION (les barres/scan/fenêtres
	// qui dépassent le seuil HDR floutent) -> bâtiments lumineux, plus de blocs noirs.
	ALBEDO = face_color.rgb + tintcol;
	EMISSION = tintcol + windows;
	// Corps plus dense (moins « vitre vide ») la ou ca s'allume.
	ALPHA = clamp(opacite + w * 0.5 + (bande * mur + rscan * toit + 0.3 * vscan) * 0.3, 0.0, 1.0);
}
