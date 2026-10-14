# ============================================================
# StockConsommables — stock PERSISTANT de consommables du QG (inventaire de
# l'Atelier, 14/10/2026). Supersède la règle « consommables de run, purgés en
# fin de run » du chantier 7 : ce qui reste en poche à la sortie est conservé.
#
# État : `GameData.player["consommables"]` (id → quantité). Sous-dict de
# `player` donc sauvegardé automatiquement ; merge tolérant → une ancienne
# sauvegarde sans la clé démarre à vide, aucune migration (SAVE_VER inchangé).
#
# Règles de run (acté avec Rhend) :
#   • TOUT le stock part en expédition (ExpeRun.demarrer → `pour_la_run`).
#   • À la sortie normale (extraction OU étage bouclé), le stock devient ce
#     qui reste dans l'inventaire de run (`enregistrer_fin_de_run`) — les
#     trouvailles de coffre sont donc gardées, les objets utilisés consommés.
#   • DÉFAITE : le stock n'est pas touché ; le Game Over recharge de toute
#     façon la sauvegarde du lancement.
#
# Catalogue : les .tres de `data/expedition/consommables/` — un nouveau
# consommable = un fichier, rien d'autre à toucher.
# class_name statique (pas autoload), pattern Balance/ProgressionHeros.
# ============================================================
class_name StockConsommables

const DOSSIER := "res://data/expedition/consommables/"

static var _catalogue: Dictionary = {}   # id → ConsommableData (cache de session)

# ─── Catalogue ───────────────────────────────────────────────

static func catalogue() -> Dictionary:
	if _catalogue.is_empty():
		var dir := DirAccess.open(DOSSIER)
		if dir != null:
			for f in dir.get_files():
				# Export : les ressources sont listées en « .tres.remap ».
				var nom := f.trim_suffix(".remap")
				if not nom.ends_with(".tres"):
					continue
				var res := load(DOSSIER + nom) as ConsommableData
				if res != null and res.id != "":
					_catalogue[res.id] = res
	return _catalogue

static func definition(id: String) -> ConsommableData:
	return catalogue().get(id) as ConsommableData

# ─── Stock ───────────────────────────────────────────────────

static func _stock() -> Dictionary:
	if not GameData.player.has("consommables") \
			or not (GameData.player["consommables"] is Dictionary):
		GameData.player["consommables"] = {}
	return GameData.player["consommables"]

static func quantite(id: String) -> int:
	return int(_stock().get(id, 0))

static func total() -> int:
	var n := 0
	for id: String in _stock():
		n += int(_stock()[id])
	return n

# Copie (id → quantité > 0) du stock courant.
static func contenu() -> Dictionary:
	var out: Dictionary = {}
	for id: String in _stock():
		if int(_stock()[id]) > 0:
			out[id] = int(_stock()[id])
	return out

static func ajouter(id: String, qte: int = 1) -> void:
	if qte <= 0 or id == "":
		return
	_stock()[id] = quantite(id) + qte
	EventBus.resources_changed.emit()   # déclencheur de sauvegarde + rafraîchissement UI

static func retirer(id: String, qte: int = 1) -> bool:
	if qte <= 0 or quantite(id) < qte:
		return false
	var reste := quantite(id) - qte
	if reste > 0:
		_stock()[id] = reste
	else:
		_stock().erase(id)
	EventBus.resources_changed.emit()
	return true

# ─── Run ─────────────────────────────────────────────────────

# Inventaire de DÉPART d'une run : tout le stock (ids inconnus ignorés).
static func pour_la_run() -> Array[ConsommableData]:
	var out: Array[ConsommableData] = []
	for id: String in contenu():
		var def := definition(id)
		if def == null:
			continue
		for i in quantite(id):
			out.append(def)
	return out

# Sortie normale : le stock devient le contenu restant de l'inventaire de run.
static func enregistrer_fin_de_run(inventaire: Array) -> void:
	var nouveau: Dictionary = {}
	for c in inventaire:
		var def := c as ConsommableData
		if def != null and def.id != "":
			nouveau[def.id] = int(nouveau.get(def.id, 0)) + 1
	GameData.player["consommables"] = nouveau
	EventBus.resources_changed.emit()

# ─── Craft ───────────────────────────────────────────────────

# Peut-on fabriquer UN exemplaire ? (Euren + Modules + matériaux disponibles)
static func peut_fabriquer(def: ConsommableData) -> bool:
	if def == null or not def.fabricable():
		return false
	if ProgressionHeros.euren() < def.cout_euren:
		return false
	if ProgressionHeros.modules() < def.cout_modules:
		return false
	for rid: String in def.cout_materiaux:
		if int(GameData.player["resources"].get(rid, 0)) < int(def.cout_materiaux[rid]):
			return false
	return true

# Fabrique UN exemplaire : débite puis ajoute au stock. false si impossible.
static func fabriquer(def: ConsommableData) -> bool:
	if not peut_fabriquer(def):
		return false
	ProgressionHeros.depenser_euren(def.cout_euren)
	ProgressionHeros.depenser_modules(def.cout_modules)
	for rid: String in def.cout_materiaux:
		GameData.player["resources"][rid] = \
				int(GameData.player["resources"].get(rid, 0)) - int(def.cout_materiaux[rid])
	ajouter(def.id, 1)   # émet resources_changed (matériaux compris)
	return true
