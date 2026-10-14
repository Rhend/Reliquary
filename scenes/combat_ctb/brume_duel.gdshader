// Brume noire de bordure du zoom-duel : assombrit le POURTOUR de l'écran pour
// recentrer le regard sur l'action. Pas un cadre lisse — un voile de brume
// (bruit fractal lent) qui mord irrégulièrement vers le centre.
shader_type canvas_item;

// 0 = invisible, 1 = plein effet (animé par CombatCtbUi pendant le duel).
uniform float intensite : hint_range(0.0, 1.0) = 0.0;
// Part de l'écran (depuis chaque bord) qui plonge dans le noir.
uniform float largeur : hint_range(0.0, 0.5) = 0.15;
// Opacité maximale de la brume au bord extrême.
uniform float force : hint_range(0.0, 1.0) = 0.92;
// Irrégularité du front de brume (en fraction d'écran).
uniform float turbulence : hint_range(0.0, 0.3) = 0.09;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * bruit(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// Distance au bord le plus proche, 0 au bord, 0.5 au centre.
	vec2 d = min(UV, 1.0 - UV);
	// Mélange min() + moyenne géométrique : coins plus sombres que les
	// milieux de côté, sans arête franche à la diagonale.
	float bord = min(d.x, d.y) * 0.6 + sqrt(d.x * d.y) * 0.4;
	// Brume qui dérive lentement.
	vec2 q = UV * vec2(4.0, 2.4) + vec2(TIME * 0.05, -TIME * 0.03);
	float n = fbm(q) - 0.5;
	float profondeur = bord + n * turbulence;
	float m = 1.0 - smoothstep(0.0, largeur, profondeur);
	COLOR = vec4(0.0, 0.0, 0.0, m * force * intensite);
}
