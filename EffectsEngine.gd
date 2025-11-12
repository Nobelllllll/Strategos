extends Node
class_name EffectsEngine

# --------------------------------------------------------------------
# Effets commandants
# --------------------------------------------------------------------
static var effects_by_hook: Dictionary = {
	"on_move_attempt": [],
	"on_attack_compute": [],
	"on_damage_before": []
}

# --------------------------------------------------------------------
# Tactiques actives pendant la partie
# On stocke toujours sous la forme :
#   { "tactic": <dict de la carte>, "grand_tour": <int> }
# --------------------------------------------------------------------
static var active_tactics: Dictionary = {
	"RED": [],
	"BLUE": []
}

# --------------------------------------------------------------------
# Chargement des effets de commandants
# --------------------------------------------------------------------
static func load_definitions(defs_source) -> void:
	var defs: Array = []
	if typeof(defs_source) == TYPE_STRING:
		var f := FileAccess.open(defs_source, FileAccess.READ)
		if f == null:
			push_error("EffectsEngine: impossible d'ouvrir " + defs_source)
			return
		var txt := f.get_as_text()
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_ARRAY:
			defs = parsed
	elif typeof(defs_source) == TYPE_ARRAY:
		defs = defs_source
	else:
		return

	# reset
	for k in effects_by_hook.keys():
		effects_by_hook[k] = []

	for e in defs:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if not e.has("effects"):
			continue

		var cid := str(e.get("id", ""))
		for eff in e["effects"]:
			if typeof(eff) != TYPE_DICTIONARY:
				continue
			var hook := str(eff.get("hook", ""))
			if not effects_by_hook.has(hook):
				continue
			eff["_cid"] = cid
			effects_by_hook[hook].append(eff)

# ====================================================================
# ============  TACTIQUES : API publique =============================
# ====================================================================

# appelé par le GameManager quand une carte tactique est jouée
static func apply_tactic(tactic_data: Dictionary, ctx: Dictionary) -> void:
	if tactic_data.is_empty():
		return

	var player := str(ctx.get("current_player", "BLUE"))
	var phase_at_play := str(ctx.get("current_phase", ""))

	if not active_tactics.has(player):
		active_tactics[player] = []

	# on clone pour ne pas modifier le JSON d’origine
	var clone := tactic_data.duplicate(true)
	clone["_played_phase"] = phase_at_play
	clone["_player"] = player

	active_tactics[player].append(clone)
	print("EffectsEngine: tactique activée pour ", player, " en phase ", phase_at_play, ": ", clone.get("id", ""))


# Supprime toutes les tactiques d'un joueur qui ont été jouées dans une phase différente
# de la phase courante.
static func clear_tactics_for(player: String, current_phase: String) -> void:
	if not active_tactics.has(player):
		return

	var kept: Array = []
	for entry in active_tactics[player]:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_phase: String = entry.get("phase", "")
		if entry_phase == current_phase:
			kept.append(entry)
		# sinon on la laisse tomber

	active_tactics[player] = kept


# à appeler au début d’un “grand tour” (depuis GameManager)
static func clear_tactics_older_than(current_gt: int) -> void:
	for player in active_tactics.keys():
		var fresh: Array = []
		for entry in active_tactics[player]:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var e_gt := int(entry.get("grand_tour", 0))
			if e_gt >= current_gt:
				fresh.append(entry)
		active_tactics[player] = fresh

static func clear_all_tactics() -> void:
	active_tactics["RED"] = []
	active_tactics["BLUE"] = []

# ====================================================================
# ============  HOOKS ================================================
# ====================================================================

# ctx : { board, player, from, to, mover_card, game_manager }
static func on_move_attempt(ctx: Dictionary) -> Dictionary:
	var result: Dictionary = {"forbid": false}

	# 1) effets de commandants
	var list: Array = effects_by_hook["on_move_attempt"]
	for eff in list:
		var local_ctx: Dictionary = ctx.duplicate()
		local_ctx["_current_effect"] = eff
		var ok := _evaluate_effect_for_hook(eff, local_ctx, "on_move_attempt")
		if not ok.get("applies", false):
			continue
		for a in eff.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if a.has("forbid_move") and bool(a["forbid_move"]):
				result["forbid"] = true
				return result

	# 2) tactiques
	var mover_card = ctx.get("mover_card", null)
	var player := str(ctx.get("player", ""))
	var ctx_phase := str(ctx.get("current_phase", ""))

	if mover_card != null and player != "" and active_tactics.has(player):
		for t in active_tactics[player]:
			if typeof(t) != TYPE_DICTIONARY:
				continue
			var eff_t: Dictionary = t.get("effect", {})
			if eff_t.is_empty():
				continue
			if str(eff_t.get("stat", "")) != "move_range":
				continue

			# phase de jeu de la tactique
			var played_phase := str(t.get("_played_phase", ""))

			# si la carte dit "je m'applique en attack" mais qu'elle a été jouée en defense → ignorer
			var required_phase := str(eff_t.get("apply_on_phase", ""))
			if required_phase != "" and played_phase != "" and required_phase != played_phase:
				continue

			# filtrage classe
			var gm = ctx.get("game_manager", null)
			var class_targets: Array = t.get("class_targets", [])
			var matches := _unit_matches_tactic_classes(mover_card, gm, class_targets)
			if not matches:
				continue

			result["extra_move_range"] = int(eff_t.get("delta", 0))

	return result




# ctx : { board, attacker, target, attack_data, base_damage, game_manager }
static func on_attack_compute(ctx: Dictionary) -> Dictionary:
	var damage: int = int(ctx.get("base_damage", 0))

	# 1) effets de commandants
	for eff in effects_by_hook["on_attack_compute"]:
		var local_ctx := ctx.duplicate()
		local_ctx["_current_effect"] = eff
		var ok := _evaluate_effect_for_hook(eff, local_ctx, "on_attack_compute")
		if not ok.get("applies", false):
			continue
		for a in eff.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if a.has("modify_damage_add"):
				damage += int(a["modify_damage_add"])

	# 2) tactiques offensives
	var attacker_card = ctx.get("attacker", null)
	var gm = ctx.get("game_manager", null)

	if attacker_card != null and gm != null:
		var player: String = attacker_card.player_color
		if active_tactics.has(player):
			var to_remove: Array = []
			for t in active_tactics[player]:
				if typeof(t) != TYPE_DICTIONARY:
					continue
				var eff_t: Dictionary = t.get("effect", {})
				if eff_t.is_empty():
					continue
				if str(eff_t.get("stat", "")) != "attack":
					continue

				# phase où la tactique a été jouée
				var played_phase := str(t.get("_played_phase", ""))
				# phase demandée par la tactique (dans le JSON)
				var required_phase := str(eff_t.get("apply_on_phase", ""))
				if required_phase != "" and played_phase != "" and required_phase != played_phase:
					continue

				var class_targets: Array = t.get("class_targets", [])
				var matches := _unit_matches_tactic_classes(attacker_card, gm, class_targets)
				if not matches:
					continue

				damage += int(eff_t.get("delta", 0))

				# consommation
				var consumption := str(eff_t.get("consumption", ""))
				if consumption == "per_unit_next_attack":
					to_remove.append(t)

			for rem in to_remove:
				active_tactics[player].erase(rem)

	return {"damage": damage}




# ctx : { board, target, incoming_damage, game_manager }
static func on_damage_before(ctx: Dictionary) -> Dictionary:
	var dmg: int = int(ctx.get("incoming_damage", 0))

	# 1) effets de commandants
	for eff in effects_by_hook["on_damage_before"]:
		var local_ctx := ctx.duplicate()
		local_ctx["_current_effect"] = eff
		var ok := _evaluate_effect_for_hook(eff, local_ctx, "on_damage_before")
		if not ok.get("applies", false):
			continue
		for a in eff.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if a.has("modify_incoming_damage_mult"):
				dmg = int(floor(dmg * float(a["modify_incoming_damage_mult"])))
				if dmg < 0: dmg = 0
			elif a.has("modify_damage_add"):
				dmg += int(a["modify_damage_add"])

	# 2) tactiques défensives
	var target_card = ctx.get("target", null)
	var gm = ctx.get("game_manager", null)

	if target_card != null and gm != null:
		var player: String = target_card.player_color
		if active_tactics.has(player):
			var to_remove: Array = []
			for t in active_tactics[player]:
				if typeof(t) != TYPE_DICTIONARY:
					continue
				var eff_t: Dictionary = t.get("effect", {})

				if eff_t.is_empty():
					continue
				if str(eff_t.get("stat", "")) != "defense":
					continue

				var played_phase := str(t.get("_played_phase", ""))
				var required_phase := str(eff_t.get("apply_on_phase", ""))
				if required_phase != "" and played_phase != "" and required_phase != played_phase:
					continue

				var class_targets: Array = t.get("class_targets", [])
				var matches := _unit_matches_tactic_classes(target_card, gm, class_targets)
				if not matches:
					continue

				dmg -= int(eff_t.get("delta", 0))
				if dmg < 0:
					dmg = 0

				var consumption := str(eff_t.get("consumption", ""))
				if consumption == "per_unit_next_attack":
					to_remove.append(t)

			for rem in to_remove:
				active_tactics[player].erase(rem)

	return {"damage": dmg}






# ------------------------------------------------------------------------------
# ÉVALUATION D’UN EFFET POUR UN HOOK
# ------------------------------------------------------------------------------

static func _evaluate_effect_for_hook(eff: Dictionary, ctx: Dictionary, hook: String) -> Dictionary:
	# 1) Scope
	var scope: Dictionary = eff.get("scope", {}) as Dictionary
	var who: String = str(scope.get("who", ""))

	var ent: Dictionary = _resolve_scope_entity(who, ctx, hook)
	if ent.is_empty():
		return {"applies": false}

	# 2) Filtres de scope
	var filter: Dictionary = scope.get("filter", {}) as Dictionary
	var sc_ok: bool = _evaluate_scope_filters(filter, ent, ctx)
	if not sc_ok:
		return {"applies": false}

	# 3) Conditions
	var conds: Array = eff.get("conditions", [])
	var all_ok: bool = _evaluate_conditions(conds, ent, ctx)
	if not all_ok:
		return {"applies": false}

	return {"applies": true, "entity": ent}

# ------------------------------------------------------------------------------
# SCOPE / ENTITÉS
# ------------------------------------------------------------------------------

# Retour :
#   { "owner": "RED"/"BLUE", "cell": Vector2i, "card": StrategosCard }
static func _resolve_scope_entity(who: String, ctx: Dictionary, hook: String) -> Dictionary:
	var entity: Dictionary = {"owner": "", "cell": Vector2i(-999, -999), "card": null}

	if who == "attacker":
		if not ctx.has("attacker"):
			return {}
		var attacker = ctx["attacker"]
		if attacker == null:
			return {}
		entity["owner"] = attacker.player_color
		entity["cell"] = attacker.cell
		entity["card"] = attacker
		return entity

	if who == "target":
		if not ctx.has("target"):
			return {}
		var target = ctx["target"]
		if target == null:
			return {}
		entity["owner"] = target.player_color
		entity["cell"] = target.cell
		entity["card"] = target
		return entity

	if who == "mover":
		if not ctx.has("mover_card"):
			return {}
		var mover = ctx["mover_card"]
		if mover == null:
			return {}
		entity["owner"] = mover.player_color
		if ctx.has("from"):
			entity["cell"] = ctx["from"]
		else:
			entity["cell"] = mover.cell
		entity["card"] = mover
		return entity

	return {}

# ------------------------------------------------------------------------------
# FILTRES DE SCOPE (rapides)
# ------------------------------------------------------------------------------

static func _evaluate_scope_filters(filter: Dictionary, ent: Dictionary, ctx: Dictionary) -> bool:
	# Si pas de filtre, c'est ok
	if filter.is_empty():
		return true

	# Board requis
	var board = ctx.get("board", null)
	if board == null:
		return false

	# Vérifs de base sur l'entité (owner/cell)
	if not ent.has("owner"):
		return false
	if not ent.has("cell"):
		return false

	# -------- unit_type_is --------
	if filter.has("unit_type_is"):
		var want: String = str(filter["unit_type_is"])
		var t: String = _unit_type_at(board, ent["owner"], ent["cell"], ent.get("card", null))
		if t != want:
			return false

	# -------- same_row_as_commander --------
	if filter.has("same_row_as_commander"):
		var flag_val = filter["same_row_as_commander"]
		var flag := false
		if typeof(flag_val) == TYPE_BOOL:
			flag = bool(flag_val)
		elif typeof(flag_val) == TYPE_INT:
			flag = int(flag_val) != 0
		elif typeof(flag_val) == TYPE_FLOAT:
			flag = float(flag_val) != 0.0

		# On récupère l'ID du commandant à partir de l'effet courant (tagué dans load_definitions)
		var eff_commander_id := ""
		if ctx.has("_current_effect"):
			var eff = ctx["_current_effect"]
			if typeof(eff) == TYPE_DICTIONARY and eff.has("_cid"):
				eff_commander_id = str(eff["_cid"])

		# Si on n'a pas d'ID, par sécurité on considère que le filtre échoue
		if eff_commander_id == "":
			return false

		# Lignes pour CE commandant précis
		var rows: Array = _rows_for_commander_id(board, ent["owner"], eff_commander_id)
		var on_row := rows.has(ent["cell"].y)

		# Ne pas appliquer sur la pièce commandant elle-même
		var is_self_commander := _is_commander_at(board, ent["owner"], ent["cell"])
		if is_self_commander:
			return false

		if flag:
			if not on_row:
				return false
		else:
			if on_row:
				return false

	# -------- slot_active --------
	if filter.has("slot_active"):
		var slot: String = str(filter["slot_active"])
		if slot == "general":
			# On vérifie la présence du commandant correspondant à l'effet courant
			var eff_commander_id2 := ""
			if ctx.has("_current_effect"):
				var eff2 = ctx["_current_effect"]
				if typeof(eff2) == TYPE_DICTIONARY and eff2.has("_cid"):
					eff_commander_id2 = str(eff2["_cid"])

			if eff_commander_id2 == "":
				return false

			var has_this := _has_commander_for_player_id(board, ent["owner"], eff_commander_id2)
			if not has_this:
				return false

	# Si tous les filtres passés n'ont pas échoué, c'est bon
	return true


# ------------------------------------------------------------------------------
# CONDITIONS (dynamiques)
# ------------------------------------------------------------------------------

static func _evaluate_conditions(conds: Array, ent: Dictionary, ctx: Dictionary) -> bool:
	for c in conds:
		if typeof(c) != TYPE_DICTIONARY:
			continue

		# ally_is_adjacent
		if c.has("ally_is_adjacent"):
			var params: Dictionary = c["ally_is_adjacent"] as Dictionary
			var unit_type: String = str(params.get("unit_type", ""))
			var pattern: String = str(params.get("pattern", "orthogonal"))
			var ok_adj: bool = _has_adjacent_ally_of_type(ctx.get("board", null), ent["owner"], ent["cell"], unit_type, pattern)
			if not ok_adj:
				return false

		# range_equals
		if c.has("range_equals"):
			if not ctx.has("attack_data"):
				return false
			var ad: Dictionary = ctx["attack_data"] as Dictionary
			var expected: int = int(c["range_equals"])
			var rng: int = int(ad.get("range", 1))
			if rng != expected:
				return false

		# move_is_backward_for_owner
		if c.has("move_is_backward_for_owner"):
			if not ctx.has("from") or not ctx.has("to"):
				return false
			var from_pos: Vector2i = ctx["from"]
			var to_pos: Vector2i = ctx["to"]
			var backward: bool = _is_backward_move_for_player(ent["owner"], from_pos, to_pos)

			var need_backward_val = c["move_is_backward_for_owner"]
			var must_be_backward: bool = false
			if typeof(need_backward_val) == TYPE_BOOL:
				must_be_backward = bool(need_backward_val)
			elif typeof(need_backward_val) == TYPE_INT:
				must_be_backward = int(need_backward_val) != 0
			elif typeof(need_backward_val) == TYPE_FLOAT:
				must_be_backward = float(need_backward_val) != 0.0

			if must_be_backward:
				if not backward:
					return false
			else:
				if backward:
					return false

		# unit_type_is (condition directe)
		if c.has("unit_type_is"):
			var want2: String = str(c["unit_type_is"])
			var t2: String = _unit_type_at(ctx.get("board", null), ent["owner"], ent["cell"], ent["card"])
			if t2 != want2:
				return false

		# slot_active (condition directe)
		if c.has("slot_active"):
			var slot2: String = str(c["slot_active"])
			if slot2 == "general":
				var has_gen2: bool = _has_general_for_player(ctx.get("board", null), ent["owner"])
				if not has_gen2:
					return false

	return true

# ------------------------------------------------------------------------------
# UTILITAIRES "Board" / unités
# ------------------------------------------------------------------------------


static func _units_dict_for_owner(board, owner: String) -> Dictionary:
	if owner == "RED":
		return board.red_units
	return board.blue_units

static func _unit_type_at(board, owner: String, cell: Vector2i, fallback_card) -> String:
	var dict: Dictionary = _units_dict_for_owner(board, owner)
	if dict.has(cell):
		var raw = dict[cell]
		if typeof(raw) == TYPE_DICTIONARY and raw.has("type"):
			return str(raw["type"])
		if typeof(raw) == TYPE_STRING:
			return str(raw)
	# fallback via carte UI si besoin
	if fallback_card != null:
		if fallback_card.has_meta("unit_type"):
			return str(fallback_card.get_meta("unit_type"))
	return ""

static func _get_commander_rows_for_player(board, player: String) -> Array:
	var rows: Array = []
	var dict: Dictionary = _units_dict_for_owner(board, player)
	for pos in dict.keys():
		# zone commandant = x == -1
		if pos.x != -1:
			continue
		var data = dict[pos]
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if not data.has("is_commander"):
			continue
		var is_cmd: bool = bool(data["is_commander"])
		if not is_cmd:
			continue
		if not rows.has(pos.y):
			rows.append(pos.y)
	return rows

static func _has_general_for_player(board, player: String) -> bool:
	var dict: Dictionary = _units_dict_for_owner(board, player)
	for pos in dict.keys():
		if pos.x != -1:
			continue
		var data = dict[pos]
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if not data.has("is_commander"):
			continue
		var is_cmd: bool = bool(data["is_commander"])
		if not is_cmd:
			continue
		var role: String = str(data.get("role", ""))
		if role == "general":
			return true
	return false

static func _has_adjacent_ally_of_type(board, owner: String, cell: Vector2i, unit_type: String, pattern: String) -> bool:
	if board == null:
		return false
	var dict: Dictionary = _units_dict_for_owner(board, owner)
	var dirs: Array = []
	if pattern == "orthogonal":
		dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	else:
		# diagonales possibles plus tard si nécessaire
		dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	for d in dirs:
		var p: Vector2i = cell + d
		if dict.has(p):
			var raw = dict[p]
			var t: String = ""
			if typeof(raw) == TYPE_DICTIONARY and raw.has("type"):
				t = str(raw["type"])
			elif typeof(raw) == TYPE_STRING:
				t = str(raw)
			if t == unit_type:
				return true
	return false

static func _is_backward_move_for_player(player: String, from_pos: Vector2i, to_pos: Vector2i) -> bool:
	# RED avance vers le bas (y croissant) -> reculer = to.y < from.y
	# BLUE avance vers le haut  (y décroissant) -> reculer = to.y > from.y
	if player == "RED":
		return to_pos.y < from_pos.y
	else:
		return to_pos.y > from_pos.y

static func _is_commander_at(board, owner: String, cell: Vector2i) -> bool:
	var dict: Dictionary = _units_dict_for_owner(board, owner)
	if dict.has(cell):
		var raw = dict[cell]
		if typeof(raw) == TYPE_DICTIONARY and raw.has("is_commander"):
			var ic: bool = bool(raw["is_commander"])
			if ic:
				return true
	return false

static func _rows_for_commander_id(board, player: String, commander_id: String) -> Array:
	var rows: Array = []
	var dict: Dictionary = _units_dict_for_owner(board, player)
	for pos in dict.keys():
		if pos.x != -1:
			continue
		var raw = dict[pos]
		var matches := false
		if typeof(raw) == TYPE_STRING:
			# format simple: raw = "leon_sparta"
			if commander_id != "" and str(raw) == commander_id:
				matches = true
		elif typeof(raw) == TYPE_DICTIONARY:
			if raw.has("commander_id"):
				if commander_id != "" and str(raw["commander_id"]) == commander_id:
					matches = true
			elif raw.has("is_commander"):
				# compat si ancien format sans id (au pire on ne matchera pas)
				matches = false
		if matches and not rows.has(pos.y):
			rows.append(pos.y)
	return rows

static func _has_commander_for_player_id(board, player: String, commander_id: String) -> bool:
	var dict: Dictionary = _units_dict_for_owner(board, player)
	for pos in dict.keys():
		if pos.x != -1:
			continue
		var raw = dict[pos]
		if typeof(raw) == TYPE_STRING:
			if commander_id != "" and str(raw) == commander_id:
				return true
		elif typeof(raw) == TYPE_DICTIONARY:

			if raw.has("commander_id"):
				if commander_id != "" and str(raw["commander_id"]) == commander_id:
					return true
			elif raw.has("is_commander"):
				# ancien format sans id → on ne le compte pas pour un id précis
				pass
	return false
	
# ------------------------------------------------------------------------------
# UTILITAIRES "Tactiques"
# ------------------------------------------------------------------------------

static func _unit_matches_tactic_classes(unit_card, game_manager, class_targets: Array) -> bool:
	if unit_card == null:
		return false
	if game_manager == null:
		return false
	if class_targets.is_empty():
		return false

	var unit_type: String = str(unit_card.get_meta("unit_type", ""))
	if unit_type == "":
		return false

	if not game_manager.units_data.has(unit_type):
		return false

	var unit_info: Dictionary = game_manager.units_data[unit_type]
	if not unit_info.has("class"):
		return false

	var unit_class: String = str(unit_info["class"])

	for c in class_targets:
		if str(c) == unit_class:
			return true

	return false

static func _tactic_allows_phase(tactic_data: Dictionary, current_phase: String) -> bool:
	if not tactic_data.has("effect"):
		return true
	var eff: Dictionary = tactic_data["effect"]
	var need := str(eff.get("apply_on_phase", ""))
	if need == "":
		return true
	return need == current_phase

# ------------------------------------------------------------------
# Helpers pour le POPUP : récupérer les tactiques applicables
# ------------------------------------------------------------------

static func get_attack_tactics_for_attacker(ctx: Dictionary) -> Array:
	var out: Array = []

	if not ctx.has("attacker"):
		return out
	var attacker = ctx["attacker"]
	if attacker == null:
		return out

	var gm = ctx.get("game_manager", null)
	if gm == null:
		return out

	var player: String = attacker.player_color
	if not active_tactics.has(player):
		return out

	for t in active_tactics[player]:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if not t.has("effect"):
			continue

		var eff_t: Dictionary = t["effect"]
		var stat := str(eff_t.get("stat", ""))
		if stat != "attack":
			continue

		# ⚠️ on NE filtre PLUS sur apply_on_phase ici,
		# parce que le popup peut être appelé en phase "defense"
		# alors que la tactique est marquée "attack".

		# classes ciblées
		var class_targets: Array = []
		if t.has("class_targets"):
			class_targets = t["class_targets"]
		var matches := _unit_matches_tactic_classes(attacker, gm, class_targets)
		if not matches:
			continue

		out.append({
			"title": t.get("title", "Tactique"),
			"delta": int(eff_t.get("delta", 0))
		})

	return out




static func get_defense_tactics_for_target(ctx: Dictionary) -> Array:
	# ctx attendu :
	# {
	#   "target": StrategosCard,
	#   "game_manager": GameManager,
	#   "current_phase": "attack"/"defense"
	# }
	var out: Array = []

	if not ctx.has("target"):
		return out
	if not ctx.has("game_manager"):
		return out

	var target = ctx["target"]
	var gm = ctx["game_manager"]
	var phase: String = str(ctx.get("current_phase", ""))

	var player: String = target.player_color
	if not active_tactics.has(player):
		return out

	for t in active_tactics[player]:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if not t.has("effect"):
			continue

		var eff_t: Dictionary = t["effect"]
		var stat: String = str(eff_t.get("stat", ""))
		if stat != "defense":
			continue

		# phase autorisée ?
		var allowed_phase: String = str(eff_t.get("apply_on_phase", ""))
		if allowed_phase != "" and phase != "" and phase != allowed_phase:
			continue

		# classe cohérente ?
		var class_targets: Array = []
		if t.has("class_targets"):
			class_targets = t["class_targets"]

		var matches := _unit_matches_tactic_classes(target, gm, class_targets)
		if not matches:
			continue

		out.append({
			"title": t.get("title", "Tactique"),
			"delta": eff_t.get("delta", 0)
		})

	return out
