extends Node

const COMMAND_ZONE_WIDTH := 1
const GRID_WIDTH := 6
const GRID_HEIGHT := 8

var CELL_SIZE = Vector2(168 * 0.85, 101 * 0.85)

var red_commanders := {}
var blue_commanders := {}

var red_units: Dictionary = {}   
var blue_units: Dictionary = {}  


func apply_unit_positions(player: String, unit_list: Array):
	# Nettoyer le camp
	if player == "RED":
		red_units.clear()
	else:
		blue_units.clear()

	for unit_data in unit_list:
		var pos: Vector2i = unit_data["pos"]
		var data = unit_data["data"]  # ✅ maintenant c’est déjà un dict complet !

		if player == "RED":
			red_units[pos] = data
		else:
			blue_units[pos] = data




func init_units_for_player(player: String, unit_list: Array):
	# Nettoyer
	if player == "RED":
		red_units.clear()
	else:
		blue_units.clear()

	for unit_data in unit_list:
		var pos: Vector2i = unit_data["pos"]
		var data: Dictionary = unit_data["data"] # ✅ déjà complet
		if player == "RED":
			red_units[pos] = data
		else:
			blue_units[pos] = data




func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= -COMMAND_ZONE_WIDTH and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT

func is_empty(pos: Vector2i) -> bool:
	return not red_units.has(pos) and not blue_units.has(pos)

func get_units(player: String) -> Array[Vector2i]:
	var units_dict: Dictionary
	if player == "RED":
		units_dict = red_units
	else:
		units_dict = blue_units

	var keys_array: Array = units_dict.keys()
	var result: Array[Vector2i] = []
	for k in keys_array:
		result.append(k)  # chaque clé est déjà un Vector2i
	return result




func add_unit(player: String, pos: Vector2i, unit_data):
	if not is_in_bounds(pos):
		return
	if not is_empty(pos):
		return

	# ✅ On stocke directement ce qu’on reçoit (string ou dict complet)
	if player == "RED":
		red_units[pos] = unit_data
	else:
		blue_units[pos] = unit_data







func remove_unit(player: String, pos: Vector2i):
	if player == "RED":
		if red_units.has(pos):
			red_units.erase(pos)
	else:
		if blue_units.has(pos):
			blue_units.erase(pos)


func move_unit(player: String, from_pos: Vector2i, to_pos: Vector2i):
	if not is_in_bounds(to_pos):
		return
	if not is_empty(to_pos):
		return

	var units_dict: Dictionary
	if player == "RED":
		units_dict = red_units
	else:
		units_dict = blue_units

	if units_dict.has(from_pos):
		# ✅ Récupère le dictionnaire complet (type + hp + move_range)
		var unit_data = units_dict[from_pos]
		units_dict.erase(from_pos)        
		units_dict[to_pos] = unit_data    




func is_move_valid(player: String, origin: Vector2i, target: Vector2i, turn_start_positions: Dictionary) -> bool:
	var diff = target - origin
	
	if not is_in_bounds(target):
		return false
		
	if not is_empty(target):
		return false
		
	if abs(diff.x) > 1 or abs(diff.y) > 1:
		return false
		
	if abs(diff.x) == 1 and abs(diff.y) == 1:
		return false
		
	if diff.y == 0:
		for kv in turn_start_positions:
			if turn_start_positions[kv] == target and kv == origin:
				return false
				
	return true

func get_front_line(player: String) -> int:
	var units = get_units(player)
	if units.is_empty():
		return -1  # Aucun front, pas de ligne

	var y_values = units.map(func(u): return u.y)

	if player == "RED":
		# Les rouges avancent vers le bas -> ligne la plus avancée = plus grand Y
		return y_values.max()
	else:
		# Les bleus avancent vers le haut -> ligne la plus avancée = plus petit Y
		return y_values.min()

