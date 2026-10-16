extends SceneTree

## Run with: Godot --headless --path . --script res://tests/combat_tests.gd
## These checks exercise the combat clock through commands. Debug helpers only
## arrange otherwise rare states; normal damage, resources and outcomes use step.
const Model = preload("res://scripts/combat_model.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_movement()
	_test_arena_boundary()
	_test_dodge_window_and_distance()
	_test_dodge_damage_window()
	_test_dodge_priority_and_cooldown()
	_test_attack_cancel()
	_test_basic_hit_and_miss()
	_test_special_snapshots_and_damage()
	_test_pickup_does_not_attack()
	_test_pickup_invalidates_buffer()
	_test_pickup_and_press_same_tick()
	_test_buffer_priority()
	_test_pickup_lifecycle()
	_test_threshold_fire_release()
	_test_fire_total_and_refresh()
	_test_damage_batch_and_post_hit_immunity()
	_test_claw_timing_and_single_hit()
	_test_rupture_timing_and_side_escape()
	_test_pulse_ring_and_dodge()
	_test_shared_telegraph_geometry()
	_test_prototype_results()
	_test_reset()
	print("COMBAT TESTS: %d checks, %d failures" % [checks, failures.size()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _new_model():
	var m = Model.new()
	m.reset(137)
	m.boss_enabled = false
	m.player_pos = Vector2(280, 184)
	m.boss_pos = Vector2(400, 184)
	m.player_facing = Vector2.RIGHT
	return m


func _close_model():
	var m = _new_model()
	m.player_pos = Vector2(280, 184)
	m.boss_pos = Vector2(320, 184)
	return m


func _advance(m, count: int, move: Vector2 = Vector2.ZERO) -> void:
	for index in range(count):
		m.step({"move": move})


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
		print("FAIL: " + message)


func _near(actual: float, expected: float, message: String, tolerance: float = 0.002) -> void:
	_check(absf(actual - expected) <= tolerance,
		"%s (got %.4f, expected %.4f)" % [message, actual, expected])


func _test_movement() -> void:
	var horizontal = _new_model()
	var diagonal = _new_model()
	horizontal.player_pos = Vector2(320, 220)
	diagonal.player_pos = horizontal.player_pos
	horizontal.boss_pos = Vector2(200, 184)
	diagonal.boss_pos = horizontal.boss_pos
	var origin: Vector2 = horizontal.player_pos
	_advance(horizontal, 20, Vector2.RIGHT)
	_advance(diagonal, 20, Vector2(1, -1))
	_near(horizontal.player_pos.distance_to(origin), 32.0, "T01 movement is 96 px/s")
	_near(diagonal.player_pos.distance_to(origin), 32.0, "T01 diagonal speed is normalized")
	var facing: Vector2 = diagonal.player_facing
	_advance(diagonal, 3)
	_check(diagonal.player_facing.is_equal_approx(facing), "Facing remains when movement stops")


func _test_arena_boundary() -> void:
	var m = _new_model()
	m.player_pos = Vector2(320, 184)
	m.boss_pos = Vector2(180, 184)
	_advance(m, 250, Vector2.RIGHT)
	_check(m.player_pos.x <= 574.01, "T01 player radius is respected at the arena edge")
	var before: Vector2 = m.player_pos
	_advance(m, 20, Vector2(1, -1))
	_check(m.player_pos.y < before.y - 10.0, "T01 diagonal movement slides along the curved boundary")
	var normalized: Vector2 = (m.player_pos - Vector2(320, 184)) / Vector2(254, 120)
	_check(normalized.length_squared() <= 1.0002, "T01 boundary remains elliptical")


func _test_dodge_window_and_distance() -> void:
	var m = _new_model()
	var origin: Vector2 = m.player_pos
	m.step({"dodge": true, "move": Vector2.RIGHT})
	_check(m.player_state == "dodge" and m.state_age == 0, "Dodge begins at age zero")
	_check(not m.is_player_invulnerable(), "T02 dodge age 0 is vulnerable")
	_advance(m, 2)
	_check(not m.is_player_invulnerable(), "T02 dodge age 2 is vulnerable")
	_advance(m, 1)
	_check(m.is_player_invulnerable(), "T02 dodge age 3 starts invulnerability")
	_advance(m, 11)
	_check(m.is_player_invulnerable(), "T02 dodge age 14 remains invulnerable")
	_advance(m, 1)
	_check(not m.is_player_invulnerable(), "T02 dodge age 15 is vulnerable")
	_advance(m, 8)
	_near(m.player_pos.distance_to(origin), 72.0, "Dodge travels exactly 72 px in its 24 movement ticks")
	_advance(m, 1)
	_check(m.player_state != "dodge", "Dodge ends at age 24")


func _test_dodge_damage_window() -> void:
	for age in [2, 3, 14, 15]:
		var m = _new_model()
		m.step({"dodge": true})
		_advance(m, age - 1)
		m.debug_damage_player(10.0, "window")
		m.step()
		_near(m.player_hp, 100.0 if age == 3 or age == 14 else 90.0,
			"T02 real incoming damage at dodge age %d" % age)


func _test_dodge_priority_and_cooldown() -> void:
	var m = _new_model()
	m.stacks = 6
	m.fire_charges = 2
	m.step({"attack": true, "dodge": true})
	_check(m.player_state == "dodge", "T03 dodge wins simultaneous attack input")
	_check(m.stacks == 6 and m.fire_charges == 2, "T03 discarded attack consumes no resources")
	_advance(m, 24)
	m.step({"dodge": true})
	_advance(m, 15)
	_check(m.player_state != "dodge", "Early cooldown press does not schedule a much later dodge")
	_advance(m, 2)
	m.step({"dodge": true})
	_check(m.player_state == "dodge", "Dodge can restart after its 42-tick cooldown")


func _test_attack_cancel() -> void:
	var m = _new_model()
	m.step({"attack": true})
	_advance(m, 22)
	m.step({"dodge": true})
	_check(m.player_state == "attack", "Sword cannot dodge-cancel before age 24")
	m.step()
	_check(m.player_state == "dodge", "Buffered dodge cancels sword at age 24")


func _test_basic_hit_and_miss() -> void:
	var m = _close_model()
	m.step({"attack": true})
	_advance(m, 8)
	_near(m.boss_hp, 1000.0, "Sword startup has no early damage")
	m.step()
	_near(m.boss_hp, 982.0, "Sword first active tick applies 18 damage")
	_advance(m, 24)
	_near(m.boss_hp, 982.0, "T06 six active ticks do not repeat direct damage")
	_check(m.stacks == 1, "T06 one basic action generates exactly one stack")
	var missed = _new_model()
	missed.step({"attack": true})
	_advance(missed, 40)
	_near(missed.boss_hp, 1000.0, "Out-of-range basic attack misses")
	_check(missed.stacks == 0, "Missed basic attack generates no stacks")


func _test_special_snapshots_and_damage() -> void:
	var signature = _close_model()
	signature.stacks = 6
	_check(signature.next_attack_kind() == "signature", "Six stacks prepare signature")
	signature.step({"attack": true})
	_check(signature.stacks == 0, "Signature spends all stacks at startup")
	_advance(signature, 15)
	_near(signature.boss_hp, 960.4, "Signature direct damage is 18 x 2.2")
	_check(signature.stacks == 0, "Signature generates no stack")
	var fire = _close_model()
	fire.fire_charges = 2
	_check(fire.next_attack_kind() == "fire", "Fire charge changes the displayed next attack")
	fire.step({"attack": true})
	_check(fire.fire_charges == 1, "Fire spends one charge at startup")
	_advance(fire, 15)
	_near(fire.boss_hp, 975.7, "Fire direct damage is 18 x 1.35")
	_check(fire.stacks == 0, "Fire direct hit generates no stack")
	var resonance = _close_model()
	resonance.stacks = 6
	resonance.fire_charges = 2
	_check(resonance.next_attack_kind() == "resonance", "T07 both resources prepare resonance")
	resonance.step({"attack": true})
	_check(resonance.stacks == 0 and resonance.fire_charges == 1, "T07 resonance spends six stacks and exactly one charge")
	_advance(resonance, 15)
	_near(resonance.boss_hp, 946.54, "T07 resonance direct damage is 18 x 2.2 x 1.35")
	_check(resonance.stacks == 0, "Resonance generates no stack")
	for special in [signature, fire, resonance]:
		_advance(special, 18)
		_check(special.player_state != "attack", "Special attack retains the 33-tick sword duration")
	var snapshot = _close_model()
	snapshot.step({"attack": true})
	snapshot.debug_spawn_fire(snapshot.player_pos)
	snapshot.step()
	_advance(snapshot, 8)
	_near(snapshot.boss_hp, 982.0, "T05 fire pickup does not transform an already-started attack")
	_check(snapshot.fire_charges == 2, "Started basic attack preserves newly obtained fire charges")


func _test_pickup_does_not_attack() -> void:
	var m = _new_model()
	m.debug_spawn_fire(m.player_pos)
	m.step()
	_check(m.fire_charges == 2, "Grounded fire is collected in contact")
	_advance(m, 45)
	_check(m.player_state != "attack" and m.fire_charges == 2, "T04 pickup alone never starts or spends an attack")
	m.step({"attack": true})
	_check(m.player_state == "attack" and m.fire_charges == 1, "T04 fresh attack press uses collected fire")


func _test_pickup_invalidates_buffer() -> void:
	var m = _new_model()
	m.step({"attack": true})
	_advance(m, 27)
	m.step({"attack": true})
	m.debug_spawn_fire(m.player_pos)
	m.step()
	_advance(m, 12)
	_check(m.player_state != "attack", "T05 pickup discards an unstarted basic attack reservation")
	_check(m.fire_charges == 2, "T05 invalidated reservation cannot spend new fire")
	var retained = _new_model()
	retained.fire_charges = 2
	retained.step({"attack": true})
	_advance(retained, 27)
	retained.step({"attack": true})
	retained.debug_spawn_fire(retained.player_pos)
	retained.step()
	_advance(retained, 4)
	_check(retained.player_state == "attack" and retained.fire_charges == 1,
		"Same-kind fire refill preserves a legal attack reservation")


func _test_pickup_and_press_same_tick() -> void:
	var m = _new_model()
	m.debug_spawn_fire(m.player_pos)
	m.step({"attack": true})
	_check(m.player_state != "attack" and m.fire_charges == 2,
		"T05 pickup and press on the same tick require another fresh press")
	m.step({"attack": true})
	_check(m.player_state == "attack" and m.fire_charges == 1,
		"Next fresh press after pickup starts the intended fire attack")


func _test_buffer_priority() -> void:
	var m = _new_model()
	m.step({"attack": true})
	_advance(m, 22)
	m.queue_frozen_input({"dodge": true})
	m.queue_frozen_input({"attack": true})
	m.step()
	_check(m.player_state == "attack", "T26 frozen dodge respects the sword cancel point")
	m.step()
	_check(m.player_state == "dodge", "T26 frozen attack cannot replace a queued dodge")


func _test_pickup_lifecycle() -> void:
	var m = _new_model()
	m.debug_spawn_fire(m.player_pos, false)
	m.step()
	_check(m.fire_charges == 0, "Flying fire cannot be collected")
	_advance(m, 23)
	_check(m.fire_charges == 2, "Fire lands after 24 ticks and becomes collectible")
	var full = _new_model()
	full.fire_charges = 2
	full.debug_spawn_fire(full.player_pos)
	full.step()
	_check(full.pickups.size() == 1 and full.fire_charges == 2, "T08 full fire charge leaves pickup on the floor")
	var expiry = _new_model()
	expiry.debug_spawn_fire(Vector2(200, 184))
	_advance(expiry, 599)
	_check(expiry.pickups.size() == 1, "Fire remains until its 600-tick ground lifetime")
	expiry.step()
	_check(expiry.pickups.is_empty(), "Fire expires at its ground lifetime")
	var cap = _new_model()
	cap.debug_spawn_fire(Vector2(180, 184))
	cap.debug_spawn_fire(Vector2(200, 184))
	cap.debug_spawn_fire(Vector2(220, 184))
	_check(cap.pickups.size() == 2, "Third fire drop replaces the oldest of at most two pickups")


func _test_fire_total_and_refresh() -> void:
	var m = _new_model()
	m.debug_apply_fire()
	_advance(m, 29)
	_near(m.boss_hp, 1000.0, "T25 burn does not tick before +30")
	for index in range(4):
		m.step()
		_near(m.boss_hp, 1000.0 - 3.0 * float(index + 1), "T25 burn tick %d applies three damage" % (index + 1))
		if index < 3:
			_advance(m, 29)
	_advance(m, 60)
	_near(m.boss_hp, 988.0, "T25 burn deals exactly 12 including its +120 expiry tick")
	_check(m.stacks == 0, "Burn creates no weapon stacks")
	var refreshed = _new_model()
	refreshed.debug_apply_fire()
	_advance(refreshed, 20)
	refreshed.debug_apply_fire()
	_advance(refreshed, 10)
	_near(refreshed.boss_hp, 997.0, "Burn refresh does not postpone the next scheduled tick")
	_advance(refreshed, 120)
	_near(refreshed.boss_hp, 988.0, "Burn refresh extends one instance without stacking damage")


func _test_threshold_fire_release() -> void:
	var m = _close_model()
	for action in range(10):
		m.step({"attack": true})
		_advance(m, 33)
	_check(m.boss_hp < 800.0 and m.boss_hp > 750.0,
		"Normal sword attacks cross the first 20 percent drop threshold")
	_check(m.pickups.is_empty(), "Threshold crossing queues fire until a recovery starts")
	m.player_pos = Vector2(320, 280)
	m.boss_enabled = true
	m.debug_start_pattern("claw")
	_advance(m, 57)
	_check(m.pickups.size() == 1 and m.pickups[0].state == "flying",
		"Crossed threshold releases exactly one flying fire at the next recovery")
	if not m.pickups.is_empty():
		var destination: Vector2 = m.pickups[0].dest
		var distance: float = destination.distance_to(m.player_pos)
		_check(distance >= 32.0 and distance <= 80.0, "Released fire lands in the specified player distance band")
		_advance(m, 24)
		_check(m.pickups.size() == 1 and m.pickups[0].state == "grounded", "Released fire completes its 24-tick flight")
		_advance(m, 42)
		m.debug_start_pattern("claw")
		_advance(m, 57)
		_check(m.pickups.size() == 1, "A crossed threshold never releases a second copy in later recoveries")


func _test_damage_batch_and_post_hit_immunity() -> void:
	var m = _new_model()
	m.debug_damage_player(10.0, "small")
	m.debug_damage_player(28.0, "large")
	m.step()
	_near(m.player_hp, 72.0, "Same-tick incoming batch applies the greatest damage once")
	m.debug_damage_player(40.0, "immediate")
	m.step()
	_near(m.player_hp, 72.0, "Post-hit invulnerability rejects another damage event")
	_advance(m, 40)
	m.debug_damage_player(10.0, "after_immunity")
	m.step()
	_near(m.player_hp, 62.0, "Post-hit invulnerability expires after 42 ticks")


func _test_claw_timing_and_single_hit() -> void:
	var m = _close_model()
	m.boss_enabled = true
	m.player_pos = Vector2(360, 184)
	m.debug_start_pattern("claw")
	_advance(m, 50)
	_near(m.player_hp, 100.0, "Claw has its full 51-tick telegraph")
	m.step()
	_near(m.player_hp, 72.0, "Claw first active tick deals 28")
	_advance(m, 5)
	_near(m.player_hp, 72.0, "Claw active window applies damage only once")
	m.step()
	_check(m.boss_state == "recover", "Claw recovery starts at t57")
	var escape = _close_model()
	escape.boss_enabled = true
	escape.player_pos = Vector2(380, 184)
	escape.debug_start_pattern("claw")
	_advance(escape, 31)
	_advance(escape, 26, Vector2.UP)
	_near(escape.player_hp, 100.0, "Walking sideways after claw direction lock can evade it")


func _test_rupture_timing_and_side_escape() -> void:
	var m = _close_model()
	m.boss_enabled = true
	m.player_pos = Vector2(400, 184)
	m.debug_start_pattern("rupture")
	_advance(m, 119)
	_near(m.player_hp, 100.0, "Rupture has its full 120-tick telegraph")
	m.step()
	_near(m.player_hp, 60.0, "Rupture first active tick deals 40")
	_advance(m, 6)
	_check(m.boss_state == "recover", "Rupture recovery starts at t126")
	var escape = _close_model()
	escape.boss_enabled = true
	escape.player_pos = Vector2(400, 184)
	escape.debug_start_pattern("rupture")
	_advance(escape, 61)
	_advance(escape, 30, Vector2.UP)
	_advance(escape, 35)
	_near(escape.player_hp, 100.0, "Rupture can be avoided by walking beside its locked line")


func _test_pulse_ring_and_dodge() -> void:
	var inside = _close_model()
	inside.boss_enabled = true
	inside.player_pos = Vector2(400, 184)
	inside.debug_start_pattern("pulse")
	_advance(inside, 126)
	inside.player_pos = Vector2(344.5, 184)
	_advance(inside, 15)
	_near(inside.player_hp, 100.0, "Pulse is a ring rather than a damaging full disk")
	var crossed = _close_model()
	crossed.boss_enabled = true
	crossed.player_pos = Vector2(400, 184)
	crossed.debug_start_pattern("pulse")
	_advance(crossed, 121)
	crossed.step({"dodge": true, "move": Vector2.LEFT})
	_advance(crossed, 24)
	_near(crossed.player_hp, 100.0, "Pulse can be crossed inward with one normally timed dodge")
	var hit = _close_model()
	hit.boss_enabled = true
	hit.player_pos = Vector2(400, 184)
	hit.debug_start_pattern("pulse")
	_advance(hit, 145)
	_near(hit.player_hp, 70.0, "Standing in the expanding pulse path takes 30 damage once")


func _test_prototype_results() -> void:
	var win = _close_model()
	win.boss_hp = 18.0
	win.step({"attack": true})
	_advance(win, 9)
	_check(win.result == "prototype_complete" and win.player_hp > 0.0,
		"T27 surviving P1 kill ends with prototype_complete")
	var tick_at_result: int = win.tick
	var position_at_result: Vector2 = win.player_pos
	win.step({"attack": true, "dodge": true, "move": Vector2.RIGHT})
	_check(win.tick == tick_at_result and win.player_pos == position_at_result,
		"Result stops combat updates and further inputs")
	var draw = _close_model()
	draw.boss_hp = 18.0
	draw.player_hp = 28.0
	draw.step({"attack": true})
	_advance(draw, 8)
	draw.debug_damage_player(28.0, "simultaneous")
	draw.step()
	_check(draw.boss_hp <= 0.0 and draw.player_hp <= 0.0 and draw.result == "dead",
		"T27 simultaneous prototype death resolves as failure")
	var dead = _new_model()
	dead.debug_damage_player(100.0, "test_death")
	dead.step()
	_check(dead.result == "dead" and not dead.cause.is_empty(), "Death records a readable damage cause")


func _test_shared_telegraph_geometry() -> void:
	for pattern in ["claw", "rupture", "pulse"]:
		var m = _close_model()
		m.boss_enabled = true
		m.player_pos = Vector2(400, 184)
		m.debug_start_pattern(pattern)
		var locked_age: int = 31 if pattern == "claw" else (61 if pattern == "rupture" else 1)
		var active_age: int = 51 if pattern == "claw" else 120
		_advance(m, locked_age)
		var preview: Dictionary = m.hazards[0].duplicate(true)
		_advance(m, active_age - locked_age)
		var active: Dictionary = m.hazards[0]
		var same_geometry: bool = true
		for key in ["shape", "origin", "facing", "radius", "width", "length", "arc_radians"]:
			same_geometry = same_geometry and preview[key] == active[key]
		_check(preview.phase == "telegraph" and active.phase == "active" and same_geometry,
			"%s telegraph and first damage event share exactly the same geometry" % pattern)
	var locked = _close_model()
	locked.boss_enabled = true
	locked.player_pos = Vector2(360, 184)
	locked.debug_start_pattern("claw")
	_advance(locked, 30)
	var locked_facing: Vector2 = locked.boss_facing
	locked.player_pos = Vector2(320, 244)
	locked.step()
	_check(locked.boss_facing.is_equal_approx(locked_facing), "Claw cannot turn after its t30 direction lock")


func _test_reset() -> void:
	var m = _new_model()
	m.stacks = 6
	m.fire_charges = 2
	m.debug_spawn_fire(Vector2(200, 184))
	m.debug_damage_player(100.0, "test_death")
	m.step()
	m.reset(137)
	_check(m.result.is_empty() and m.player_hp == 100.0 and m.boss_hp == 1000.0,
		"Retry resets result and both health pools")
	_check(m.stacks == 0 and m.fire_charges == 0 and m.pickups.is_empty(),
		"Retry resets stacks, fire and ground objects")
