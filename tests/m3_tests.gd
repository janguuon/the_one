extends SceneTree

## M3 rules checked at their public simulation boundary. Debug commands arrange
## rare simultaneous states; the normal step still applies damage and outcomes.
const Model = preload("res://scripts/combat_model.gd")
const Patterns = preload("res://scripts/boss_patterns.gd")
const Profile = preload("res://scripts/practice_profile.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_mode_and_phase_health()
	_test_phase_transition()
	_test_transition_cleanup_and_input()
	_test_mode_outcome_priority()
	_test_all_elements()
	_test_element_pickup_rules()
	_test_element_attack_snapshots()
	_test_frost_guard()
	_test_phase_threshold_drops()
	_test_all_pattern_timings()
	_test_echo_and_footprints_snapshots()
	_test_event_immunity_and_later_hits()
	_test_heartbeat_one_dodge_for_two_hits()
	_test_phase_bags_and_first_patterns()
	_test_practice_profile_recovery()
	_test_director_deferred_bag()
	_test_director_waits_for_roll_exit()
	_test_dash_swept_collision_before_body_separation()
	print("M3 TESTS: %d checks, %d failures" % [checks, failures.size()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _model(run_mode: String = "prototype", phase: int = 1):
	var m = Model.new()
	m.reset(137, run_mode, phase)
	m.boss_enabled = false
	m.player_pos = Vector2(280, 184)
	m.boss_pos = Vector2(320, 184)
	m.player_facing = Vector2.RIGHT
	return m


func _advance(m, count: int, movement: Vector2 = Vector2.ZERO) -> void:
	for index in range(count):
		if m.selection_pending:
			m.choose_oath("") # M3 regression deliberately skips M4 build choices.
		m.step({"move": movement})


func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures.append(message)


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= 0.002,
		"%s (got %.3f, expected %.3f)" % [message, actual, expected])


func _attack_hit(m) -> void:
	m.step({"attack": true})
	_advance(m, 9)


func _test_mode_and_phase_health() -> void:
	var healths = [1000.0, 1100.0, 1200.0, 1300.0, 1400.0]
	for phase in range(1, 6):
		var practice = _model("practice", phase)
		_check(practice.mode == "practice" and practice.phase_id == phase,
			"Practice starts exactly the selected P%d" % phase)
		_near(practice.boss_hp, healths[phase - 1], "P%d independent health pool" % phase)
		_near(practice.phase_hp_max, healths[phase - 1], "P%d health denominator" % phase)
		_check(practice.player_hp == 100.0 and practice.stacks == 0
			and practice.element_charges == 0, "P%d practice starts without combat resources" % phase)
	var old = _model()
	_check(old.mode == "prototype" and old.phase_id == 1, "Default reset preserves the P1 prototype contract")


func _test_phase_transition() -> void:
	var m = _model("official")
	for expected in range(2, 6):
		m.player_pos = Vector2(280, 184)
		m.boss_pos = Vector2(320, 184)
		m.player_facing = Vector2.RIGHT
		m.boss_hp = 1.0
		m.player_hp = 80.0
		_attack_hit(m)
		_check(m.result.is_empty() and m.transition_ticks_remaining > 0,
			"P%d kill begins one transition instead of ending the official run" % (expected - 1))
		_near(m.player_hp, 95.0, "P%d transition restores exactly 15 health" % (expected - 1))
		_advance(m, 90)
		_check(m.player_pos == Vector2(320, 280) and m.boss_pos == Vector2(320, 135),
			"The 90-tick transition relocates both actors to clear starting positions")
		_check(m.phase_id == expected and m.transition_ticks_remaining == 60,
			"The next phase is reached before its full 60-tick restart warning")
		_advance(m, 59)
		_check(m.transition_ticks_remaining == 1, "Transition preserves all 90 animation and 60 restart ticks")
		m.step()
		_check(m.phase_id == expected and m.highest_phase_reached == expected,
			"Official transition reaches and unlocks P%d exactly once" % expected)
		_near(m.boss_hp, 900.0 + float(expected) * 100.0,
			"P%d begins at full health; excess damage never carries over" % expected)
		_check(m.transition_ticks_remaining == 0, "Transition ends after exactly 150 ticks")
		m.boss_enabled = false
	_advance(m, 5)
	_check(m.phase_id == 5 and m.result.is_empty(), "No unintended P6 or repeated transition appears")
	var capped = _model("official")
	capped.boss_hp = 1.0
	capped.player_hp = 96.0
	_attack_hit(capped)
	_near(capped.player_hp, 100.0, "Transition heal respects maximum health")


func _test_transition_cleanup_and_input() -> void:
	var m = _model("official")
	m.stacks = 6
	m.element_id = "lightning"
	m.element_charges = 3
	m.debug_spawn_element("void", Vector2(200, 184))
	m.debug_apply_fire()
	m.fire_next_tick = m.tick + 30
	m.frost_guard_until = m.tick + 180
	m.boss_hp = 1.0
	m.boss_enabled = true
	m.debug_start_pattern("echo")
	_attack_hit(m)
	_check(m.transition_ticks_remaining > 0, "A live pattern can end directly into transition")
	_check(m.attack.is_empty() and m.hazards.is_empty() and m.pickups.is_empty(),
		"T13 transition clears ongoing attacks, echoes, hazards and floor pickups")
	_check(m.fire_next_tick < 0 and m.fire_expires_tick < 0 and m.frost_guard_until <= m.tick,
		"T13 transition removes burn schedule and frost guard")
	_check(m.element_id == "lightning" and m.element_charges == 2 and m.stacks == 0,
		"Transition preserves remaining held element after the finishing resonance")
	m.stacks = 4
	var charges: int = m.element_charges
	var health: float = m.player_hp
	for index in range(149):
		if m.selection_pending:
			m.choose_oath("")
		m.debug_damage_player(45.0, "transition_attempt")
		m.step({"attack": true, "dodge": true})
	_check(m.player_hp == health and m.stacks == 4 and m.element_charges == charges,
		"Transition rejects damage and action resource consumption")
	m.step({"attack": true, "dodge": true})
	_check(m.pending_input.is_empty() and m.attack.is_empty(),
		"Transition boundary discards old or same-boundary action presses")
	m.boss_enabled = false
	m.step({"attack": true})
	_check(m.player_state == "attack" and m.element_charges == charges - 1,
		"Fresh input after restart can spend a preserved element")


func _test_mode_outcome_priority() -> void:
	for phase in range(1, 6):
		var practice = _model("practice", phase)
		practice.boss_hp = 18.0
		practice.player_hp = 28.0
		practice.step({"attack": true})
		_advance(practice, 8)
		practice.debug_damage_player(28.0, "simultaneous")
		practice.step()
		_check(practice.result == "practice_complete" and practice.phase_id == phase
			and practice.transition_ticks_remaining == 0,
			"T18 selected P%d practice completes on a draw without advancing" % phase)
		_check(practice.highest_phase_reached == 1,
			"T18 practice P%d never creates an official phase unlock" % phase)
	for phase in range(1, 6):
		var official = _model("official")
		official.phase_id = phase
		official.phase_hp_max = 900.0 + float(phase) * 100.0
		official.boss_hp = 18.0
		official.player_hp = 28.0
		official.step({"attack": true})
		_advance(official, 8)
		official.debug_damage_player(28.0, "simultaneous")
		official.step()
		_check(official.result == ("victory" if phase == 5 else "dead"),
			"T17 official P%d simultaneous death uses the specified priority" % phase)
		_check(official.transition_ticks_remaining == 0, "A simultaneous terminal result never starts a transition")
	var prototype = _model()
	prototype.boss_hp = 18.0
	_attack_hit(prototype)
	_check(prototype.result == "prototype_complete" and prototype.phase_id == 1,
		"T27 prototype P1 still ends at its own completion result")
	var terminal_tick: int = prototype.tick
	prototype.step({"attack": true})
	_check(prototype.tick == terminal_tick, "Terminal outcomes stop further combat ticks")


func _test_all_elements() -> void:
	var cases = [["fire", 2, 1.35], ["frost", 1, 1.8], ["lightning", 3, 1.15], ["void", 1, 2.1]]
	for entry in cases:
		var m = _model()
		m.debug_spawn_element(entry[0], m.player_pos)
		m.step()
		_check(m.element_id == entry[0] and m.element_charges == entry[1]
			and m.next_attack_kind() == entry[0], "%s pickup sets the correct next attack and charge count" % entry[0])
		_attack_hit(m)
		_near(m.boss_hp, 1000.0 - 18.0 * float(entry[2]), "%s direct damage multiplier" % entry[0])
		_check(m.element_charges == int(entry[1]) - 1 and m.stacks == 0,
			"%s spends one charge and creates no weapon stack" % entry[0])
		_advance(m, 24)
		_check(m.player_state != "attack", "%s retains the 33-tick sword duration" % entry[0])
		var resonance = _model()
		resonance.stacks = 6
		resonance.element_id = entry[0]
		resonance.element_charges = int(entry[1])
		_attack_hit(resonance)
		_near(resonance.boss_hp, 1000.0 - 18.0 * 2.2 * float(entry[2]), "%s resonance damage composes both multipliers" % entry[0])
		_check(resonance.stacks == 0 and resonance.element_charges == int(entry[1]) - 1,
			"%s resonance spends one charge and all six stacks" % entry[0])
	var reach = _model()
	reach.player_pos = Vector2(246, 184)
	reach.element_id = "lightning"
	reach.element_charges = 3
	_attack_hit(reach)
	_near(reach.boss_hp, 979.3, "Lightning reaches a boss 74px away through its +20px reach")
	var basic = _model()
	basic.player_pos = Vector2(246, 184)
	_attack_hit(basic)
	_near(basic.boss_hp, 1000.0, "The same 74px target remains outside a basic sword attack")


func _test_element_pickup_rules() -> void:
	var m = _model()
	m.element_id = "frost"
	m.element_charges = 1
	m.debug_spawn_element("void", m.player_pos)
	m.step()
	_check(m.pickups.size() == 1 and m.element_id == "frost" and m.element_charges == 1,
		"T08 a different element remains grounded while another is held")
	m.debug_spawn_element("frost", m.player_pos)
	m.step()
	_check(m.pickups.size() == 2, "T08 a full matching element also remains grounded")
	var refill = _model()
	refill.element_id = "lightning"
	refill.element_charges = 1
	refill.debug_spawn_element("lightning", refill.player_pos)
	refill.step()
	_check(refill.element_charges == 3 and refill.pickups.is_empty(), "Matching pickup refills charges to its cap")
	var order = _model()
	order.debug_spawn_element("void", order.player_pos)
	order.debug_spawn_element("fire", order.player_pos)
	order.step()
	_check(order.element_id == "void" and order.pickups.size() == 1,
		"Simultaneous grounded contacts choose older creation ID then preserve the other type")
	var landing_order = _model()
	landing_order.debug_spawn_element("void", landing_order.player_pos, false)
	_advance(landing_order, 23)
	landing_order.debug_spawn_element("fire", landing_order.player_pos)
	landing_order.step()
	_check(landing_order.element_id == "fire" and landing_order.pickups.size() == 1,
		"Earlier landing time wins simultaneous contact even when a newer landing has the lower creation ID")
	for element in ["frost", "lightning", "void"]:
		var flying = _model()
		flying.debug_spawn_element(element, flying.player_pos, false)
		_advance(flying, 23)
		_check(flying.element_charges == 0, "%s cannot be collected before its 24-tick landing" % element)
		flying.step()
		_check(flying.element_id == element, "%s is collectible on its landing tick" % element)


func _test_element_attack_snapshots() -> void:
	var m = _model()
	m.step({"attack": true})
	_advance(m, 27)
	m.step({"attack": true})
	m.debug_spawn_element("void", m.player_pos)
	m.step()
	_advance(m, 10)
	_check(m.pending_input.is_empty() and m.player_state != "attack" and m.element_charges == 1,
		"T05 new void pickup invalidates a buffered basic attack")
	var started = _model()
	started.step({"attack": true})
	started.debug_spawn_element("frost", started.player_pos)
	_advance(started, 9)
	_near(started.boss_hp, 982.0, "An already started basic attack keeps its damage snapshot after frost pickup")
	_check(started.element_id == "frost" and started.element_charges == 1,
		"A new frost charge is preserved by the in-progress basic attack")
	var key = _model()
	key.stacks = 6
	key.element_id = "fire"
	key.element_charges = 1
	var fire_key: String = key.next_attack_key()
	key.element_id = "void"
	_check(fire_key != key.next_attack_key(), "Resonance reservation key includes the held element identity")


func _test_frost_guard() -> void:
	var m = _model()
	m.element_id = "frost"
	m.element_charges = 1
	_attack_hit(m)
	_check(m.frost_guard_until == m.tick + 180, "Frost guard starts on an actual hit for 180 ticks")
	m.debug_damage_player(25.0, "guarded")
	m.step()
	_near(m.player_hp, 80.0, "Frost guard reduces exactly the next valid incoming hit by 20 percent")
	_check(m.frost_guard_until <= m.tick, "A reduced hit consumes frost guard once")
	var miss = _model()
	miss.boss_pos = Vector2(420, 184)
	miss.element_id = "frost"
	miss.element_charges = 1
	_attack_hit(miss)
	_check(miss.frost_guard_until <= miss.tick, "A missed frost attack creates no guard")
	var simultaneous = _model()
	simultaneous.element_id = "frost"
	simultaneous.element_charges = 1
	simultaneous.step({"attack": true})
	_advance(simultaneous, 8)
	simultaneous.debug_damage_player(25.0, "same_tick")
	simultaneous.step()
	_near(simultaneous.player_hp, 75.0, "New frost guard never retroactively reduces the hit on its creation tick")
	_check(simultaneous.frost_guard_until > simultaneous.tick, "Same-tick frost hit leaves its new guard available for a later hit")
	var invulnerable = _model()
	invulnerable.frost_guard_until = 180
	invulnerable.step({"dodge": true})
	_advance(invulnerable, 2)
	invulnerable.debug_damage_player(25.0, "dodged")
	invulnerable.step()
	_check(invulnerable.player_hp == 100.0 and invulnerable.frost_guard_until == 180,
		"An invulnerable rejected hit cannot consume frost guard")
	var expired = _model()
	expired.frost_guard_until = 180
	_advance(expired, 179)
	expired.debug_damage_player(25.0, "expired")
	expired.step()
	_near(expired.player_hp, 75.0, "Frost guard expires at its 180-tick deadline")


func _test_phase_threshold_drops() -> void:
	for phase in range(1, 5):
		var m = _model("practice", phase)
		var expected: String = ["fire", "frost", "lightning", "void"][phase - 1]
		m.boss_hp = float(m.phase_hp_max) * 0.80 + 1.0
		_attack_hit(m)
		_check(m.pickups.is_empty(), "P%d threshold queues its element until recovery" % phase)
		m.player_pos = Vector2(320, 280)
		m.boss_enabled = true
		m.debug_start_pattern("claw")
		_advance(m, 57)
		_check(m.pickups.size() == 1 and m.pickups[0].element == expected,
			"P%d recovery releases its own %s element" % [phase, expected])


func _test_all_pattern_timings() -> void:
	var expected = {
		"claw": [51], "rupture": [120], "pulse": [120],
		"territory": [120], "rings": [120, 177], "horizon": [132],
		"heartbeat": [48, 81, 141], "dash": [120, 177, 234], "thrust": [96],
		"echo": [51, 111], "footprints": [120, 144, 168], "fractures": [120, 177, 234, 291],
		"execution": [48, 81, 141, 267], "last_horizon": [120, 240], "nameless_end": [51, 111, 213]
	}
	for id in expected:
		var runner = Patterns.new()
		var rng = RandomNumberGenerator.new()
		rng.seed = 137
		runner.start(id, Vector2(320, 135), Vector2(320, 195), rng)
		var started: Array[int] = []
		var previews: Dictionary = {}
		var active_ids: Dictionary = {}
		var shared: bool = true
		var stable: bool = true
		for age in range(0, int(expected[id].back()) + 7):
			var snapshot: Dictionary = runner.update(age, Vector2(320, 195))
			for hazard in snapshot.hazards:
				var event_id: String = str(hazard.event_id)
				if hazard.phase == "telegraph":
					previews[event_id] = hazard.duplicate(true)
				elif hazard.phase == "active":
					if not active_ids.has(event_id):
						active_ids[event_id] = age
						if not started.has(age):
							started.append(age)
						if not previews.has(event_id):
							shared = false
						else:
							# A dash previews its full route, then damages only the
							# moving swept segment; already crossed ground is safe.
							for property in (["shape", "facing", "width"] if id == "dash" else ["shape", "origin", "facing", "radius", "width", "length", "arc_radians"]):
								if previews[event_id].get(property) != hazard.get(property):
									shared = false
					else:
						stable = stable and int(hazard.start_tick) == int(active_ids[event_id])
		started.sort()
		_check(runner.actual_id == id and runner.safety_error.is_empty(), "%s has a legal standard-position pattern" % id)
		_check(started == expected[id], "%s first active events follow exact documented ticks: %s" % [id, str(started)])
		_check(shared, "%s telegraphs share their first-active event geometry" % id)
		_check(stable, "%s active windows retain stable hit-event IDs" % id)


func _test_echo_and_footprints_snapshots() -> void:
	var m = _model("practice", 4)
	m.boss_enabled = true
	m.player_pos = Vector2(360, 184)
	m.debug_start_pattern("echo")
	_advance(m, 31)
	var original_origin: Vector2 = m.boss_pos
	var original_facing: Vector2 = m.boss_facing
	m.boss_pos = Vector2(240, 184)
	m.player_pos = Vector2(320, 240)
	_advance(m, 80)
	var echo_found = false
	for hazard in m.hazards:
		if hazard.phase == "active":
			echo_found = true
			_check(hazard.origin == original_origin and hazard.facing == original_facing,
				"T15 the echo uses its recorded origin and direction after the boss is moved")
	_check(echo_found, "T15 the stored echo actually executes at t111")
	var runner = Patterns.new()
	var rng = RandomNumberGenerator.new()
	rng.seed = 137
	runner.start("footprints", Vector2(320, 135), Vector2(280, 220), rng)
	var count_before = 0
	for age in range(0, 49):
		var snapshot: Dictionary = runner.update(age, Vector2(280.0 + age * 1.5, 220))
		var count: int = snapshot.hazards.size()
		if age in [0, 24, 48]:
			_check(count == count_before + 1, "Footprints records one visible new snapshot at t%d" % age)
		elif age < 48:
			_check(count == count_before, "Footprints does not preview an unrecorded future position at t%d" % age)
		count_before = count


func _test_event_immunity_and_later_hits() -> void:
	var m = _model("practice", 2)
	m.player_pos = Vector2(360, 184)
	m.boss_enabled = true
	m.debug_start_pattern("territory")
	_advance(m, 120)
	var first_health: float = m.player_hp
	_check(first_health < 100.0, "A player remaining inside a territory receives its first damage")
	_advance(m, 100)
	_near(m.player_hp, first_health, "A long territory event cannot hit the same player again after immunity expires")
	var separate = _model("practice", 2)
	separate.player_pos = Vector2(350, 184)
	separate.boss_enabled = true
	separate.debug_start_pattern("rings")
	_advance(separate, 120)
	_near(separate.player_hp, 72.0, "First ring event hits its inner disk once")
	separate.player_pos = Vector2(420, 184)
	_advance(separate, 57)
	_near(separate.player_hp, 44.0, "Second ring uses a distinct hit-event ID after damage immunity ends")


func _test_heartbeat_one_dodge_for_two_hits() -> void:
	var m = _model("practice", 3)
	m.player_pos = Vector2(360, 184)
	m.boss_enabled = true
	m.debug_start_pattern("heartbeat")
	_advance(m, 40)
	m.step({"dodge": true, "move": Vector2.LEFT})
	_advance(m, 45)
	_check(m.player_pos.x < m.boss_pos.x and m.player_hp == 100.0,
		"T14 one normal dodge crosses behind the boss and avoids both t48/t81 swings")
	_check(m.next_dodge_tick < m.tick, "The first two heartbeat hits require no second dodge cooldown")


func _test_phase_bags_and_first_patterns() -> void:
	var first = ["claw", "rings", "heartbeat", "echo", "execution"]
	var available = [
		["claw", "rupture", "pulse"], ["territory", "rings", "horizon"],
		["heartbeat", "dash", "thrust"], ["echo", "footprints", "fractures"],
		["execution", "last_horizon", "nameless_end"]
	]
	for phase in range(1, 6):
		var m = _model("practice", phase)
		m.boss_enabled = true
		m.player_pos = Vector2(320, 280)
		m.boss_pos = Vector2(320, 135)
		var seen: Array[String] = []
		# This selection-only test supplies an outer legal position and clears
		# incidental incoming damage. It is not a full-play survivability test.
		for index in range(7000):
			m.player_pos = Vector2(320, 280)
			m.player_hp = 100.0
			m.step()
			if m.pattern_history.size() >= 9:
				break
		seen = m.pattern_history.duplicate()
		_check(not seen.is_empty() and seen[0] == first[phase - 1], "P%d starts with its fixed introductory pattern" % phase)
		var legal = seen.size() >= 9
		var no_repeat = true
		for index in range(seen.size()):
			legal = legal and available[phase - 1].has(seen[index])
			if index > 0:
				no_repeat = no_repeat and seen[index] != seen[index - 1]
		_check(legal and no_repeat, "T24 P%d selects only its phase patterns without consecutive repeats" % phase)
		if seen.size() >= 9:
			for offset in [0, 3, 6]:
				var bag = seen.slice(offset, offset + 3)
				bag.sort()
				var sorted_expected: Array = available[phase - 1].duplicate()
				sorted_expected.sort()
				_check(bag == sorted_expected, "P%d shuffle bag %d contains all three patterns once" % [phase, offset / 3 + 1])


func _test_practice_profile_recovery() -> void:
	var path = "user://tests/m3_practice_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Profile.load_phase(path).phase == 1, "Absent practice profile safely starts at P1")
	_check(Profile.save_phase(path, 4) == OK and Profile.load_phase(path).phase == 4,
		"Officially reached practice phase survives a profile round trip")
	_check(Profile.save_phase(path, 5) == OK and Profile.load_phase(path).phase == 5,
		"A later reach atomically replaces an existing practice profile")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var invalid: Dictionary = Profile.load_phase(path)
	_check(invalid.phase == 1 and not str(invalid.error).is_empty(),
		"A corrupt practice profile recovers P1 with a visible error message")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"schema":1,"max_phase":"five"}')
	file.close()
	_check(Profile.load_phase(path).phase == 1, "A nonnumeric saved phase cannot unlock practice")
	_check(Profile.save_phase(path, 100) == OK and Profile.load_phase(path).phase == 5,
		"Saved practice IDs remain limited to existing P1 through P5")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_director_deferred_bag() -> void:
	for seed_value in [1, 7, 23, 137, 991, 4242]:
		var m = Model.new()
		m.reset(seed_value, "practice", 2)
		m.boss_pos = Vector2(320, 184)
		m.player_pos = Vector2(380, 184)
		m._first_pattern = false
		m._last_pattern = "territory"
		m._pattern_bag.clear()
		m._deferred_pattern = "horizon"
		m._director_repositioned = true
		m._start_next_pattern()
		_check(m.boss_pattern == "horizon" and m._deferred_pattern.is_empty()
			and m.pattern_history.size() == 1 and m.safety_error.is_empty(),
			"Deferred horizon resumes before refilling an empty bag, seed %d" % seed_value)
		m._start_next_pattern()
		_check(m.boss_pattern != "horizon" and m.pattern_history.size() == 2,
			"A restored deferred pattern cannot immediately repeat on bag refill, seed %d" % seed_value)
		var legal = true
		for iteration in range(12):
			m._start_next_pattern()
			var unique: Dictionary = {}
			for id in m._pattern_bag:
				unique[id] = true
			legal = legal and unique.size() == m._pattern_bag.size()
			var count: int = m.pattern_history.size()
			legal = legal and count >= 2 and m.pattern_history[count - 1] != m.pattern_history[count - 2]
		_check(legal, "Deferred recovery keeps later bags unique and avoids adjacent duplicates, seed %d" % seed_value)
		# Both cardinal corridor templates remain legal at the restored center.
		m.player_pos = Vector2(320, 244)
		m._deferred_pattern = "horizon"
		m._pattern_bag.clear()
		m._last_pattern = "territory"
		m._director_repositioned = true
		m._start_next_pattern()
		_check(m.boss_pattern == "horizon" and m.safety_error.is_empty(),
			"Deferred horizon also restores from the perpendicular center approach, seed %d" % seed_value)


func _test_director_waits_for_roll_exit() -> void:
	var m = Model.new()
	m.reset(137, "practice", 2)
	m.boss_pos = Vector2(320, 184)
	m.player_pos = Vector2(344.5, 184)
	m.player_facing = Vector2.LEFT
	m.step({"dodge": true, "move": Vector2.LEFT})
	_advance(m, 23)
	_check(m.player_state == "dodge" and m.pattern_history.is_empty()
		and m.hazards.is_empty() and m.safety_error.is_empty(),
		"Approach waits while a normal roll passes through the boss body")
	m.step()
	_check(m.player_state != "dodge" and m.pattern_history.size() == 1
		and m.boss_pattern == "rings" and m.boss_age == 0 and m.boss_state == "telegraph",
		"The first fully telegraphed pattern starts after roll exit and body separation")


func _test_dash_swept_collision_before_body_separation() -> void:
	var m = _model("practice", 3)
	m.player_pos = Vector2(380, 184)
	m.boss_enabled = true
	m.debug_start_pattern("dash")
	m.step()
	var first_route: Dictionary = {}
	for hazard in m.hazards:
		if int(hazard.number) == 1:
			first_route = hazard.duplicate(true)
	_check(not first_route.is_empty() and m.boss_pattern == "dash", "Dash regression starts a real legal first route")
	if first_route.is_empty():
		return
	m.player_pos = Vector2(first_route.origin) + Vector2(first_route.facing) * 40.0
	_advance(m, 119)
	_near(m.player_hp, 100.0, "Dash retains its telegraph and only reaches 8px on its first execution tick")
	_advance(m, 2)
	_near(m.player_hp, 74.0, "A player standing 40px in front takes the real swept dash hit before body separation")
	_advance(m, 15)
	_near(m.player_hp, 74.0, "The remaining first dash slot does not duplicate its 26 damage")
