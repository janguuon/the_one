extends SceneTree

## Independently replay certified positions against live timeline geometry.
## No player health, damage reduction or post-hit immunity can hide a collision.
const Patterns = preload("res://scripts/boss_patterns.gd")
const Geometry = preload("res://scripts/combat_geometry.gd")
const CENTER = Vector2(320, 184)
const RADII = Vector2(260, 126)
const MIN_SPEED = 90.24
const ROLLS = [64.8, 72.0, 74.52, 82.8]
const AREA_PATTERNS = ["territory", "rings", "horizon", "dash", "fractures", "last_horizon"]
var checks: int = 0
var failures: Array[String] = []
var replayed_paths: int = 0
var replayed_ticks: int = 0
var fallbacks: int = 0
var sample_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var states: Array[Dictionary] = _starting_states()
	sample_count = states.size()
	_check(states.size() >= 12 and states.size() <= 30, "Safety sampling uses 12 through 30 distinct legal starting states")
	for index in range(states.size()):
		for requested in AREA_PATTERNS:
			_test_state(requested, states[index].boss, states[index].player, 137 + index * 37)
	_check(fallbacks >= 3, "Opposite-side deadline failures exercise bounded fallbacks and full replacement telegraphs")
	print("PATTERN SAFETY: %d checks, %d failures, %d states, %d paths, %d live geometry ticks, %d fallbacks" % [checks, failures.size(), sample_count, replayed_paths, replayed_ticks, fallbacks])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _starting_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for boss in [Vector2(320, 184), Vector2(150, 110), Vector2(485, 258)]:
		var local_count = 0
		for radial_index in range(4):
			for turn in range(8):
				if (radial_index + turn) % 3 != 0:
					continue
				var distance: float = [30.0, 60.0, 100.0, 160.0][radial_index]
				var player: Vector2 = boss + Vector2.RIGHT.rotated(TAU * turn / 8.0) * distance
				if Geometry.in_arena(boss, CENTER, RADII, 18.0) and Geometry.in_arena(player, CENTER, RADII, 6.0):
					states.append({"boss": boss, "player": player})
					local_count += 1
		_check(local_count >= 3, "Centered or edge boss %s has several legal near and distant starts" % str(boss))
	# Opposite-side legal positions force the ring/wave placement deadline to
	# reject a route, exercising the bounded fallback rather than only success.
	states.append({"boss": Vector2(150, 110), "player": Vector2(550, 184)})
	states.append({"boss": Vector2(485, 258), "player": Vector2(90, 184)})
	return states


func _new_runner(requested: String, boss: Vector2, player: Vector2, seed_value: int):
	var runner = Patterns.new()
	runner.configure(72.0, MIN_SPEED)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	runner.start(requested, boss, player, rng)
	return runner


func _test_state(requested: String, boss: Vector2, player: Vector2, seed_value: int) -> void:
	var runner = _new_runner(requested, boss, player, seed_value)
	var label = "%s boss%s player%s seed%d" % [requested, str(boss), str(player), seed_value]
	_check(runner.safety_error.is_empty() and runner.duration > 0 and runner.duration < 1000,
		label + " finishes bounded placement validation with a playable pattern")
	if not runner.safety_error.is_empty():
		return
	var allowed: Dictionary = {
		"territory": ["territory"], "rings": ["rings", "territory"],
		"horizon": ["horizon", "territory"], "dash": ["dash", "thrust"],
		"fractures": ["fractures", "echo"], "last_horizon": ["last_horizon", "nameless_end"]
	}
	_check(allowed[requested].has(runner.actual_id), label + " uses only its documented fallback")
	if runner.actual_id != requested:
		fallbacks += 1
		_check(not str(runner.safety.get("fallback_reason", "")).is_empty(), label + " reports its fallback reason")
	if runner.actual_id == "last_horizon":
		var distances: Array[float] = []
		for path in runner.safety.paths:
			distances.append(float(path.get("dodge_distance", 0.0)))
		var all_rolls = true
		for roll in ROLLS:
			all_rolls = all_rolls and distances.has(float(roll))
		_check(all_rolls, label + " certifies all four allowed dodge distances")
	if AREA_PATTERNS.has(runner.actual_id):
		_check(not runner.safety.paths.is_empty(), label + " publishes an actual continuous safe route")
	for path in runner.safety.paths:
		_replay_path(requested, boss, player, seed_value, path, runner.duration, label)
	if runner.safety.paths.is_empty():
		# Non-area fallbacks keep their complete established telegraph timing.
		var begins = {"thrust": 96, "echo": 51, "nameless_end": 51}
		var expected_begin: int = int(begins.get(runner.actual_id, -1))
		var first_active = -1
		for age in range(expected_begin + 1):
			var snapshot: Dictionary = runner.update(age, player)
			for hazard in snapshot.hazards:
				if hazard.phase == "active" and first_active < 0:
					first_active = age
		_check(expected_begin > 0 and first_active == expected_begin,
			label + " fallback retains its full documented first telegraph")


func _replay_path(requested: String, boss: Vector2, player: Vector2, seed_value: int, path: Dictionary, duration: int, label: String) -> void:
	replayed_paths += 1
	var points: Array = path.get("positions", [])
	_check(points.size() > duration and not points.is_empty() and Vector2(points[0]).distance_to(player) < 0.001,
		label + " route begins at the real player position and spans the whole pattern")
	if points.is_empty():
		return
	var runner = _new_runner(requested, boss, player, seed_value)
	var dodge_start: int = int(path.get("dodge_start", -1000))
	var roll_distance: float = float(path.get("dodge_distance", 0.0))
	var problem = ""
	for age in range(mini(points.size(), duration + 1)):
		var point: Vector2 = points[age]
		var snapshot: Dictionary = runner.update(age, point)
		replayed_ticks += 1
		var roll_age: int = age - dodge_start
		var rolling: bool = roll_age >= 0 and roll_age < 24
		var invulnerable: bool = roll_age >= 3 and roll_age <= 14
		if not Geometry.in_arena(point, CENTER, RADII, 6.0):
			problem = "outside player-radius arena at t%d: %s" % [age, str(point)]
			break
		if not rolling and point.distance_to(snapshot.boss_pos) < 24.489:
			problem = "overlaps boss body at t%d: distance %.3f" % [age, point.distance_to(snapshot.boss_pos)]
			break
		if age > 0:
			var stride: float = point.distance_to(points[age - 1])
			var maximum_stride: float = roll_distance / 24.0 if rolling else MIN_SPEED / 60.0
			# A legal separation on the roll-exit tick is an intentional snap;
			# every ordinary walk and every roll movement must obey its speed.
			var separation: bool = roll_age == 24 and absf(point.distance_to(snapshot.boss_pos) - 24.5) < 0.005
			if stride > maximum_stride + 0.006 and not separation:
				problem = "exceeds minimum-build movement at t%d: %.4f > %.4f" % [age, stride, maximum_stride]
				break
		for hazard in snapshot.hazards:
			if hazard.phase == "active" and Geometry.contains(hazard, point, 6.0) and not invulnerable:
				problem = "unprotected live %s collision at t%d / roll age %d / %s" % [hazard.event_id, age, roll_age, str(point)]
				break
			if hazard.phase == "active" and hazard.shape in ["disk", "capsule", "corridor"] and runner.actual_id not in ["rings", "fractures"]:
				# A 22px test disk is the 6px body plus a 16px half-width
				# footpoint corridor. Ground remains excluded while rolling.
				if Geometry.contains(hazard, point, 22.0):
					problem = "less than a 32px clear footpoint corridor around %s at t%d" % [hazard.event_id, age]
					break
		if not problem.is_empty():
			break
	var route_label: String = label + " roll%.2f" % roll_distance if roll_distance > 0.0 else label
	_check(problem.is_empty(), route_label + " passes live hazards, speed, arena and body checks" + (": " + problem if not problem.is_empty() else ""))


func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures.append(message)
