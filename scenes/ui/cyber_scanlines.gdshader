// Scanlines SOBRES de la peau cyberpunk intérimaire (chantier 10) :
// une ligne sur deux légèrement assombrie + très léger vignettage.
// Pas de glitch permanent (fatigue) — intensité pilotée par `force`.
shader_type canvas_item;

uniform float force : hint_range(0.0, 0.5) = 0.10;
uniform float periode : hint_range(2.0, 8.0) = 3.0;

void fragment() {
	float ligne = step(0.5, fract(FRAGCOORD.y / periode));
	float vignette = smoothstep(0.55, 1.15, length(UV - vec2(0.5)) * 1.3);
	COLOR = vec4(0.0, 0.0, 0.0, ligne * force + vignette * 0.22);
}
