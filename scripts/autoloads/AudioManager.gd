# ============================================================
# AudioManager — Hub audio centralisé (autoload).
#
# Point d'entrée unique pour tout le son du jeu (bruitages aujourd'hui,
# bande-son à venir). Responsabilités :
#   • Crée les bus « Music » et « SFX » (routés vers Master) au démarrage,
#     sans dépendre d'un default_bus_layout.tres.
#   • Bibliothèque de sons NOMMÉS. Pour l'instant générés en procédural ;
#     à terme on chargera des fichiers (res://audio/…) sous le même nom,
#     sans toucher aux appelants.
#   • SFX « fire-and-forget » via un pool de players → sons simultanés.
#   • Musique : un player dédié (play/stop), bus séparé pour régler le volume.
#   • Volume par bus (à brancher plus tard sur les réglages / GameSettings).
#
# API :
#   AudioManager.play_sfx("evolve_ready", -5.0)     # bruitage ponctuel
#   AudioManager.stream("ritual_drone")             # pour un player maison
#   AudioManager.play_music("…") / stop_music()
#   AudioManager.set_bus_volume("SFX", 0.8)         # niveau linéaire 0..1
# ============================================================
extends Node

const MUSIC_BUS := "Music"
const SFX_BUS   := "SFX"
const SFX_VOICES := 8        # bruitages simultanés avant recyclage

var _streams:  Dictionary = {}                 # nom → AudioStream
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _music:    AudioStreamPlayer = null

func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_build_library()

	for _i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_sfx_pool.append(p)

	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)

# ═══════════════════════════════════════════════════════════
#  Bus
# ═══════════════════════════════════════════════════════════

# Crée le bus s'il n'existe pas (routé vers Master). Idempotent.
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

# Règle le volume d'un bus depuis un niveau linéaire 0..1 (0 → coupé). Centralise
# la conversion linéaire→dB et le mute (utilisé par GameSettings pour les
# réglages Musique/SFX).
func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear) if linear > 0.0 else -80.0)

# ═══════════════════════════════════════════════════════════
#  Bibliothèque de sons
# ═══════════════════════════════════════════════════════════

func _build_library() -> void:
	# Famille « cloche » (rituel + notifications) : même timbre, hauteur/decay
	# distincts. Drone grave = montée rituelle.
	_streams["ritual_drone"]   = _gen_drone(160.0, 3.0)
	_streams["ritual_crystal"] = _gen_bell(2400.0, 0.6, 8.0)
	_streams["evolve_ready"]   = _gen_bell(1318.5, 0.5, 13.0)

	# Placeholders (à remplacer par de vrais fichiers sous le même nom) :
	_streams["ui_select"]          = _gen_blip(720.0, 0.09)               # clic UI net
	_streams["attack"]             = _gen_whoosh(0.16)                    # souffle d'attaque
	_streams["trap_appear"]        = _gen_menace(110.0, 0.55)             # grave, menaçant
	_streams["benediction_appear"] = _gen_arpeggio(                       # arpège majeur joyeux
			[523.25, 659.25, 783.99], 0.10, 7.0)

# Stream nommé, pour un appelant qui gère son propre player (son séquencé /
# pitché, ex. le rituel d'évolution). null si inconnu.
func stream(sound_name: String) -> AudioStream:
	return _streams.get(sound_name, null)

# ═══════════════════════════════════════════════════════════
#  Lecture
# ═══════════════════════════════════════════════════════════

# Bruitage ponctuel : joué sur la prochaine voix libre du pool (recyclage
# circulaire → les sons rapprochés se superposent au lieu de se couper).
func play_sfx(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStream = _streams.get(sound_name, null)
	if s == null:
		push_warning("AudioManager: son inconnu '%s'" % sound_name)
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream      = s
	p.volume_db   = volume_db
	p.pitch_scale = pitch
	p.play()

func play_music(sound_name: String, volume_db: float = 0.0) -> void:
	var s: AudioStream = _streams.get(sound_name, null)
	if s == null or _music == null:
		return
	_music.stream    = s
	_music.volume_db = volume_db
	_music.play()

func stop_music() -> void:
	if _music and _music.playing:
		_music.stop()

# ═══════════════════════════════════════════════════════════
#  Générateurs procéduraux (16 bits mono)
#  Provisoires : remplaçables par des fichiers chargés sous le même nom.
# ═══════════════════════════════════════════════════════════

# Cloche brillante : fondamentale + 2 harmoniques (légèrement inharmoniques pour
# le grain métallique) à décroissance exponentielle. Attaque sèche.
func _gen_bell(freq: float, dur: float, decay: float) -> AudioStreamWAV:
	var sr := 22050
	var n  := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		var t   := float(i) / float(sr)
		var env := exp(-t * decay)
		var s := (sin(t * freq * TAU) * 0.58
				+ sin(t * freq * 2.01 * TAU) * 0.27
				+ sin(t * freq * 3.01 * TAU) * 0.12) * env * 0.55
		_put_s16(data, i, s)
	return _finish_wav(sr, data)

# Bourdon grave sinusoïdal avec fondus d'entrée/sortie (fade) symétriques.
func _gen_drone(freq: float, dur: float) -> AudioStreamWAV:
	var sr   := 11025
	var n    := int(sr * dur)
	var fade := 0.3
	var data := PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		var t   := float(i) / float(sr)
		var env := 1.0
		if t < fade:
			env = t / fade
		elif t > dur - fade:
			env = 1.0 - (t - (dur - fade)) / fade
		_put_s16(data, i, sin(t * freq * TAU) * 0.35 * env)
	return _finish_wav(sr, data)

# Blip court : sinus à décroissance très rapide + court fondu d'attaque
# (anti-clic). Pour les clics d'interface.
func _gen_blip(freq: float, dur: float) -> AudioStreamWAV:
	var sr := 22050
	var n  := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		var t   := float(i) / float(sr)
		var env := exp(-t * 32.0)
		if t < 0.002:                       # fondu d'attaque 2 ms (évite le « clic »)
			env *= t / 0.002
		_put_s16(data, i, sin(t * freq * TAU) * 0.5 * env)
	return _finish_wav(sr, data)

# Souffle / whoosh : bruit blanc adouci (lissage 1 pôle) sous une enveloppe
# triangulaire (montée brève, descente longue). Pour le lancement d'attaque.
func _gen_whoosh(dur: float) -> AudioStreamWAV:
	var sr := 22050
	var n  := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	for i: int in n:
		var frac := float(i) / float(n)
		var env := frac / 0.25 if frac < 0.25 else 1.0 - (frac - 0.25) / 0.75
		prev = lerpf(prev, randf() * 2.0 - 1.0, 0.30)   # passe-bas simple
		_put_s16(data, i, prev * 0.6 * clampf(env, 0.0, 1.0))
	return _finish_wav(sr, data)

# Tonalité grave et menaçante : deux sinus détunés (battement glauque) + une
# harmonique, décroissance moyenne. Pour l'apparition d'un piège (danger).
func _gen_menace(freq: float, dur: float) -> AudioStreamWAV:
	var sr := 22050
	var n  := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		var t   := float(i) / float(sr)
		var env := exp(-t * 5.0)
		var s := (sin(t * freq * TAU) * 0.5
				+ sin(t * freq * 1.04 * TAU) * 0.4
				+ sin(t * freq * 2.0 * TAU) * 0.15) * env * 0.55
		_put_s16(data, i, s)
	return _finish_wav(sr, data)

# Arpège ascendant de cloches (accord donné), notes égrenées toutes les
# `note_dur` s, chacune en décroissance. Pour l'apparition d'une bénédiction.
func _gen_arpeggio(freqs: Array, note_dur: float, decay: float) -> AudioStreamWAV:
	var sr := 22050
	var total := note_dur * float(freqs.size()) + 0.4   # queue pour la dernière note
	var n := int(sr * total)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		var t := float(i) / float(sr)
		var s := 0.0
		for k: int in freqs.size():
			var onset := note_dur * float(k)
			if t >= onset:
				var tt := t - onset
				var env := exp(-tt * decay)
				var f: float = freqs[k]
				s += (sin(tt * f * TAU) * 0.6 + sin(tt * f * 2.01 * TAU) * 0.25) * env
		_put_s16(data, i, clampf(s * 0.4, -1.0, 1.0))
	return _finish_wav(sr, data)

# Écrit un échantillon float [-1,1] en 16 bits little-endian à l'index i.
func _put_s16(data: PackedByteArray, i: int, sample: float) -> void:
	var v := clampi(int(clampf(sample, -1.0, 1.0) * 32767.0), -32768, 32767)
	data[i * 2 + 0] = v & 0xFF
	data[i * 2 + 1] = (v >> 8) & 0xFF

func _finish_wav(sr: int, data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo   = false
	wav.mix_rate = sr
	wav.data     = data
	return wav
