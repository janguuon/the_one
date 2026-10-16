extends SceneTree
## Normal stats / normal commands / no debug damage or invulnerability.
const Combat = preload("res://scripts/combat_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failed = false
	for run_seed in [1, 2, 3, 7, 19]:
		var game = Combat.new()
		game.reset(run_seed)
		var observed: Dictionary = {}
		for iteration in range(36000):
			if not game.result.is_empty():
				break
			var command = _decide(game)
			game.step(command)
			for event in game.events:
				if event.type == "attack":
					observed[event.kind] = true
				if event.type == "player_hit":
					print("  HIT seed=%d t=%d pattern=%s age=%d distance=%.1f hp=%.1f command=%s" % [run_seed, game.tick, game.boss_pattern, game.boss_age, game.player_pos.distance_to(game.boss_pos), game.player_hp, str(command)])
		print("PLAYTHROUGH seed=%d result=%s ticks=%d hp=%.3f boss=%.3f attacks=%d fire=%d kinds=%s" % [run_seed, game.result, game.tick, game.player_hp, game.boss_hp, game.total_attacks, game.collected_fire, str(observed.keys())])
		if game.result != "prototype_complete" or game.player_hp <= 0.0:
			failed = true
		if not observed.has("signature") or not observed.has("fire"):
			failed = true
	# A stationary player must lose under the same normal damage rules.
	var idle = Combat.new()
	for iteration in range(6000):
		idle.step()
		if idle.result != "":
			break
	print("IDLE_LOSS result=%s hp=%.1f cause=%s" % [idle.result, idle.player_hp, idle.cause])
	if idle.result != "dead":
		failed = true
	quit(1 if failed else 0)

func _decide(game) -> Dictionary:
	var radial: Vector2 = (game.player_pos - game.boss_pos).normalized()
	if radial.length_squared() < 0.01:
		radial = Vector2.DOWN
	var distance: float = game.player_pos.distance_to(game.boss_pos)
	var target: Vector2 = game.boss_pos + radial * 38.0
	var wants_dodge = false
	var safe_attack = false
	if game.boss_state == "approach":
		safe_attack = true
	elif game.boss_state == "recover":
		safe_attack = true
	elif game.boss_pattern == "claw":
		if game.boss_age >= 45 and game.boss_age <= 50 and distance < 80.0:
			wants_dodge = true
	elif game.boss_pattern == "rupture":
		if game.boss_age >= 60 and game.boss_age < 126:
			target = game.boss_pos + game.boss_facing.orthogonal() * 40.0
	elif game.boss_pattern == "pulse":
		if game.boss_state == "telegraph":
			target = game.boss_pos + radial * 80.0
		else:
			var radius: float = float(game.data.patterns.pulse.radius) + float(game.data.patterns.pulse.speed) * (game.boss_age - 120) / 60.0
			if radius < distance - 42.0:
				target = game.boss_pos + radial * 80.0
			elif radius <= distance + 12.0:
				wants_dodge = true
			else:
				safe_attack = true
	# Collect only between direct attacks or after a wave has passed.
	if safe_attack and game.fire_charges < 2:
		for pickup in game.pickups:
			if pickup.state == "grounded":
				target = pickup.pos
				safe_attack = false
				break
	var movement: Vector2 = target - game.player_pos
	if movement.length() < 2.0:
		movement = Vector2.ZERO
	else:
		movement = movement.normalized()
	if wants_dodge:
		movement = -radial
	var attack_now = safe_attack and distance <= 47.0 and (game.player_state == "idle" or game.player_state == "move")
	# Reorient before striking; aim correction is deliberately limited.
	if attack_now:
		movement = -radial
	return {"move": movement, "attack": attack_now, "dodge": wants_dodge and game.player_state != "dodge" and game.tick + 1 >= game.next_dodge_tick}
