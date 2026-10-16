extends RefCounted
## One deterministic timeline owns both telegraph geometry and damage geometry.
## update() is called once per combat tick; repeated calls for the same age are
## idempotent, including the three player-position recordings in footprints.

const Geometry = preload("res://scripts/combat_geometry.gd")
const ARENA_CENTER := Vector2(320, 184)
const ARENA_RADII := Vector2(260, 126)
const ALLOWED_ROLLS := [64.8, 72.0, 74.52, 82.8]
const PLAYER_RADIUS := 6.0
const BODY_SEPARATION := 24.5
const CLEARANCE := 22.0 # Player radius plus a 16px half-width walking corridor.

var definitions: Dictionary = {}
var actual_id: String = ""
var safety_error: String = ""
var safety: Dictionary = {}
var recover_start: int = 0
var duration: int = 0
var dodge_distance: float = 72.0
var minimum_speed: float = 90.24
var _origin := Vector2.ZERO
var _start_player := Vector2.ZERO
var _initial_facing := Vector2.DOWN
var _facing := Vector2.DOWN
var _boss_pos := Vector2.ZERO
var _definition: Dictionary = {}
var _locks: Dictionary = {}
var _circles: Array[Vector2] = []
var _routes: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _recorded_ticks: Array[int] = []
var _corridor_axis := Vector2.DOWN
var _last_age: int = -1
var _snapshot: Dictionary = {}

func _init() -> void:
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_patterns.json"))

func configure(actual_dodge_distance: float = 72.0, min_speed: float = 90.24) -> void:
	dodge_distance = actual_dodge_distance
	minimum_speed = min_speed

func get_definition(id: String) -> Dictionary:
	return Dictionary(definitions.get(id, {})).duplicate(true)

func start(id: String, origin: Vector2, player_pos: Vector2, rng: RandomNumberGenerator) -> void:
	actual_id = id
	safety_error = ""
	safety = {"valid": true, "template": id, "reason": "", "paths": [], "skipped_records": [], "circle_count": 0}
	_origin = origin
	_boss_pos = origin
	_start_player = player_pos
	_initial_facing = _direction(origin, player_pos)
	_facing = _initial_facing
	_locks.clear()
	_circles.clear()
	_routes.clear()
	_records.clear()
	_recorded_ticks.clear()
	_last_age = -1
	_snapshot.clear()
	if not definitions.has(id) or not Geometry.in_arena(origin, ARENA_CENTER, ARENA_RADII, 18.0) or not Geometry.in_arena(player_pos, ARENA_CENTER, ARENA_RADII, PLAYER_RADIUS):
		_fail("Unknown pattern or illegal starting position: " + id)
		return
	_definition = get_definition(actual_id)
	match id:
		"territory":
			if not _prepare_ground(player_pos, rng, false):
				_fail("No reachable escape from territory, including its one-circle fallback")
		"rings", "fractures":
			if not _prepare_rings(player_pos, id == "fractures"):
				_use_fallback("territory" if id == "rings" else "echo", "No continuous inside/outside ring route", player_pos, rng)
		"horizon":
			if not _prepare_horizon(player_pos, rng):
				_use_fallback("territory", "Neither 60px corridor is reachable with its full width", player_pos, rng)
		"dash":
			if not _prepare_dash(player_pos, rng):
				_use_fallback("thrust", "No three distinct legal dash segments with a reachable escape", player_pos, rng)
		"last_horizon":
			if not _prepare_ground(player_pos, rng, true):
				_use_fallback("nameless_end", "No certified wave route, even after removing every circle", player_pos, rng)
	_set_timing()

func _use_fallback(id: String, reason: String, player_pos: Vector2, rng: RandomNumberGenerator) -> void:
	# A bounded, explicit fallback, never a recursive attempt to start a pattern.
	actual_id = id
	_definition = get_definition(id)
	_circles.clear()
	_routes.clear()
	safety["fallback_reason"] = reason
	safety["template"] = id + "_fallback"
	if id == "territory":
		_circles.append(player_pos)
		var escape: Dictionary = _escape_certificate(_circles, player_pos, 120, 324)
		if escape.is_empty():
			_fail("Fallback territory has no reachable safe path")
		else:
			safety["paths"] = [escape]
			safety["circle_count"] = 1

func _fail(reason: String) -> void:
	safety_error = reason
	safety["valid"] = false
	safety["reason"] = reason
	recover_start = 0
	duration = 0

func _set_timing() -> void:
	if safety_error != "":
		return
	if actual_id == "pulse":
		recover_start = _wave_end_tick(int(_definition.telegraph_ticks))
		duration = maxi(recover_start, int(_definition.telegraph_ticks) + int(_definition.recover_ticks))
	elif actual_id == "last_horizon":
		recover_start = maxi(int(_definition.telegraph_ticks) + int(_definition.active_ticks), _wave_end_tick(int(_definition.wave_start)))
		duration = recover_start + int(_definition.recover_ticks)
	else:
		recover_start = int(_definition.recover_start)
		duration = recover_start + int(_definition.recover_ticks)

func update(age: int, player_pos: Vector2) -> Dictionary:
	if age == _last_age:
		return _snapshot.duplicate(true)
	var hazards: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	_boss_pos = _origin
	if safety_error == "":
		match actual_id:
			"claw":
				_facing = _track("claw", age, 0, int(_definition.lock_tick), player_pos)
				var begin: int = int(_definition.telegraph_ticks)
				_add(hazards, _sector(_facing), "claw_1", age, 0, begin, begin + int(_definition.active_ticks) - 1, float(_definition.damage), 1)
			"rupture", "thrust":
				_facing = _track("line", age, 0, int(_definition.lock_tick), player_pos)
				var start_tick: int = int(_definition.telegraph_ticks)
				_add(hazards, _line(_facing, float(_definition.length)), actual_id + "_1", age, 0, start_tick, start_tick + int(_definition.active_ticks) - 1, float(_definition.damage), 1)
			"pulse":
				_add_wave(hazards, age, 0, int(_definition.telegraph_ticks), "pulse_1")
			"territory", "last_horizon":
				var ground_begin: int = int(_definition.telegraph_ticks)
				var last: int = ground_begin + int(_definition.active_ticks) - 1
				for i in range(_circles.size()):
					_add(hazards, {"shape":"disk", "origin":_circles[i], "radius":float(_definition.radius)}, actual_id + "_ground_" + str(i + 1), age, 0, ground_begin, last, float(_definition.damage), i + 1)
				if actual_id == "last_horizon":
					_add_wave(hazards, age, int(_definition.wave_preview), int(_definition.wave_start), "last_horizon_wave")
			"rings", "fractures":
				var starts: Array = _definition.strike_ticks
				for i in range(starts.size()):
					var shape: Dictionary = {"shape":"disk", "origin":_origin, "radius":float(_definition.radius)} if i % 2 == 0 else {"shape":"annulus", "origin":_origin, "inner_radius":float(_definition.radius), "outer_radius":800.0}
					_add(hazards, shape, actual_id + "_" + str(i + 1), age, 0, int(starts[i]), int(starts[i]) + int(_definition.active_ticks) - 1, float(_definition.damage), i + 1)
			"horizon":
				var begin: int = int(_definition.telegraph_ticks)
				_add(hazards, {"shape":"corridor", "origin":_origin, "facing":_corridor_axis, "width":float(_definition.width)}, "horizon_1", age, 0, begin, begin + int(_definition.active_ticks) - 1, float(_definition.damage), 1)
			"heartbeat", "execution":
				var last_preview: int = int(_definition.last_preview)
				var first_facing: Vector2 = _track("first_pair", age, 0, int(_definition.lock_tick), player_pos)
				var final_facing: Vector2 = _track("last_beat", age, last_preview, int(_definition.last_lock), player_pos)
				_facing = first_facing if age < last_preview else final_facing
				for i in range(3):
					var direction: Vector2 = first_facing if i < 2 else final_facing
					var preview: int = 0 if i < 2 else last_preview
					_add(hazards, _sector(direction), actual_id + "_" + str(i + 1), age, preview, int(_definition.strike_ticks[i]), int(_definition.strike_ticks[i]) + int(_definition.active_ticks) - 1, float(_definition.strike_damage[i]), i + 1)
				if actual_id == "execution" and age >= int(_definition.line_preview):
					_facing = _track("execution_line", age, int(_definition.line_preview), int(_definition.line_lock), player_pos)
					var begin: int = int(_definition.strike_ticks[3])
					_add(hazards, _line(_facing, float(_definition.line_length)), "execution_4", age, int(_definition.line_preview), begin, begin + int(_definition.active_ticks) - 1, float(_definition.strike_damage[3]), 4)
			"dash":
				_update_dash(hazards, age)
			"echo", "nameless_end":
				var echo_facing: Vector2 = _track("echo", age, 0, int(_definition.lock_tick), player_pos)
				_facing = echo_facing
				for i in range(2):
					var begin: int = int(_definition.strike_ticks[i])
					_add(hazards, _sector(echo_facing), actual_id + "_" + str(i + 1), age, 0, begin, begin + int(_definition.active_ticks) - 1, float(_definition.strike_damage[i]), i + 1, i == 1)
				if actual_id == "nameless_end" and age >= int(_definition.line_preview):
					_facing = _track("nameless_line", age, int(_definition.line_preview), int(_definition.line_lock), player_pos)
					var begin: int = int(_definition.strike_ticks[2])
					_add(hazards, _line(_facing, float(_definition.line_length)), "nameless_end_3", age, int(_definition.line_preview), begin, begin + int(_definition.active_ticks) - 1, float(_definition.strike_damage[2]), 3)
			"footprints":
				_record_footprint(age, player_pos)
				for record in _records:
					var begin: int = int(record.tick) + int(_definition.telegraph_ticks)
					_add(hazards, {"shape":"disk", "origin":record.pos, "radius":float(_definition.radius)}, "footprints_" + str(record.number), age, int(record.tick), begin, begin + int(_definition.active_ticks) - 1, float(_definition.damage), int(record.number), true)
	for hazard in hazards:
		if age == int(hazard.start_tick):
			events.append({"type":"boss_attack", "pattern":actual_id, "event_id":hazard.event_id, "pos":_boss_pos})
	var first_tick: int = int(_definition.get("telegraph_ticks", 0))
	var state: String = "recover" if age >= recover_start else ("telegraph" if age < first_tick else "execute")
	_snapshot = {"hazards":hazards, "boss_pos":_boss_pos, "boss_facing":_facing, "boss_state":state, "recover_start":recover_start, "duration":duration, "events":events, "actual_id":actual_id, "safety_error":safety_error, "safety":safety}
	_last_age = age
	return _snapshot.duplicate(true)

func _track(key: String, age: int, start_tick: int, lock_tick: int, player_pos: Vector2) -> Vector2:
	if not _locks.has(key):
		_locks[key] = {"direction":_initial_facing, "locked":false}
	var item: Dictionary = _locks[key]
	if age >= start_tick and not bool(item.locked):
		item["direction"] = _direction(_origin, player_pos)
		if age >= lock_tick:
			item["locked"] = true
	return item.direction

func _sector(facing: Vector2) -> Dictionary:
	return {"shape":"sector", "origin":_origin, "facing":facing, "radius":float(_definition.radius), "arc_radians":deg_to_rad(float(_definition.arc_degrees))}

func _line(facing: Vector2, length: float) -> Dictionary:
	return {"shape":"line", "origin":_origin, "facing":facing, "length":length, "width":float(_definition.width)}

func _add(hazards: Array[Dictionary], shape: Dictionary, event_id: String, age: int, preview: int, start_tick: int, end_tick: int, damage: float, number: int, echo: bool = false) -> void:
	if age < preview or age > end_tick:
		return
	var hazard: Dictionary = shape.duplicate(true)
	# Preserve a uniform shape record for callers and the original M2 inspector.
	for field in ["radius", "width", "length"]:
		if not hazard.has(field):
			hazard[field] = 0.0
	if not hazard.has("arc_radians"):
		hazard["arc_radians"] = TAU
	if not hazard.has("facing"):
		hazard["facing"] = _initial_facing
	var damage_cause = str(_definition.name)
	if actual_id in ["heartbeat","execution","dash","echo","nameless_end","fractures","rings","footprints"]:
		damage_cause += " · %d번째 %s" % [number, "잔향" if echo else "타격"]
	elif actual_id in ["territory","last_horizon"]:
		damage_cause += " · 파동" if event_id.ends_with("wave") else " · 장판 %d" % number
	hazard.merge({"id":event_id, "event_id":event_id, "damage":damage, "cause":damage_cause, "phase":"active" if age >= start_tick else "telegraph", "progress":clampf(float(age - preview) / maxi(1, start_tick - preview), 0.0, 1.0), "preview_tick":preview, "start_tick":start_tick, "end_tick":end_tick, "number":number, "echo":echo, "dashed":echo, "label":str(number)})
	hazards.append(hazard)

func _add_wave(hazards: Array[Dictionary], age: int, preview: int, start_tick: int, event_id: String) -> void:
	var wave: Dictionary = _wave_parameters()
	var radius: float = float(wave.radius) + float(wave.speed) / 60.0 * maxi(0, age - start_tick)
	_add(hazards, {"shape":"ring", "origin":_origin, "radius":radius, "width":float(wave.width), "facing":_initial_facing}, event_id, age, preview, start_tick, _wave_end_tick(start_tick) - 1, float(wave.damage), 1)

func _wave_parameters() -> Dictionary:
	if actual_id == "last_horizon":
		return {"radius":_definition.wave_radius, "width":_definition.wave_width, "speed":_definition.wave_speed, "damage":_definition.wave_damage}
	return {"radius":_definition.radius, "width":_definition.width, "speed":_definition.speed, "damage":_definition.damage}

func _wave_end_tick(start_tick: int) -> int:
	var greatest: float = 0.0
	for corner in [Vector2(60,58), Vector2(580,58), Vector2(60,310), Vector2(580,310)]:
		greatest = maxf(greatest, _origin.distance_to(corner))
	var wave: Dictionary = _wave_parameters()
	return start_tick + int(ceil((greatest + 12.0 - float(wave.radius)) / (float(wave.speed) / 60.0))) + 1

func _direction(from: Vector2, to: Vector2) -> Vector2:
	var difference: Vector2 = to - from
	return difference.normalized() if difference.length_squared() > 0.001 else _initial_facing

func _prepare_ground(player_pos: Vector2, rng: RandomNumberGenerator, with_wave: bool) -> bool:
	var angle: float = rng.randf_range(-PI, PI)
	var candidates: Array[Vector2] = [player_pos]
	for turn in [-1.1, 1.1]:
		var candidate: Vector2 = player_pos + Vector2.RIGHT.rotated(angle + float(turn)) * rng.randf_range(48.0, 80.0)
		if Geometry.in_arena(candidate, ARENA_CENTER, ARENA_RADII):
			candidates.append(candidate)
	var minimum: int = 0 if with_wave else 1
	for count in range(candidates.size(), minimum - 1, -1):
		var circles: Array[Vector2] = []
		for i in range(count):
			circles.append(candidates[i])
		if with_wave:
			var paths: Array[Dictionary] = []
			var rolls: Array = ALLOWED_ROLLS.duplicate()
			if not rolls.has(dodge_distance):
				rolls.append(dodge_distance)
			for distance in rolls:
				var path: Dictionary = _last_horizon_certificate(circles, player_pos, float(distance))
				if path.is_empty():
					paths.clear()
					break
				paths.append(path)
			if not paths.is_empty():
				_circles = circles
				safety["paths"] = paths
				safety["circle_count"] = count
				safety["template"] = "last_horizon_radial_corridor_" + str(count)
				return true
		else:
			var path: Dictionary = _escape_certificate(circles, player_pos, 120, 324)
			if not path.is_empty():
				_circles = circles
				safety["paths"] = [path]
				safety["circle_count"] = count
				return true
	return false

func _escape_certificate(circles: Array[Vector2], start_pos: Vector2, deadline: int, end_tick: int) -> Dictionary:
	# Small hand-authored radial templates, then a bounded grid of inward routes.
	var candidates: Array[Vector2] = []
	for distance in [48.0, 64.0, 96.0, 128.0]:
		for i in range(16):
			candidates.append(start_pos + Vector2.RIGHT.rotated(TAU * i / 16.0) * float(distance))
	candidates.append(ARENA_CENTER)
	for target in candidates:
		if not _clear_point(target, circles, CLEARANCE) or target.distance_to(_origin) < BODY_SEPARATION:
			continue
		var route: Array[Vector2] = _walking_route(start_pos, target)
		if route.is_empty() or _route_length(route) > minimum_speed * deadline / 60.0:
			continue
		return {"kind":"walk", "positions":_sample_route(route, end_tick), "target":target, "arrival_tick":int(ceil(_route_length(route) * 60.0 / minimum_speed)), "clear_width":32.0}
	return {}

func _clear_point(point: Vector2, circles: Array[Vector2], clearance: float = PLAYER_RADIUS) -> bool:
	if not Geometry.in_arena(point, ARENA_CENTER, ARENA_RADII, clearance):
		return false
	for circle in circles:
		if point.distance_to(circle) <= 22.0 + clearance:
			return false
	return true

func _walking_route(from: Vector2, to: Vector2) -> Array[Vector2]:
	var direct: Array[Vector2] = [from, to]
	if _segment_body_clear(from, to):
		return direct
	var best: Array[Vector2] = []
	var best_length: float = INF
	for i in range(16):
		var waypoint: Vector2 = _origin + Vector2.RIGHT.rotated(TAU * i / 16.0) * 52.0
		if not Geometry.in_arena(waypoint, ARENA_CENTER, ARENA_RADII, PLAYER_RADIUS) or not _segment_body_clear(from, waypoint) or not _segment_body_clear(waypoint, to):
			continue
		var route: Array[Vector2] = [from, waypoint, to]
		var length: float = _route_length(route)
		if length < best_length:
			best = route
			best_length = length
	return best

func _segment_body_clear(from: Vector2, to: Vector2) -> bool:
	# Allow numerical equality at a legal separation point.
	return _origin.distance_to(Geometry2D.get_closest_point_to_segment(_origin, from, to)) >= BODY_SEPARATION - 0.01

func _route_length(route: Array[Vector2]) -> float:
	var length: float = 0.0
	for i in range(1, route.size()):
		length += route[i - 1].distance_to(route[i])
	return length

func _route_point(route: Array[Vector2], traveled: float) -> Vector2:
	for i in range(1, route.size()):
		var length: float = route[i - 1].distance_to(route[i])
		if traveled <= length and length > 0.001:
			return route[i - 1].lerp(route[i], traveled / length)
		traveled -= length
	return route[-1]

func _sample_route(route: Array[Vector2], end_tick: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for age in range(end_tick + 1):
		positions.append(_route_point(route, minimum_speed * age / 60.0))
	return positions

func _prepare_rings(player_pos: Vector2, four: bool) -> bool:
	for i in range(32):
		var direction: Vector2 = Vector2.RIGHT.rotated(TAU * i / 32.0)
		var outer: Vector2 = _origin + direction * 76.0
		var inner: Vector2 = _origin + direction * 52.0
		if not Geometry.in_arena(outer, ARENA_CENTER, ARENA_RADII, PLAYER_RADIUS) or not Geometry.in_arena(inner, ARENA_CENTER, ARENA_RADII, PLAYER_RADIUS):
			continue
		var route: Array[Vector2] = _walking_route(player_pos, outer)
		if route.is_empty() or _route_length(route) > minimum_speed * 120.0 / 60.0:
			continue
		var end_tick: int = 405 if four else 267
		var positions: Array[Vector2] = _sample_route(route, end_tick)
		var transitions: Array = [126, 183, 240] if four else [126]
		var previous: Vector2 = outer
		for index in range(transitions.size()):
			var target: Vector2 = inner if index % 2 == 0 else outer
			var begin: int = int(transitions[index])
			for age in range(begin, end_tick + 1):
				positions[age] = previous.move_toward(target, minimum_speed * (age - begin + 1) / 60.0)
			previous = target
		var valid: bool = true
		var strikes: Array = [120,177,234,291] if four else [120,177]
		for index in range(strikes.size()):
			for age in range(int(strikes[index]), int(strikes[index]) + 6):
				var radius: float = positions[age].distance_to(_origin)
				if (index % 2 == 0 and radius < 70.0) or (index % 2 == 1 and radius > 58.0):
					valid = false
		if valid:
			safety["paths"] = [{"kind":"alternating_rings", "positions":positions, "outer":outer, "inner":inner, "clear_width":32.0}]
			return true
	return false

func _prepare_horizon(player_pos: Vector2, rng: RandomNumberGenerator) -> bool:
	var axes: Array[Vector2] = [Vector2.DOWN, Vector2.RIGHT]
	if rng.randi_range(0, 1) == 1:
		axes.reverse()
	for axis in axes:
		var best: Dictionary = {}
		var shortest: float = INF
		for step in range(-13,14):
			var target: Vector2 = _origin + axis * step * 20.0
			if not Geometry.in_arena(target, ARENA_CENTER, ARENA_RADII, CLEARANCE) or target.distance_to(_origin) < 41.0:
				continue
			var route: Array[Vector2] = _walking_route(player_pos, target)
			var length: float = _route_length(route) if not route.is_empty() else INF
			if length <= minimum_speed * 132.0 / 60.0 and length < shortest:
				shortest = length
				best = {"kind":"corridor", "positions":_sample_route(route, 222), "target":target, "clear_width":48.0}
		if not best.is_empty():
			_corridor_axis = axis
			safety["paths"] = [best]
			return true
	return false

func _prepare_dash(player_pos: Vector2, rng: RandomNumberGenerator) -> bool:
	var first_angle: float = rng.randf_range(-PI, PI)
	for index in range(16):
		var angle: float = first_angle + TAU * index / 16.0
		var points: Array[Vector2] = [_origin]
		for offset in [Vector2(112,0), Vector2(64,80), Vector2(-56,24)]:
			points.append(Geometry.clamp_arena(_origin + Vector2(offset).rotated(angle), ARENA_CENTER, ARENA_RADII, 18.0))
		var routes: Array[Dictionary] = []
		var valid: bool = true
		for i in range(3):
			var delta: Vector2 = points[i + 1] - points[i]
			if delta.length() > float(_definition.max_length) + 0.001 or delta.length() < 40.0:
				valid = false
				break
			routes.append({"shape":"capsule", "origin":points[i], "facing":delta.normalized(), "length":delta.length(), "width":float(_definition.width)})
		if not valid:
			continue
		# Reject parallel return segments, including degenerate wall-clamped routes.
		for a in range(routes.size()):
			for b in range(a + 1, routes.size()):
				if absf(Vector2(routes[a].facing).cross(Vector2(routes[b].facing))) < 0.12:
					valid = false
		if not valid:
			continue
		for distance in [0.0,48.0,80.0,120.0,160.0]:
			for turn in range(16):
				var target: Vector2 = player_pos + Vector2.RIGHT.rotated(TAU * turn / 16.0) * float(distance)
				if not Geometry.in_arena(target, ARENA_CENTER, ARENA_RADII, CLEARANCE):
					continue
				var clear: bool = true
				for route_shape in routes:
					if Geometry.contains(route_shape, target, CLEARANCE):
						clear = false
				if not clear:
					continue
				var walk: Array[Vector2] = _walking_route(player_pos, target)
				if walk.is_empty() or _route_length(walk) > minimum_speed * 120.0 / 60.0:
					continue
				_routes = routes
				safety["paths"] = [{"kind":"dash_escape", "positions":_sample_route(walk, 342), "target":target, "clear_width":32.0}]
				return true
	return false

func _update_dash(hazards: Array[Dictionary], age: int) -> void:
	for i in range(_routes.size()):
		var route: Dictionary = _routes[i]
		var start_tick: int = int(_definition.strike_ticks[i])
		var speed_per_tick: float = float(_definition.speed) / 60.0
		var shape: Dictionary = route.duplicate(true)
		if age >= start_tick:
			var distance: float = minf(float(route.length), (age - start_tick + 1) * speed_per_tick)
			_boss_pos = Vector2(route.origin) + Vector2(route.facing) * distance
			_facing = route.facing
			if age < start_tick + int(_definition.active_ticks):
				var previous_distance: float = minf(float(route.length), (age - start_tick) * speed_per_tick)
				shape["origin"] = Vector2(route.origin) + Vector2(route.facing) * previous_distance
				shape["length"] = distance - previous_distance
		_add(hazards, shape, "dash_" + str(i + 1), age, 0, start_tick, start_tick + int(_definition.active_ticks) - 1, float(_definition.damage), i + 1)

func _record_footprint(age: int, player_pos: Vector2) -> void:
	var record_number: int = -1
	for i in range(_definition.record_ticks.size()):
		if int(_definition.record_ticks[i]) == age:
			record_number = i + 1
			break
	if record_number < 0 or _recorded_ticks.has(age):
		return
	_recorded_ticks.append(age)
	var circles: Array[Vector2] = []
	for record in _records:
		circles.append(record.pos)
	circles.append(player_pos)
	# Future explosions are conservatively treated as one persistent union. If
	# the union has a reachable escape, the timed explosions do too.
	var path: Dictionary = _escape_certificate(circles, player_pos, int(_definition.telegraph_ticks) - age, duration - age)
	if path.is_empty():
		safety.skipped_records.append(age)
		return
	_records.append({"tick":age, "pos":player_pos, "number":record_number})
	safety["paths"] = [path]
	safety["circle_count"] = _records.size()

func _last_horizon_certificate(circles: Array[Vector2], player_pos: Vector2, roll_distance: float) -> Dictionary:
	var wave_end: int = _wave_end_tick(240)
	for radius in [136.0,152.0,168.0,184.0]:
		for i in range(32):
			var direction: Vector2 = Vector2.RIGHT.rotated(TAU * i / 32.0)
			var waiting: Vector2 = _origin + direction * float(radius)
			var ending: Vector2 = waiting - direction * roll_distance
			if not _clear_point(waiting, circles, CLEARANCE) or not _clear_point(ending, circles, CLEARANCE):
				continue
			var walk: Array[Vector2] = _walking_route(player_pos, waiting)
			if walk.is_empty() or _route_length(walk) > minimum_speed * 120.0 / 60.0:
				continue
			var dodge_start: int = 240 + int(floor((float(radius) - 28.0 - 36.0) / 4.0))
			var valid: bool = true
			var roll_positions: Array[Vector2] = []
			var previous: Vector2 = waiting
			for roll_age in range(25):
				var point: Vector2 = waiting - direction * roll_distance * minf(1.0, float(roll_age + 1) / 24.0)
				if roll_age == 24:
					point = _separated_end(point, -direction)
				# The whole route has a 32px footpoint corridor, including the
				# final body separation segment. No hazard is tanked by a shield.
				if not _clear_point(point, circles, CLEARANCE):
					valid = false
					break
				for circle in circles:
					if circle.distance_to(Geometry2D.get_closest_point_to_segment(circle, previous, point)) <= 22.0 + CLEARANCE:
						valid = false
				var wave_radius: float = 28.0 + 4.0 * (dodge_start + roll_age - 240)
				var intersects: bool = absf(point.distance_to(_origin) - wave_radius) <= 10.0
				if intersects and not (roll_age >= 3 and roll_age <= 14):
					valid = false
					break
				roll_positions.append(point)
				previous = point
			if not valid:
				continue
			# Check all wave ticks, not just the two endpoint positions.
			for age in range(240, wave_end):
				var point: Vector2 = waiting if age < dodge_start else roll_positions[mini(age - dodge_start, 24)]
				var invulnerable: bool = age >= dodge_start + 3 and age <= dodge_start + 14
				if absf(point.distance_to(_origin) - (28.0 + 4.0 * (age - 240))) <= 10.0 and not invulnerable:
					valid = false
					break
			if not valid:
				continue
			var positions: Array[Vector2] = _sample_route(walk, maxi(312, wave_end) + 108)
			for age in range(dodge_start, positions.size()):
				positions[age] = roll_positions[mini(age - dodge_start, 24)]
			return {"kind":"last_horizon", "dodge_distance":roll_distance, "dodge_start":dodge_start, "dodge_direction":-direction, "positions":positions, "waiting":waiting, "ending":roll_positions[-1], "arrival_tick":int(ceil(_route_length(walk) * 60.0 / minimum_speed)), "clear_width":32.0}
	return {}

func _separated_end(point: Vector2, dodge_direction: Vector2) -> Vector2:
	if point.distance_to(_origin) >= BODY_SEPARATION:
		return point
	for degrees in [0,45,-45,90,-90,135,-135,180]:
		var candidate: Vector2 = _origin + dodge_direction.rotated(deg_to_rad(float(degrees))) * BODY_SEPARATION
		if Geometry.in_arena(candidate, ARENA_CENTER, ARENA_RADII, PLAYER_RADIUS):
			return candidate
	return point
