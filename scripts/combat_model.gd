extends RefCounted
## Pure 60 Hz simulation. Rendering, pause and real-time hitstop are external.
const Geometry = preload("res://scripts/combat_geometry.gd")
const Patterns = preload("res://scripts/boss_patterns.gd")
const DATA_PATH = "res://data/combat.json"
const WEAPONS_PATH = "res://data/weapons.json"
const OATHS_PATH = "res://data/oaths.json"

var data: Dictionary
var tick = 0
var mode = "prototype"
var phase_id = 1
var phase_hp_max = 1000.0
var highest_phase_reached = 1
var transition_ticks_remaining = 0
var frost_guard_until = -1
var element_id = ""
var element_charges = 0
var fire_charges: int:
	get:
		return element_charges if element_id == "fire" else 0
	set(value):
		if value > 0:
			element_id = "fire"
			element_charges = value
		elif element_id == "fire":
			element_id = ""
			element_charges = 0
var seed_value = 1
var player_pos = Vector2(320, 280)
var boss_pos = Vector2(320, 135)
var player_hp = 100.0
var boss_hp = 1000.0
var player_facing = Vector2.UP
var player_state = "idle"
var state_age = 0
var stacks = 0
var result = ""
var cause = ""
var hitstop_ms = 0.0
var boss_pattern = "claw"
var boss_state = "approach"
var boss_age = 0
var boss_facing = Vector2.DOWN
var boss_enabled = true
var attack: Dictionary = {}
var pickups: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var events: Array[Dictionary] = []
var pending_input = ""
var next_dodge_tick = -42
var player_invulnerable_until = -1
var fire_expires_tick = -1
var fire_next_tick = -1
var total_attacks = 0
var damage_dealt = 0.0
var damage_received = 0.0
var collected_fire = 0
var pattern_history: Array[String] = []
var phase_history: Array[int] = []
var collected_elements: Dictionary = {}
var pattern_runner = Patterns.new()
var safety_error = ""
var weapon_id = "W01"
var oaths: Array[String] = []
var altars: Array[Dictionary] = []
var oath_candidates: Array[String] = []
var selection_pending = false

var _state_started = 0
var _dodge_direction = Vector2.UP
var _pending_until = -1
var _pending_key = ""
var _frozen_intent = ""
var _move = Vector2.ZERO
var _action_id = 0
var _pickup_id = 0
var _pattern_id = 0
var _pattern_started = 0
var _approach_started = 0
var _pattern_origin = Vector2.ZERO
var _recover_notified = false
var _boss_hit_events: Dictionary = {}
var _pattern_bag: Array[String] = []
var _last_pattern = ""
var _first_pattern = true
var _drop_crossed: Array[int] = []
var _drop_queue: Array[int] = []
var _injected_damage: Array[Dictionary] = []
var _boss_rng = RandomNumberGenerator.new()
var _element_rng = RandomNumberGenerator.new()
var _layout_rng = RandomNumberGenerator.new()
var _oath_rng = RandomNumberGenerator.new()
var _cosmetic_rng = RandomNumberGenerator.new()
var _p5_elements: Array[String] = []
var _transition_from_player = Vector2.ZERO
var _transition_from_boss = Vector2.ZERO
var _transition_target_phase = 1
var _director_wait_until = -1
var _director_repositioned = false
var _deferred_pattern = ""
var _altar_input_this_tick = false
var _altar_candidate = -1
var _hit_this_tick = false

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert(not data.is_empty(), "Missing combat data")
	data["weapons"] = JSON.parse_string(FileAccess.get_file_as_string(WEAPONS_PATH))
	data["oaths"] = JSON.parse_string(FileAccess.get_file_as_string(OATHS_PATH))
	# Kept as the W01 data alias for older callers; combat reads the selected weapon.
	data["sword"] = data.weapons.W01
	for phase in data.phases:
		for id in phase.patterns:
			data.patterns[id] = pattern_runner.get_definition(id)
	reset()

func reset(run_seed: int = 1, run_mode: String = "prototype", start_phase: int = 1, starting_weapon: String = "W01") -> void:
	assert(run_mode in ["prototype", "official", "practice"], "Unknown run mode")
	seed_value = run_seed
	_boss_rng.seed = run_seed
	_element_rng.seed = run_seed ^ 0x6E624EB7
	_layout_rng.seed = run_seed ^ 0x2A71C5
	_oath_rng.seed = run_seed ^ 0x0A7A51
	_cosmetic_rng.seed = run_seed ^ 0xC05E71C
	weapon_id = starting_weapon if data.weapons.has(starting_weapon) else "W01"
	oaths.clear()
	oath_candidates.clear()
	selection_pending = false
	_altar_candidate = -1
	_hit_this_tick = false
	_initialize_altars()
	tick = 0
	mode = run_mode
	phase_id = 1 if mode == "prototype" else clampi(start_phase, 1, 5)
	phase_hp_max = float(data.phases[phase_id - 1].hp)
	highest_phase_reached = phase_id if mode == "official" else 1
	transition_ticks_remaining = 0
	frost_guard_until = -1
	element_id = ""
	element_charges = 0
	safety_error = ""
	player_pos = Vector2(320, 280)
	boss_pos = Vector2(320, 135)
	player_hp = float(data.player.hp)
	boss_hp = phase_hp_max
	player_facing = Vector2.UP
	player_state = "idle"
	state_age = 0
	_state_started = 0
	stacks = 0
	fire_charges = 0
	result = ""
	cause = ""
	hitstop_ms = 0.0
	next_dodge_tick = -42
	player_invulnerable_until = -1
	fire_expires_tick = -1
	fire_next_tick = -1
	total_attacks = 0
	damage_dealt = 0.0
	damage_received = 0.0
	collected_fire = 0
	boss_enabled = true
	boss_pattern = str(data.phases[phase_id - 1].patterns[0])
	boss_state = "approach"
	boss_age = 0
	boss_facing = Vector2.DOWN
	_approach_started = 0
	_pattern_started = 0
	_pattern_id = 0
	_action_id = 0
	_pickup_id = 0
	_first_pattern = true
	_last_pattern = ""
	_director_wait_until = -1
	_director_repositioned = false
	_deferred_pattern = ""
	attack.clear()
	pickups.clear()
	hazards.clear()
	events.clear()
	pattern_history.clear()
	phase_history.clear()
	phase_history.append(phase_id)
	collected_elements.clear()
	_pattern_bag.clear()
	_drop_queue.clear()
	_drop_crossed.clear()
	_injected_damage.clear()
	_boss_hit_events.clear()
	_p5_elements = ["fire", "frost", "lightning", "void"]
	for i in range(_p5_elements.size() - 1, 0, -1):
		var j = _element_rng.randi_range(0, i)
		var swap = _p5_elements[i]
		_p5_elements[i] = _p5_elements[j]
		_p5_elements[j] = swap
	clear_input()

func weapon_definition() -> Dictionary:
	return data.weapons[weapon_id]

func stack_threshold() -> int:
	var value = int(weapon_definition().stack_threshold)
	for id in oaths:
		value += int(data.oaths[id].get("stack_delta", 0))
	return maxi(3, value)

func player_max_hp() -> float:
	var value = float(data.player.hp)
	for id in oaths:
		value += float(data.oaths[id].get("hp_delta", 0))
	return value

func move_speed() -> float:
	var value = float(data.player.speed)
	for id in oaths:
		value *= float(data.oaths[id].get("speed_multiplier", 1.0))
	return value

func dodge_distance() -> float:
	var value = float(data.player.dodge_distance)
	for id in oaths:
		value *= float(data.oaths[id].get("dodge_multiplier", 1.0))
	return value

func element_max_charges(id: String = "") -> int:
	var selected = element_id if id == "" else id
	if not data.elements.has(selected):
		return 0
	var value = int(data.elements[selected].charges)
	for oath in oaths:
		value += int(data.oaths[oath].get("charge_delta", 0))
	return value

func ground_lifetime() -> int:
	var value = int(data.fire.ground_ticks)
	for id in oaths:
		value += int(data.oaths[id].get("ground_delta", 0))
	return value

func phase_heal() -> float:
	var value = float(data.transition.heal)
	for id in oaths:
		value = maxf(value, float(data.oaths[id].get("phase_heal", value)))
	return value

func stream_states() -> Dictionary:
	return {"seed":seed_value, "layout":_layout_rng.state, "boss":_boss_rng.state, "oath":_oath_rng.state, "element":_element_rng.state, "cosmetic":_cosmetic_rng.state}

func cosmetic_random() -> float:
	return _cosmetic_rng.randf()

func _initialize_altars() -> void:
	altars.clear()
	var available: Array[String] = []
	for id in data.weapons:
		if id != weapon_id:
			available.append(str(id))
	_shuffle_ids(available, _layout_rng)
	var positions = [Vector2(155,110), Vector2(485,110), Vector2(155,258), Vector2(485,258)]
	for index in range(4):
		altars.append({"id":index + 1, "pos":positions[index], "weapon":available[index], "progress":0, "armed":true})

func _shuffle_ids(ids: Array[String], rng: RandomNumberGenerator) -> void:
	for index in range(ids.size() - 1, 0, -1):
		var other = rng.randi_range(0, index)
		var previous = ids[index]
		ids[index] = ids[other]
		ids[other] = previous

func legal_oaths() -> Array[String]:
	var available: Array[String] = []
	if oaths.size() >= 3:
		return available
	for id in data.oaths:
		if oaths.has(str(id)):
			continue
		var legal = true
		for held in oaths:
			if data.oaths[id].excludes.has(held) or data.oaths[held].excludes.has(id):
				legal = false
		if legal:
			available.append(str(id))
	return available

func _begin_oath_selection() -> void:
	oath_candidates = legal_oaths()
	_shuffle_ids(oath_candidates, _oath_rng)
	oath_candidates.resize(mini(3, oath_candidates.size()))
	selection_pending = true
	clear_input()
	events.append({"type":"oath_selection", "candidates":oath_candidates.duplicate()})

func choose_oath(id: String = "") -> bool:
	if not selection_pending or (id != "" and not oath_candidates.has(id)):
		return false
	if id != "":
		oaths.append(id)
		player_hp = minf(player_max_hp(), player_hp + float(data.oaths[id].get("heal_on_select", 0)))
		stacks = mini(stacks, stack_threshold())
	selection_pending = false
	oath_candidates.clear()
	clear_input()
	events.clear()
	events.append({"type":"oath_selected", "id":id})
	return true

func phase_name() -> String:
	return str(data.phases[phase_id - 1].name)

func pattern_name() -> String:
	return str(data.patterns[boss_pattern].get("name", boss_pattern))

func total_boss_hp() -> float:
	var remaining = boss_hp
	if mode == "official":
		for index in range(phase_id, data.phases.size()):
			remaining += float(data.phases[index].hp)
	return remaining

func total_boss_max() -> float:
	if mode != "official":
		return phase_hp_max
	var total = 0.0
	for phase in data.phases:
		total += float(phase.hp)
	return total

func clear_input() -> void:
	pending_input = ""
	_pending_until = -1
	_pending_key = ""
	_frozen_intent = ""

func next_attack_kind() -> String:
	var ready = stacks >= stack_threshold()
	if ready and element_charges > 0:
		return "resonance"
	if ready:
		return "signature"
	if element_charges > 0:
		return element_id
	return "basic"

func next_attack_key() -> String:
	return next_attack_kind() + ":" + (element_id if element_charges > 0 else "")

func is_player_invulnerable() -> bool:
	return tick < player_invulnerable_until or (player_state == "dodge" and state_age >= int(data.player.dodge_inv_start) and state_age <= int(data.player.dodge_inv_end))

func queue_frozen_input(command: Dictionary) -> void:
	if result != "" or transition_ticks_remaining > 0 or selection_pending:
		return
	if command.get("dodge", false):
		_frozen_intent = "dodge"
	elif command.get("attack", false) and _frozen_intent != "dodge":
		_frozen_intent = "attack"

func step(command: Dictionary = {}) -> void:
	if result != "" or selection_pending:
		return
	tick += 1
	events.clear()
	hitstop_ms = 0.0
	if transition_ticks_remaining > 0:
		_step_transition()
		return
	if safety_error != "":
		return
	_move = Vector2(command.get("move", Vector2.ZERO)).limit_length(1.0)
	_altar_input_this_tick = _move.length_squared() > 0.001 or bool(command.get("attack", false)) or bool(command.get("dodge", false)) or _frozen_intent != ""
	_hit_this_tick = false
	_update_player_state()
	if pending_input != "" and tick > _pending_until:
		_clear_pending()
	if _frozen_intent != "":
		_offer_input(_frozen_intent)
		_frozen_intent = ""
	if command.get("dodge", false):
		_offer_input("dodge")
	elif command.get("attack", false):
		_offer_input("attack")
	var dodged = false
	if pending_input == "dodge" and _ready_delay("dodge") == 0:
		_start_dodge()
		dodged = true
	_move_player()
	if boss_enabled:
		_update_boss()
		if result != "":
			return
	# A charging body's separation radius exceeds its attacking radius. Let the
	# swept strike resolve first, rather than pushing its victim harmlessly ahead.
	var charging = boss_pattern == "dash" and boss_state == "execute" and hazards.any(func(h): return h.phase == "active" and h.shape == "capsule")
	if player_state != "dodge" and not charging:
		_separate_bodies(false)
	var old_kind = next_attack_key()
	_update_pickups()
	_invalidate_changed_input(old_kind)
	if not dodged and pending_input == "attack" and _ready_delay("attack") == 0:
		if _pending_key == next_attack_key():
			_start_attack()
		else:
			_clear_pending()
	_resolve_damage()
	_update_altars()
	_check_result()
	if result != "" or transition_ticks_remaining > 0:
		return
	if boss_enabled:
		_finish_boss_tick()

func _clear_pending() -> void:
	pending_input = ""
	_pending_until = -1
	_pending_key = ""

func _ready_delay(kind: String) -> int:
	var delay = 0
	match player_state:
		"attack":
			if kind == "dodge":
				delay = maxi(0, int(attack.get("definition", weapon_definition()).dodge_cancel_tick) - state_age)
			else:
				delay = maxi(0, _attack_duration() - state_age)
		"dodge":
			delay = maxi(0, int(data.player.dodge_ticks) - state_age)
		"hurt":
			delay = maxi(0, int(data.player.hurt_ticks) - state_age)
	if kind == "dodge":
		delay = maxi(delay, next_dodge_tick - tick)
	return maxi(0, delay)

func _offer_input(kind: String) -> void:
	if _ready_delay(kind) > int(data.player.buffer_ticks):
		return
	if kind == "attack" and pending_input == "dodge":
		return
	pending_input = kind
	_pending_until = tick + int(data.player.buffer_ticks)
	_pending_key = next_attack_key()

func _update_player_state() -> void:
	state_age = tick - _state_started
	if player_state == "attack":
		attack["age"] = state_age
		if state_age >= _attack_duration():
			attack.clear()
			_set_player_state("idle")
	elif player_state == "dodge" and state_age >= int(data.player.dodge_ticks):
		_separate_bodies(true)
		_set_player_state("idle")
	elif player_state == "hurt" and state_age >= int(data.player.hurt_ticks):
		_set_player_state("idle")

func _set_player_state(value: String) -> void:
	player_state = value
	_state_started = tick
	state_age = 0

func _attack_duration() -> int:
	var definition: Dictionary = attack.get("definition", weapon_definition())
	return int(definition.startup_ticks) + int(definition.active_ticks) + int(definition.recovery_ticks)

func _start_dodge() -> void:
	_dodge_direction = _move.normalized() if _move.length_squared() > 0.01 else player_facing
	player_facing = _dodge_direction
	next_dodge_tick = tick + int(data.player.dodge_cooldown)
	attack.clear()
	_set_player_state("dodge")
	_clear_pending()
	events.append({"type": "dodge", "pos": player_pos})

func _move_player() -> void:
	if player_state == "dodge":
		player_pos += _dodge_direction * dodge_distance() / float(data.player.dodge_ticks)
	elif player_state == "idle" or player_state == "move":
		player_state = "move" if _move.length_squared() > 0.001 else "idle"
		if _move.length_squared() > 0.001:
			player_facing = _move.normalized()
		player_pos += _move * move_speed() / 60.0
	player_pos = clamp_position(player_pos, float(data.player.radius))

func clamp_position(point: Vector2, inset: float = 6.0) -> Vector2:
	return Geometry.clamp_arena(point, Vector2(320,184), Vector2(260,126), inset)

func _separate_bodies(after_dodge: bool) -> void:
	var separation = float(data.player.radius) + float(data.boss.body_radius) + 0.5
	if player_pos.distance_to(boss_pos) >= separation:
		return
	var direction = _dodge_direction if after_dodge else (player_pos - boss_pos).normalized()
	if direction.length_squared() < 0.01:
		direction = -boss_facing
	for degrees in [0, 45, -45, 90, -90, 135, -135, 180]:
		var candidate = boss_pos + direction.rotated(deg_to_rad(float(degrees))) * separation
		if Geometry.in_arena(candidate, Vector2(320,184), Vector2(260,126), float(data.player.radius)):
			player_pos = candidate
			return

func _start_attack() -> void:
	var kind = next_attack_kind()
	var used_element = element_id if element_charges > 0 else ""
	var element_data: Dictionary = data.elements.get(used_element, {})
	var definition = weapon_definition().duplicate(true)
	var special = kind == "signature" or kind == "resonance"
	var reach = float(definition.get("signature_reach", definition.reach) if special else definition.reach) + float(element_data.get("range_bonus", 0.0))
	var direction = player_facing
	var to_boss = boss_pos - player_pos
	# Aim uses the nearest point of the boss hurt disk, not its sprite center.
	if to_boss.length() - float(data.boss.hurt_radius) <= reach + 12.0 and absf(direction.angle_to(to_boss)) <= deg_to_rad(60.0):
		direction = direction.rotated(clampf(direction.angle_to(to_boss), -deg_to_rad(30.0), deg_to_rad(30.0)))
	var multiplier = 1.0
	if special:
		multiplier *= float(definition.signature_multiplier)
		stacks = 0
	if used_element != "":
		multiplier *= float(element_data.multiplier)
		element_charges -= 1
		if element_charges == 0:
			element_id = ""
	_action_id += 1
	total_attacks += 1
	# Static coefficients and move timing belong to the action snapshot. Only the
	# O03/O04 distance condition is evaluated at each actual hit below.
	multiplier *= _direct_multiplier(kind, used_element, oaths)
	attack = {"id": _action_id, "weapon":weapon_id, "definition":definition, "oaths":oaths.duplicate(), "kind": kind, "element": used_element, "age": 0, "facing": direction, "origin": player_pos, "reach": reach, "damage": float(definition.damage) * multiplier, "hit": false, "hit_events":{}, "stack_awarded":false, "effect_applied":false}
	player_facing = direction
	_set_player_state("attack")
	_clear_pending()
	events.append({"type": "attack", "weapon":weapon_id, "kind": kind, "element": used_element, "pos": player_pos})

func _direct_multiplier(kind: String, used_element: String, held: Array) -> float:
	var value = 1.0
	for id in held:
		var oath: Dictionary = data.oaths[id]
		value *= float(oath.get("direct_multiplier", 1.0))
		if kind == "basic":
			value *= float(oath.get("basic_multiplier", 1.0))
		if kind == "signature" or kind == "resonance":
			value *= float(oath.get("signature_multiplier", 1.0))
		if used_element != "":
			value *= float(oath.get("element_multiplier", 1.0))
	return value

func _distance_multiplier(held: Array) -> float:
	var value = 1.0
	var key = "near_multiplier" if player_pos.distance_to(boss_pos) <= 40.0 else "far_multiplier"
	for id in held:
		value *= float(data.oaths[id].get(key, 1.0))
	return value

func player_attack_shape() -> Dictionary:
	if attack.is_empty():
		return {}
	var special = attack.kind == "signature" or attack.kind == "resonance"
	var definition: Dictionary = attack.definition
	var shape_kind = str(definition.get("signature_shape", definition.shape) if special else definition.shape)
	# The held weapon follows the owner's footpoint if body separation moves
	# them; attack facing and all parameters remain the startup snapshot.
	if shape_kind == "line":
		return {"shape":"line", "origin":player_pos, "facing":attack.facing, "length":attack.reach, "width":float(definition.get("signature_width", definition.width) if special else definition.width)}
	if shape_kind == "disk":
		# Lightning extends the forward point by its usual range bonus. The
		# impact disk radius stays fixed, retaining the hammer's ground target.
		var bonus = float(attack.reach) - float(definition.reach)
		return {"shape":"disk", "origin":player_pos + Vector2(attack.facing) * (float(definition.signature_origin_offset) + bonus), "radius":float(definition.signature_radius)}
	return {"shape":"sector", "origin":player_pos, "facing":attack.facing, "radius":attack.reach, "inner_radius":float(definition.get("inner_radius", 0.0)), "arc_radians":deg_to_rad(float(definition.get("signature_arc_degrees", definition.arc_degrees) if special else definition.arc_degrees))}

func _invalidate_changed_input(old_kind: String) -> void:
	if old_kind != next_attack_key() and pending_input == "attack":
		_clear_pending()

func _resolve_damage() -> void:
	var old_kind = next_attack_key()
	var outgoing = 0.0
	var normal_hit = false
	var hit_element = ""
	var old_guard = tick < frost_guard_until
	if player_state == "attack" and not attack.is_empty():
		var definition: Dictionary = attack.definition
		var hit_windows: Array = definition.hit_windows
		for index in range(hit_windows.size()):
			var window: Array = hit_windows[index]
			if state_age < int(window[0]) or state_age >= int(window[1]) or attack.hit_events.has(index):
				continue
			# A chain's minimum footpoint distance remains for every transformed
			# attack, even when the large boss hurt disk reaches its inner arc.
			if player_pos.distance_to(boss_pos) < float(definition.get("min_target_distance", 0.0)):
				continue
			if Geometry.contains(player_attack_shape(), boss_pos, float(data.boss.hurt_radius)) and boss_hp > 0.0:
				attack.hit_events[index] = true
				attack["hit"] = true
				var direct = snappedf(float(attack.damage) / float(hit_windows.size()) * _distance_multiplier(attack.oaths), 0.001)
				outgoing += direct
				if attack.kind == "basic" and not attack.stack_awarded:
					normal_hit = true
					attack["stack_awarded"] = true
				if not attack.effect_applied:
					hit_element = str(attack.get("element", ""))
					attack["effect_applied"] = true
				events.append({"type":"boss_hit", "damage":direct, "kind":attack.kind, "weapon":attack.weapon, "hit_index":index, "action_id":attack.id, "pos":boss_pos})
				hitstop_ms = 33.0 if attack.kind == "basic" else 67.0
	if fire_next_tick >= 0 and tick >= fire_next_tick and tick <= fire_expires_tick:
		outgoing += float(data.fire.dot_damage)
		fire_next_tick += int(data.fire.dot_interval)
		events.append({"type": "burn", "damage": float(data.fire.dot_damage), "pos": boss_pos})
	var incoming: Array[Dictionary] = []
	if not is_player_invulnerable():
		for hazard in hazards:
			var key = str(_pattern_id) + ":" + str(hazard.get("event_id", "main"))
			if hazard.phase == "active" and not _boss_hit_events.has(key) and Geometry.contains(hazard, player_pos, float(data.player.radius)):
				incoming.append({"damage": float(hazard.get("damage", data.patterns[boss_pattern].get("damage", 0.0))), "cause": str(hazard.get("cause", pattern_name())), "event_key": key})
		for injected in _injected_damage:
			incoming.append(injected)
	_injected_damage.clear()
	if outgoing > 0.0:
		var actual = minf(boss_hp, outgoing)
		boss_hp = maxf(0.0, snappedf(boss_hp - outgoing, 0.001))
		damage_dealt += actual
		if normal_hit and actual > 0.0:
			stacks = mini(stacks + 1, stack_threshold())
		_queue_crossed_drops()
	if not incoming.is_empty():
		var greatest: Dictionary = incoming[0]
		for candidate in incoming:
			if float(candidate.damage) > float(greatest.damage):
				greatest = candidate
		var applied = float(greatest.damage) * (float(data.elements.frost.guard_multiplier) if old_guard else 1.0)
		for id in oaths:
			applied *= float(data.oaths[id].get("incoming_multiplier", 1.0))
		applied = snappedf(applied, 0.001)
		if old_guard:
			frost_guard_until = -1
		var received = minf(player_hp, applied)
		player_hp = maxf(0.0, snappedf(player_hp - applied, 0.001))
		damage_received += received
		_hit_this_tick = true
		cause = str(greatest.cause)
		player_invulnerable_until = tick + int(data.player.hurt_inv_ticks)
		if greatest.has("event_key"):
			_boss_hit_events[greatest.event_key] = true
		attack.clear()
		_set_player_state("hurt")
		events.append({"type": "player_hit", "damage": applied, "pos": player_pos, "cause": cause})
		hitstop_ms = maxf(hitstop_ms, 67.0)
	# New on-hit effects cannot reduce damage already batched in this tick.
	if hit_element == "fire":
		debug_apply_fire()
	elif hit_element == "frost":
		frost_guard_until = tick + int(data.elements.frost.guard_ticks)
	if fire_expires_tick >= 0 and tick >= fire_expires_tick:
		fire_expires_tick = -1
		fire_next_tick = -1
	_invalidate_changed_input(old_kind)

func _check_result() -> void:
	if mode == "practice" and boss_hp <= 0.0:
		result = "practice_complete"
	elif mode == "official" and phase_id == 5 and boss_hp <= 0.0:
		result = "victory"
	elif player_hp <= 0.0:
		result = "dead"
	elif boss_hp <= 0.0:
		if mode == "official":
			_begin_transition()
			return
		result = "prototype_complete"
	if result == "":
		return
	hazards.clear()
	pickups.clear()
	_drop_queue.clear()
	fire_expires_tick = -1
	fire_next_tick = -1
	attack.clear()
	clear_input()
	events.append({"type": "result", "result": result})

func _begin_transition() -> void:
	_transition_target_phase = phase_id + 1
	_transition_from_player = player_pos
	_transition_from_boss = boss_pos
	transition_ticks_remaining = int(data.transition.relocate_ticks) + int(data.transition.ready_ticks)
	player_hp = minf(player_max_hp(), player_hp + phase_heal())
	_clear_phase_effects()
	_set_player_state("transition")
	boss_state = "transition"
	next_dodge_tick = tick
	player_invulnerable_until = -1
	frost_guard_until = -1
	events.append({"type": "phase_transition", "from": phase_id, "to": _transition_target_phase})

func _clear_phase_effects() -> void:
	hazards.clear()
	pickups.clear()
	attack.clear()
	_drop_queue.clear()
	_drop_crossed.clear()
	_boss_hit_events.clear()
	_injected_damage.clear()
	fire_expires_tick = -1
	fire_next_tick = -1
	hitstop_ms = 0.0
	for altar in altars:
		altar.progress = 0
	clear_input()

func _step_transition() -> void:
	clear_input()
	_injected_damage.clear()
	transition_ticks_remaining -= 1
	var relocate = int(data.transition.relocate_ticks)
	var ready = int(data.transition.ready_ticks)
	var progress = clampf(float(relocate + ready - transition_ticks_remaining) / relocate, 0.0, 1.0)
	player_pos = _transition_from_player.lerp(Vector2(320,280), progress)
	boss_pos = _transition_from_boss.lerp(Vector2(320,135), progress)
	state_age += 1
	if transition_ticks_remaining == ready:
		phase_id = _transition_target_phase
		phase_hp_max = float(data.phases[phase_id - 1].hp)
		boss_hp = phase_hp_max
		highest_phase_reached = maxi(highest_phase_reached, phase_id)
		phase_history.append(phase_id)
		_pattern_bag.clear()
		_first_pattern = true
		_last_pattern = ""
		_director_wait_until = -1
		_director_repositioned = false
		_deferred_pattern = ""
		events.append({"type": "phase_reached", "phase": phase_id})
		if mode == "official" and phase_id <= 4:
			_begin_oath_selection()
	if transition_ticks_remaining == 0:
		_set_player_state("idle")
		player_facing = Vector2.UP
		boss_facing = Vector2.DOWN
		boss_state = "approach"
		boss_pattern = str(data.phases[phase_id - 1].patterns[0])
		_approach_started = tick
		boss_age = 0
		events.append({"type": "phase_started", "phase": phase_id})

func _update_boss() -> void:
	if boss_state == "approach":
		boss_age = tick - _approach_started
		# A roll may legally pass through the boss. Do not generate a ground
		# escape certificate from a transient body-overlap position.
		if player_state == "dodge":
			hazards.clear()
			return
		if _director_wait_until >= 0:
			if tick < _director_wait_until:
				boss_pos = clamp_position(boss_pos.move_toward(Vector2(320,184), float(data.boss.speed) / 60.0), float(data.boss.body_radius))
				hazards.clear()
				return
			_director_wait_until = -1
		var difference = player_pos - boss_pos
		if difference.length() > float(data.boss.approach_distance):
			var distance = minf(float(data.boss.speed) / 60.0, difference.length() - float(data.boss.approach_distance))
			boss_pos = clamp_position(boss_pos + difference.normalized() * distance, float(data.boss.body_radius))
		if difference.length() <= float(data.boss.approach_distance) + 0.01 or boss_age >= int(data.boss.approach_ticks):
			_start_next_pattern()
		else:
			hazards.clear()
			return
		if boss_state == "approach" or result != "":
			return
	boss_age = tick - _pattern_started
	var snapshot: Dictionary = pattern_runner.update(boss_age, player_pos)
	boss_pos = snapshot.boss_pos
	boss_facing = snapshot.boss_facing
	boss_state = snapshot.boss_state
	hazards.clear()
	hazards.assign(snapshot.hazards)
	for event in snapshot.get("events", []):
		events.append(event)

func _finish_boss_tick() -> void:
	if boss_state == "approach":
		return
	if boss_state == "recover" and not _recover_notified:
		_recover_notified = true
		_try_release_fire()
		events.append({"type": "opening", "pattern": boss_pattern})
	if boss_age >= pattern_runner.duration:
		boss_state = "approach"
		_approach_started = tick
		boss_age = 0
		hazards.clear()

func _start_next_pattern() -> void:
	var phase_patterns: Array = data.phases[phase_id - 1].patterns
	var selected = str(phase_patterns[0])
	if _deferred_pattern != "":
		selected = _deferred_pattern
		_deferred_pattern = ""
		_pattern_bag.erase(selected)
	elif _first_pattern:
		_first_pattern = false
		_pattern_bag.assign(phase_patterns.slice(1))
		if _boss_rng.randi_range(0, 1) == 1:
			_pattern_bag.reverse()
	else:
		if _pattern_bag.is_empty():
			_pattern_bag.assign(phase_patterns)
			for i in range(_pattern_bag.size() - 1, 0, -1):
				var j = _boss_rng.randi_range(0, i)
				var swap = _pattern_bag[i]
				_pattern_bag[i] = _pattern_bag[j]
				_pattern_bag[j] = swap
			if _pattern_bag[0] == _last_pattern:
				var swap = _pattern_bag[0]
				_pattern_bag[0] = _pattern_bag[1]
				_pattern_bag[1] = swap
		selected = _pattern_bag.pop_front()
	if selected == _last_pattern and not _pattern_bag.is_empty():
		var alternative = _pattern_bag.pop_front()
		_pattern_bag.append(selected)
		selected = alternative
	if _start_pattern(selected, false):
		_director_repositioned = false
		return
	# A rejected template is deferred, while other legal attacks in this bag
	# get their full, unchanged telegraph. Preparation has no damage side effect.
	for candidate in _pattern_bag.duplicate():
		if str(candidate) == _last_pattern:
			continue
		if _start_pattern(str(candidate), false):
			_pattern_bag.erase(candidate)
			_pattern_bag.append(selected)
			_director_repositioned = false
			return
	if not _director_repositioned:
		_director_repositioned = true
		_deferred_pattern = selected
		_director_wait_until = tick + 60
		boss_state = "approach"
		_approach_started = tick
		hazards.clear()
		return
	# One relocation attempt, then a bounded per-phase safe fallback.
	var fallback = str({1:"claw",2:"territory",3:"thrust",4:"echo",5:"nameless_end"}[phase_id])
	_start_pattern(fallback, true)
	_pattern_bag.erase(boss_pattern)
	_director_repositioned = false

func _start_pattern(id: String, accept_fallback: bool = true) -> bool:
	var reaction_delay = _ready_delay("attack") if player_state in ["attack", "hurt"] else 0
	# Long ground telegraphs must remain escapable after the current committed
	# action finishes. A shorter certified walking budget is conservative.
	var budget_factor = maxf(0.5, (120.0 - reaction_delay) / 120.0)
	pattern_runner.configure(dodge_distance(), minf(move_speed(), 90.24) * budget_factor)
	pattern_runner.start(id, boss_pos, player_pos, _boss_rng)
	if not accept_fallback and (pattern_runner.actual_id != id or pattern_runner.safety_error != ""):
		return false
	boss_pattern = pattern_runner.actual_id
	safety_error = pattern_runner.safety_error
	if safety_error != "":
		result = "safety_error"
		cause = safety_error
		hazards.clear()
		clear_input()
		events.append({"type": "result", "result": result})
		return false
	boss_state = "telegraph"
	boss_age = 0
	_pattern_started = tick
	_pattern_origin = boss_pos
	_pattern_id += 1
	_recover_notified = false
	_boss_hit_events.clear()
	_last_pattern = boss_pattern
	var direction = player_pos - boss_pos
	if direction.length_squared() > 0.001:
		boss_facing = direction.normalized()
	pattern_history.append(boss_pattern)
	events.append({"type": "telegraph", "pattern": boss_pattern, "pos": boss_pos})
	return true

func _queue_crossed_drops() -> void:
	var lost_ratio = 1.0 - boss_hp / phase_hp_max
	for index in range(data.boss.drop_thresholds.size()):
		if lost_ratio >= float(data.boss.drop_thresholds[index]) and not _drop_crossed.has(index):
			_drop_crossed.append(index)
			_drop_queue.append(index)

func _try_release_fire() -> void:
	if _drop_queue.is_empty():
		return
	var base_angle = _element_rng.randf_range(-PI, PI)
	for i in range(16):
		var direction = Vector2.RIGHT.rotated(base_angle + TAU * i / 16.0)
		var candidate = player_pos + direction * 48.0
		if not Geometry.in_arena(candidate, Vector2(320,184), Vector2(260,126), 12.0):
			continue
		# Pulse can end directly before the next claw. Keep landings outside
		# its maximum radius (56 + player radius), including a small margin.
		if candidate.distance_to(boss_pos) < 68.0:
			continue
		if altars.any(func(altar): return candidate.distance_to(altar.pos) < 24.0):
			continue
		var dropped_element = str(data.phases[phase_id - 1].element)
		if dropped_element == "cycle":
			dropped_element = _p5_elements[int(_drop_queue[0]) % _p5_elements.size()]
		debug_spawn_element(dropped_element, candidate, false)
		_drop_queue.pop_front()
		return

func _update_pickups() -> void:
	var remove_ids: Array[int] = []
	var grounded: Array[Dictionary] = []
	for pickup in pickups:
		pickup["age"] = tick - int(pickup.created_tick)
		if pickup.state == "flying":
			var amount = clampf(float(pickup.age) / float(data.fire.flight_ticks), 0.0, 1.0)
			pickup["pos"] = Vector2(pickup.origin).lerp(pickup.dest, amount)
			if int(pickup.age) >= int(data.fire.flight_ticks):
				pickup["state"] = "grounded"
				pickup["pos"] = pickup.dest
				pickup["landed_tick"] = tick
		if pickup.state == "grounded":
			pickup["ttl"] = ground_lifetime() - (tick - int(pickup.landed_tick))
			if int(pickup.ttl) <= 0:
				remove_ids.append(int(pickup.id))
			else:
				grounded.append(pickup)
	_limit_ground_pickups(remove_ids)
	grounded.sort_custom(func(a, b): return a.landed_tick < b.landed_tick or (a.landed_tick == b.landed_tick and a.id < b.id))
	for pickup in grounded:
		if not remove_ids.has(int(pickup.id)) and player_pos.distance_to(pickup.pos) <= float(data.fire.pickup_radius) and _can_collect_element(str(pickup.element)):
			element_id = str(pickup.element)
			element_charges = element_max_charges(element_id)
			collected_fire += 1 if element_id == "fire" else 0
			collected_elements[element_id] = int(collected_elements.get(element_id, 0)) + 1
			remove_ids.append(int(pickup.id))
			events.append({"type": "pickup", "pos": pickup.pos, "element": element_id})
	for i in range(pickups.size() - 1, -1, -1):
		if remove_ids.has(int(pickups[i].id)):
			pickups.remove_at(i)

func _limit_ground_pickups(removing: Array[int]) -> void:
	var grounded: Array[Dictionary] = []
	for pickup in pickups:
		if pickup.state == "grounded" and not removing.has(int(pickup.id)):
			grounded.append(pickup)
	grounded.sort_custom(func(a, b): return a.landed_tick < b.landed_tick or (a.landed_tick == b.landed_tick and a.id < b.id))
	while grounded.size() > int(data.fire.max_ground):
		removing.append(int(grounded.pop_front().id))

func _update_altars() -> void:
	# This runs after damage resolution. An incoming hit on the 33rd tick
	# cancels the transaction before either weapon can be changed.
	for altar in altars:
		var distance = player_pos.distance_to(Vector2(altar.pos))
		if distance > 20.0:
			altar.armed = true
		var eligible = bool(altar.armed) and distance <= 14.0 and player_state == "idle" and not _altar_input_this_tick and not _hit_this_tick and pending_input == ""
		if not eligible:
			altar.progress = 0
			continue
		altar.progress = int(altar.progress) + 1
		if int(altar.progress) < 33:
			continue
		var previous = weapon_id
		weapon_id = str(altar.weapon)
		altar.weapon = previous
		altar.progress = 0
		altar.armed = false
		stacks = 0
		clear_input()
		events.append({"type":"weapon_swap", "weapon":weapon_id, "previous":previous, "altar":altar.id})

func debug_start_pattern(id: String) -> void:
	assert(data.patterns.has(id), "Unknown pattern")
	_start_pattern(id)

func debug_spawn_fire(point: Vector2, grounded: bool = true) -> void:
	debug_spawn_element("fire", point, grounded)

func _can_collect_element(id: String) -> bool:
	if element_charges <= 0:
		return true
	return element_id == id and element_charges < element_max_charges(id)

func debug_spawn_element(id: String, point: Vector2, grounded: bool = true) -> void:
	assert(data.elements.has(id), "Unknown element")
	_pickup_id += 1
	pickups.append({"id": _pickup_id, "element": id, "state": "grounded" if grounded else "flying", "pos": point if grounded else boss_pos, "origin": boss_pos, "dest": point, "created_tick": tick, "landed_tick": tick if grounded else -1, "age": 0, "ttl": ground_lifetime()})
	if grounded:
		var remove_ids: Array[int] = []
		_limit_ground_pickups(remove_ids)
		for i in range(pickups.size() - 1, -1, -1):
			if remove_ids.has(int(pickups[i].id)):
				pickups.remove_at(i)

func debug_apply_fire() -> void:
	if fire_next_tick < 0:
		fire_next_tick = tick + int(data.fire.dot_interval)
	fire_expires_tick = tick + int(data.fire.dot_duration)

func debug_damage_player(amount: float, source: String = "test") -> void:
	if transition_ticks_remaining > 0 or result != "":
		return
	_injected_damage.append({"damage": amount, "cause": source})
