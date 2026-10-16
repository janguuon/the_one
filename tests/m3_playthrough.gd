extends SceneTree
## End-to-end normal-input policy. Never injects health, damage, positions,
## resources or phase skips. Certificates are routes derived from telegraphs.
const Combat = preload("res://scripts/combat_model.gd")
const Geometry = preload("res://scripts/combat_geometry.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failure = false
	for run_seed in [1, 2, 7]:
		var game = Combat.new()
		game.reset(run_seed, "official")
		var kinds: Dictionary = {}
		var patterns: Dictionary = {}
		for iteration in range(150000):
			if game.result != "":
				break
			var command = decide(game)
			game.step(command)
			patterns[game.boss_pattern] = true
			for event in game.events:
				if event.type == "attack":
					kinds[event.kind] = true
				elif event.type == "player_hit":
					print("HIT seed=%d phase=%d pattern=%s age=%d hp=%.1f pos=%s command=%s" % [run_seed,game.phase_id,game.boss_pattern,game.boss_age,game.player_hp,str(game.player_pos),str(command)])
				elif event.type == "phase_reached":
					print("REACHED seed=%d phase=%d tick=%d hp=%.1f" % [run_seed,game.phase_id,game.tick,game.player_hp])
		print("M3_PLAYTHROUGH seed=%d result=%s ticks=%d hp=%.1f damage=%.3f history=%s patterns=%d kinds=%s elements=%s" % [run_seed,game.result,game.tick,game.player_hp,game.damage_dealt,str(game.phase_history),patterns.size(),str(kinds.keys()),str(game.collected_elements)])
		if game.result != "victory" or game.phase_history != [1,2,3,4,5] or absf(game.damage_dealt - 6000.0) > 0.002:
			failure = true
	quit(1 if failure else 0)

static func decide(game, collect_pickups: bool = true) -> Dictionary:
	if game.selection_pending:
		game.choose_oath("")
		return {}
	if game.transition_ticks_remaining > 0:
		return {}
	var radial: Vector2 = (game.player_pos - game.boss_pos).normalized()
	if radial.length_squared() < 0.001:
		radial = Vector2.DOWN
	var distance: float = game.player_pos.distance_to(game.boss_pos)
	var desired_distance: float = {"W01":38.0,"W02":58.0,"W03":30.0,"W04":36.0,"W05":50.0}[game.weapon_id]
	var target: Vector2 = game.boss_pos + radial * desired_distance
	var dodge = false
	var dodge_direction = -radial
	var safe_attack = game.boss_state == "recover"
	var age: int = game.boss_age
	var pattern: String = game.boss_pattern
	var certificate: Dictionary = {}
	if not safe_attack and game.boss_state != "approach":
		var paths: Array = game.pattern_runner.safety.get("paths", [])
		if not paths.is_empty() and pattern in ["territory","rings","horizon","dash","fractures","last_horizon","footprints"]:
			certificate = paths[0]
			if pattern == "last_horizon":
				for candidate in paths:
					if absf(float(candidate.get("dodge_distance", 0)) - game.dodge_distance()) < 0.001:
						certificate = candidate
			var relative_age = age + 1
			if pattern == "footprints":
				var latest = 0
				for hazard in game.hazards:
					latest = maxi(latest, int(hazard.get("preview_tick", 0)))
				relative_age -= latest
			var positions: Array = certificate.get("positions", [])
			if not positions.is_empty():
				target = positions[mini(relative_age, positions.size() - 1)]
			if pattern == "last_horizon" and age + 1 == int(certificate.get("dodge_start", -100)):
				dodge = true
				dodge_direction = certificate.dodge_direction
		elif pattern == "claw":
			dodge = age >= 45 and age <= 50 and distance < 80.0
		elif pattern == "rupture" or pattern == "thrust":
			var lock_tick: int = int(game.data.patterns[pattern].lock_tick)
			if age >= lock_tick:
				target = _sidestep_line(game)
		elif pattern == "heartbeat" or pattern == "execution":
			dodge = ((age >= 42 and age <= 47) or (age >= 135 and age <= 140)) and distance < 80.0
			if pattern == "execution" and age >= 207:
				target = _sidestep_line(game)
		elif pattern == "echo" or pattern == "nameless_end":
			dodge = age >= 45 and age <= 50 and distance < 80.0
			if pattern == "nameless_end" and age >= 192:
				target = _sidestep_line(game)
		elif pattern == "pulse":
			if game.boss_state == "telegraph":
				target = game.boss_pos + radial * 80.0
			else:
				var radius = 28.0 + 4.0 * (age - 120)
				if radius < distance - 42.0:
					target = game.boss_pos + radial * 80.0
				elif radius <= distance + 12.0:
					dodge = true
				else:
					safe_attack = true
	# Stable ground-pattern safe points can provide attacks before recovery.
	if pattern == "territory" and not certificate.is_empty() and game.player_pos.distance_to(target) < 2.0:
		safe_attack = true
	if safe_attack and game.element_charges == 0 and collect_pickups:
		var remaining = game.pattern_runner.duration - age
		for pickup in game.pickups:
			if pickup.state == "grounded" and game.player_pos.distance_to(pickup.pos) < 52.0 and remaining > 42:
				target = pickup.pos
				safe_attack = false
				break
	var movement: Vector2 = (target - game.player_pos) * 60.0 / game.move_speed()
	movement = movement.limit_length(1.0)
	if dodge:
		movement = dodge_direction
	var remaining = game.pattern_runner.duration - age
	var weapon: Dictionary = game.weapon_definition()
	var duration = int(weapon.startup_ticks) + int(weapon.active_ticks) + int(weapon.recovery_ticks)
	var attack_now = safe_attack and distance <= float(weapon.reach) + float(game.data.boss.hurt_radius) - 9.0 and remaining >= duration + 1 and game.player_state in ["idle","move"]
	if game.weapon_id == "W05" and distance < 36.0:
		attack_now = false
	if attack_now:
		movement = -radial
	return {"move":movement,"attack":attack_now,"dodge":dodge and game.player_state != "dodge" and game.tick + 1 >= game.next_dodge_tick}

static func _sidestep_line(game) -> Vector2:
	var side: Vector2 = game.boss_facing.orthogonal()
	var offset: float = (game.player_pos - game.boss_pos).dot(side)
	var best: Vector2 = game.player_pos
	var best_distance = INF
	for sign_value in [-1.0, 1.0]:
		var candidate: Vector2 = game.clamp_position(game.player_pos + side * (sign_value * 26.0 - offset))
		if absf((candidate - game.boss_pos).dot(side)) < 23.0:
			continue
		var distance: float = candidate.distance_squared_to(game.player_pos)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best
