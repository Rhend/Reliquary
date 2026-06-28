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
	float vie = mix(0.35, 1.0, rich);   // peripherie a l'abandon -> plus eteinte

	// Paroi (normale horizontale) vs toit -> bandes/pulse seulement sur les murs.
	float mur = 1.0 - clamp(abs(normalize(w_nrm + vec3(0.0, 0.0001, 0.0)).y), 0.0, 1.0);

	// Bandes d'etage : fine ligne emissive a chaque plancher.
	float fy = fract(w_pos.y / max(0.001, etage_haut));
	float bande = smoothstep(0.5, 1.0, 1.0 - abs(fy - 0.5) * 2.0);  // pic etroit
	bande = pow(bande, 6.0);

	// Pulse de scan : front doux qui remonte la facade en boucle.
	float pphase = fract(w_pos.y * 0.5 - TIME * pulse_vitesse);
	float pulse = exp(-pow((pphase - 0.5) / 0.10, 2.0));

	float struct_lum = (glow_force * 0.5
		+ etage_force * bande
		+ pulse_force * pulse) * mur * vie;

	vec3 emi = tint * struct_lum + fenetre_color.rgb * w * fenetre_emission;

	ALBEDO = face_color.rgb;
	EMISSION = emi;
	// Fenetres + bandes rendent la paroi un peu plus opaque (corps plus dense).
	ALPHA = clamp(opacite + w * 0.5 + bande * mur * 0.18, 0.0, 1.0);
}
