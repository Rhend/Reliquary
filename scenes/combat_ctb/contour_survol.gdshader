// Contour de SURVOL d'un personnage (CombatCtbUi, 13/10/2026) : liseré tout
// autour de la silhouette réellement dessinée. S'applique à un CanvasGroup —
// `ecran` y est le tampon du groupe (le sprite seul, fond transparent), donc le
// contour suit la pose animée courante, pas une boîte. `epaisseur` est en
// pixels ÉCRAN (le code la convertit depuis les 2 px de la maquette).
shader_type canvas_item;

uniform sampler2D ecran : hint_screen_texture, filter_linear;
uniform vec4 couleur : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float epaisseur = 2.0;

void fragment() {
	vec4 c = texture(ecran, SCREEN_UV);
	float voisin = 0.0;
	// Deux anneaux (r/2 et r) : un seul anneau laisserait des trous dans le trait.
	for (int i = 0; i < 16; i++) {
		float ang = float(i) * TAU / 16.0;
		vec2 d = vec2(cos(ang), sin(ang)) * SCREEN_PIXEL_SIZE;
		voisin = max(voisin, texture(ecran, SCREEN_UV + d * epaisseur).a);
		voisin = max(voisin, texture(ecran, SCREEN_UV + d * epaisseur * 0.5).a);
	}
	float bord = clamp(voisin - c.a, 0.0, 1.0);
	float a = c.a + bord * (1.0 - c.a);
	vec3 rgb = (c.rgb * c.a + couleur.rgb * bord * (1.0 - c.a)) / max(a, 0.001);
	COLOR = vec4(rgb, a);
}
