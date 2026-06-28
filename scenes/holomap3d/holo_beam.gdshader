// ============================================================
// holo_beam.gdshader - Faisceau vertical de tour corpo (spire holographique).
//
// Applique a un QUAD vertical (PRIMITIVE_TRIANGLES) plante au sommet d'une tour.
// Billboard CYLINDRIQUE : le quad pivote autour de l'axe vertical pour faire face
// a la camera (l'axe monde +Y est preserve) -> un vrai SHAFT de lumiere lisible
// sous tout angle d'orbite. Brillant a la source (bas), s'eteint en montant, avec
// des impulsions d'energie qui remontent le faisceau (donnees qui s'elevent).
//
// Encodage par sommet :
//   VERTEX.y = hauteur monde le long du faisceau (0 = base au sommet de la tour)
//   UV.x     = t normalise (0 base -> 1 sommet du faisceau)
//   UV2.x    = cote du quad (-1 / +1), UV2.y = demi-largeur monde a la base
//   COLOR    = teinte du district (rgb) + alpha de base
//
// Additif, sans ecriture de profondeur. Commentaires ASCII pur (parseur Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float emission = 2.4;     // gain HDR (declenche le glow)
uniform float taper = 0.72;       // retrecissement du faisceau en montant (0..1)
uniform float pulse_vitesse = 3.0; // vitesse des impulsions montantes
uniform float fog_debut = 18.0;
uniform float fog_fin = 34.0;
uniform float fog_min = 0.35;

varying float v_t;
varying float v_side;
varying vec3  v_wpos;

void vertex() {
	float t = UV.x;
	float hw = UV2.y * mix(1.0, 1.0 - taper, t);   // se resserre vers le haut
	vec3 base = MODEL_MATRIX[3].xyz;               // base du faisceau (sommet de tour)
	vec3 camR = INV_VIEW_MATRIX[0].xyz;            // droite camera...
	camR.y = 0.0;                                  // ...projetee a l'horizontale (axe +Y garde)
	camR = normalize(camR + vec3(0.0001, 0.0, 0.0));
	vec3 wpos = base + vec3(0.0, VERTEX.y, 0.0) + camR * (UV2.x * hw);
	v_wpos = wpos;
	v_t = t;
	v_side = UV2.x;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}

void fragment() {
	float horiz = pow(clamp(1.0 - abs(v_side), 0.0, 1.0), 1.6); // coeur lumineux, bords doux
	float vert = 1.0 - v_t;                                     // brillant a la source
	vert *= vert;
	float pulse = 0.55 + 0.45 * sin(v_t * 16.0 - TIME * pulse_vitesse);
	float d = distance(v_wpos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	float a = COLOR.a * horiz * (0.12 + 0.88 * vert) * fade;
	vec3 c = COLOR.rgb * emission * horiz * (0.30 + vert) * pulse * fade;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = a;
}
