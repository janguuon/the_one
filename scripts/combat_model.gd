extends RefCounted
## Pure 60 Hz simulation. Rendering, pause and real-time hitstop are external.
const Geometry = preload("res://scripts/combat_geometry.gd")
const DATA_PATH = "res://data/combat.json"

var data: Dictionary
var tick = 0
var mode = "prototype"
var seed_value = 1
var player_pos = Vector2(320, 280)
var boss_pos = Vector2(320, 135)
var player_hp = 100.0
var boss_hp = 1000.0
var player_facing = Vector2.UP
var player_state = "idle"
var state_age = 0
var stacks = 0
var fire_charges = 0
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
var _pattern_locked = false
var _recover_notified = false
var _boss_event_hit = false
var _pattern_bag: Array[String] = []
var _last_pattern = ""
var _first_pattern = true
var _drop_crossed: Array[int] = []
var _drop_queue: Array[int] = []
var _injected_damage: Array[Dictionary] = []
var _boss_rng = RandomNumberGenerator.new()
var _element_rng = RandomNumberGenerator.new()

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert(not data.is_empty(), "Missing combat data")
	reset()

func reset(run_seed: int = 1) -> void:
	seed_value = run_seed
	_boss_rng.seed = run_seed
	_element_rng.seed = run_seed ^ 0x6E624EB7
	tick = 0
	mode = "prototype"
	player_pos = Vector2(320, 280)
	boss_pos = Vector2(320, 135)
	player_hp = float(data.player.hp)
	boss_hp = float(data.boss.hp)
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
	boss_pattern = "claw"
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
	attack.clear()
	pickups.clear()
	hazards.clear()
	events.clear()
	pattern_history.clear()
	_pattern_bag.clear()
	_drop_queue.clear()
	_drop_crossed.clear()
	_injected_damage.clear()
	clear_input()

func clear_input() -> void:
	pending_input = ""
	_pending_until = -1
	_pending_key = ""
	_frozen_intent = ""

func next_attack_kind() -> String:
	var ready = stacks >= int(data.sword.stack_threshold)
	if ready and fire_charges > 0:
		return "resonance"
	if ready:
		return "signature"
	if fire_charges > 0:
		return "fire"
	return "basic"

func is_player_invulnerable() -> bool:
	return tick < player_invulnerable_until or (player_state == "dodge" and state_age >= int(data.player.dodge_inv_start) and state_age <= int(data.player.dodge_inv_end))

func queue_frozen_input(command: Dictionary) -> void:
	if result != "":
		return
	if command.get("dodge", false):
		_frozen_intent = "dodge"
	elif command.get("attack", false) and _frozen_intent != "dodge":
		_frozen_intent = "attack"

func step(command: Dictionary = {}) -> void:
	if result != "":
		return
	tick += 1
	events.clear()
	hitstop_ms = 0.0
	_move = Vector2(command.get("move", Vector2.ZERO)).limit_length(1.0)
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
	if player_state != "dodge":
		_separate_bodies(false)
	var old_kind = next_attack_kind()
	_update_pickups()
	_invalidate_changed_input(old_kind)
	if not dodged and pending_input == "attack" and _ready_delay("attack") == 0:
		if _pending_key == next_attack_kind():
			_start_attack()
		else:
			_clear_pending()
	_resolve_damage()
	_check_result()
	if result != "":
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
				delay = maxi(0, int(data.sword.dodge_cancel_tick) - state_age)
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
	_pending_key = next_attack_kind()

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
	return int(data.sword.startup_ticks) + int(data.sword.active_ticks) + int(data.sword.recovery_ticks)

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
		player_pos += _dodge_direction * float(data.player.dodge_distance) / float(data.player.dodge_ticks)
	elif player_state == "idle" or player_state == "move":
		player_state = "move" if _move.length_squared() > 0.001 else "idle"
		if _move.length_squared() > 0.001:
			player_facing = _move.normalized()
		player_pos += _move * float(data.player.speed) / 60.0
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
	var direction = player_facing
	var to_boss = boss_pos - player_pos
	# Aim uses the nearest point of the boss hurt disk, not its sprite center.
	if to_boss.length() - float(data.boss.hurt_radius) <= float(data.sword.reach) + 12.0 and absf(direction.angle_to(to_boss)) <= deg_to_rad(60.0):
		direction = direction.rotated(clampf(direction.angle_to(to_boss), -deg_to_rad(30.0), deg_to_rad(30.0)))
	var multiplier = 1.0
	if kind == "signature" or kind == "resonance":
		multiplier *= float(data.sword.signature_multiplier)
		stacks = 0
	if kind == "fire" or kind == "resonance":
		multiplier *= float(data.fire.multiplier)
		fire_charges -= 1
	_action_id += 1
	total_attacks += 1
	attack = {"id": _action_id, "kind": kind, "age": 0, "facing": direction, "origin": player_pos, "damage": snappedf(float(data.sword.damage) * multiplier, 0.001), "hit": false}
	player_facing = direction
	_set_player_state("attack")
	_clear_pending()
	events.append({"type": "attack", "kind": kind, "pos": player_pos})

func player_attack_shape() -> Dictionary:
	if attack.is_empty():
		return {}
	var special = attack.kind == "signature" or attack.kind == "resonance"
	return {"shape": "sector", "origin": player_pos, "facing": attack.facing, "radius": float(data.sword.reach), "arc_radians": deg_to_rad(float(data.sword.signature_arc_degrees) if special else float(data.sword.arc_degrees))}

func _invalidate_changed_input(old_kind: String) -> void:
	if old_kind != next_attack_kind() and pending_input == "attack":
		_clear_pending()

func _resolve_damage() -> void:
	var old_kind = next_attack_kind()
	var outgoing = 0.0
	var normal_hit = false
	var fire_hit = false
	if player_state == "attack" and not attack.is_empty() and not attack.hit:
		var start = int(data.sword.startup_ticks)
		if state_age >= start and state_age < start + int(data.sword.active_ticks):
			if Geometry.contains(player_attack_shape(), boss_pos, float(data.boss.hurt_radius)) and boss_hp > 0.0:
				attack["hit"] = true
				outgoing += float(attack.damage)
				normal_hit = attack.kind == "basic"
				fire_hit = attack.kind == "fire" or attack.kind == "resonance"
				events.append({"type": "boss_hit", "damage": attack.damage, "kind": attack.kind, "pos": boss_pos})
				hitstop_ms = 33.0 if attack.kind == "basic" else 67.0
	if fire_next_tick >= 0 and tick >= fire_next_tick and tick <= fire_expires_tick:
		outgoing += float(data.fire.dot_damage)
		fire_next_tick += int(data.fire.dot_interval)
		events.append({"type": "burn", "damage": float(data.fire.dot_damage), "pos": boss_pos})
	var incoming: Array[Dictionary] = []
	if not is_player_invulnerable():
		for hazard in hazards:
			if hazard.phase == "active" and not _boss_event_hit and Geometry.contains(hazard, player_pos, float(data.player.radius)):
				incoming.append({"damage": float(data.patterns[boss_pattern].damage), "cause": str(data.patterns[boss_pattern].name)})
		for injected in _injected_damage:
			incoming.append(injected)
	_injected_damage.clear()
	if outgoing > 0.0:
		var actual = minf(boss_hp, outgoing)
		boss_hp = maxf(0.0, snappedf(boss_hp - outgoing, 0.001))
		damage_dealt += actual
		if normal_hit and actual > 0.0:
			stacks = mini(stacks + 1, int(data.sword.stack_threshold))
		if fire_hit:
			debug_apply_fire()
		_queue_crossed_drops()
	if not incoming.is_empty():
		var greatest: Dictionary = incoming[0]
		for candidate in incoming:
			if float(candidate.damage) > float(greatest.damage):
				greatest = candidate
		var received = minf(player_hp, float(greatest.damage))
		player_hp = maxf(0.0, snappedf(player_hp - float(greatest.damage), 0.001))
		damage_received += received
		cause = str(greatest.cause)
		player_invulnerable_until = tick + int(data.player.hurt_inv_ticks)
		_boss_event_hit = true
		attack.clear()
		_set_player_state("hurt")
		events.append({"type": "player_hit", "damage": greatest.damage, "pos": player_pos})
		hitstop_ms = maxf(hitstop_ms, 67.0)
	if fire_expires_tick >= 0 and tick >= fire_expires_tick:
		fire_expires_tick = -1
		fire_next_tick = -1
	_invalidate_changed_input(old_kind)

func _check_result() -> void:
	if player_hp <= 0.0:
		result = "dead"
	elif boss_hp <= 0.0:
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

func _update_boss() -> void:
	if boss_state == "approach":
		boss_age = tick - _approach_started
		var difference = player_pos - boss_pos
		if difference.length() > float(data.boss.approach_distance):
			var distance = minf(float(data.boss.speed) / 60.0, difference.length() - float(data.boss.approach_distance))
			boss_pos = clamp_position(boss_pos + difference.normalized() * distance, float(data.boss.body_radius))
		if difference.length() <= float(data.boss.approach_distance) + 0.01 or boss_age >= int(data.boss.approach_ticks):
			_start_next_pattern()
		else:
			hazards.clear()
			return
	boss_age = tick - _pattern_started
	var definition: Dictionary = data.patterns[boss_pattern]
	if not _pattern_locked:
		var direction = player_pos - boss_pos
		if direction.length_squared() > 0.001:
			boss_facing = direction.normalized()
		if boss_age >= int(definition.lock_tick):
			_pattern_locked = true
	var telegraph = int(definition.telegraph_ticks)
	var shape = _boss_shape()
	hazards.clear()
	if boss_age < telegraph:
		boss_state = "telegraph"
		shape["phase"] = "telegraph"
		shape["progress"] = float(boss_age) / telegraph
		hazards.append(shape)
	elif boss_pattern == "pulse":
		shape["phase"] = "active"
		shape["progress"] = 1.0
		shape["radius"] = float(definition.radius) + float(definition.speed) * (boss_age - telegraph) / 60.0
		if float(shape.radius) <= _pulse_end_radius():
			boss_state = "execute"
			hazards.append(shape)
		else:
			boss_state = "recover"
	elif boss_age < telegraph + int(definition.active_ticks):
		boss_state = "execute"
		shape["phase"] = "active"
		shape["progress"] = 1.0
		hazards.append(shape)
	else:
		boss_state = "recover"
	if boss_state == "execute" and boss_age == telegraph:
		events.append({"type": "boss_attack", "pattern": boss_pattern, "pos": boss_pos})

func _boss_shape() -> Dictionary:
	var definition: Dictionary = data.patterns[boss_pattern]
	return {"id": _pattern_id, "shape": definition.shape, "origin": _pattern_origin, "facing": boss_facing, "radius": float(definition.get("radius", 0.0)), "width": float(definition.get("width", 0.0)), "length": float(definition.get("length", 0.0)), "arc_radians": deg_to_rad(float(definition.get("arc_degrees", 360.0))), "phase": "telegraph", "progress": 0.0}

func _pulse_end_radius() -> float:
	# Maximum distance to a rectangle enclosing the arena is a conservative bound.
	var greatest = 0.0
	for corner in [Vector2(60,58), Vector2(580,58), Vector2(60,310), Vector2(580,310)]:
		greatest = maxf(greatest, _pattern_origin.distance_to(corner))
	return greatest + 12.0

func _finish_boss_tick() -> void:
	if boss_state == "approach":
		return
	var definition: Dictionary = data.patterns[boss_pattern]
	var recover_start = int(definition.telegraph_ticks) + int(definition.get("active_ticks", 0))
	var end_tick = recover_start + int(definition.recover_ticks)
	if boss_pattern == "pulse":
		recover_start = int(definition.telegraph_ticks) + int(ceil((_pulse_end_radius() - float(definition.radius)) / float(definition.speed) * 60.0)) + 1
		end_tick = maxi(recover_start, int(definition.telegraph_ticks) + int(definition.recover_ticks))
	if boss_state == "recover" and not _recover_notified:
		_recover_notified = true
		_try_release_fire()
		events.append({"type": "opening", "pattern": boss_pattern})
	if boss_age >= end_tick:
		boss_state = "approach"
		_approach_started = tick
		boss_age = 0
		hazards.clear()

func _start_next_pattern() -> void:
	var selected = "claw"
	if _first_pattern:
		_first_pattern = false
		_pattern_bag = ["rupture", "pulse"]
		if _boss_rng.randi_range(0, 1) == 1:
			_pattern_bag.reverse()
	else:
		if _pattern_bag.is_empty():
			_pattern_bag = ["claw", "rupture", "pulse"]
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
	_start_pattern(selected)

func _start_pattern(id: String) -> void:
	boss_pattern = id
	boss_state = "telegraph"
	boss_age = 0
	_pattern_started = tick
	_pattern_origin = boss_pos
	_pattern_id += 1
	_pattern_locked = false
	_recover_notified = false
	_boss_event_hit = false
	_last_pattern = id
	var direction = player_pos - boss_pos
	if direction.length_squared() > 0.001:
		boss_facing = direction.normalized()
	pattern_history.append(id)
	events.append({"type": "telegraph", "pattern": id, "pos": boss_pos})

func _queue_crossed_drops() -> void:
	var lost_ratio = 1.0 - boss_hp / float(data.boss.hp)
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
		debug_spawn_fire(candidate, false)
		_drop_queue.pop_front()
		return

func _update_pickups() -> void:
	var remove_ids: Array[int] = []
	for pickup in pickups:
		pickup["age"] = tick - int(pickup.created_tick)
		if pickup.state == "flying":
			var amount = clampf(float(pickup.age) / float(data.fire.flight_ticks), 0.0, 1.0)
			pickup["pos"] = Vector2(pickup.origin).lerp(pickup.dest, amount)
			if int(pickup.age) >= int(data.fire.flight_ticks):
				pickup["state"] = "grounded"
				pickup["pos"] = pickup.dest
				pickup["landed_tick"] = tick
				_limit_ground_pickups(remove_ids)
		if pickup.state == "grounded":
			pickup["ttl"] = int(data.fire.ground_ticks) - (tick - int(pickup.landed_tick))
			if int(pickup.ttl) <= 0:
				remove_ids.append(int(pickup.id))
			elif not remove_ids.has(int(pickup.id)) and player_pos.distance_to(pickup.pos) <= float(data.fire.pickup_radius) and fire_charges < int(data.fire.charges):
				fire_charges = int(data.fire.charges)
				collected_fire += 1
				remove_ids.append(int(pickup.id))
				events.append({"type": "pickup", "pos": pickup.pos})
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

func debug_start_pattern(id: String) -> void:
	assert(data.patterns.has(id), "Unknown pattern")
	_start_pattern(id)

func debug_spawn_fire(point: Vector2, grounded: bool = true) -> void:
	_pickup_id += 1
	pickups.append({"id": _pickup_id, "state": "grounded" if grounded else "flying", "pos": point if grounded else boss_pos, "origin": boss_pos, "dest": point, "created_tick": tick, "landed_tick": tick if grounded else -1, "age": 0, "ttl": int(data.fire.ground_ticks)})
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
	_injected_damage.append({"damage": amount, "cause": source})
