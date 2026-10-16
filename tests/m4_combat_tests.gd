extends SceneTree
## Data, input, action, resource and transition contracts for M4.
const Model = preload("res://scripts/combat_model.gd")
const Geometry = preload("res://scripts/combat_geometry.gd")
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_weapon_actions()
	_test_dagger_events()
	_test_chain_and_geometry()
	_test_action_snapshot()
	_test_oath_damage()
	_test_oath_resources()
	_test_oath_selection()
	_test_altars()
	_test_streams()
	print("M4 COMBAT TESTS: %d checks, %d failures" % [checks, failures.size()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)

func _model(weapon: String = "W01", mode: String = "prototype", phase: int = 1):
	var m = Model.new()
	m.reset(137, mode, phase, weapon)
	m.boss_enabled = false
	m.player_pos = Vector2(280,184)
	m.boss_pos = Vector2(320,184)
	m.player_facing = Vector2.RIGHT
	return m

func _advance(m, count: int, command: Dictionary = {}) -> void:
	for index in range(count):
		m.step(command)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: " + message)

func _near(actual: float, expected: float, message: String, tolerance: float = 0.002) -> void:
	_check(absf(actual - expected) <= tolerance, "%s got %.4f expected %.4f" % [message, actual, expected])

func _equip_oath(m, id: String) -> void:
	m.selection_pending = true
	m.oath_candidates.assign([id])
	_check(m.choose_oath(id), id + " can be selected from a valid offered choice")

func _swing(m) -> void:
	m.step({"attack":true})
	_advance(m, int(m.weapon_definition().startup_ticks) + int(m.weapon_definition().active_ticks))

func _test_weapon_actions() -> void:
	var weapons = ["W01","W02","W03","W04","W05"]
	var damages = [18.0,27.0,15.0,44.0,27.0]
	var timings = [[9,6,18,24,6],[12,6,24,30,5],[5,8,11,19,8],[20,8,32,44,4],[12,6,21,29,6]]
	var variants = ["basic","signature","fire","frost","lightning","void","fire_resonance","frost_resonance","lightning_resonance","void_resonance"]
	for wi in range(weapons.size()):
		for variant in variants:
			var m = _model(weapons[wi])
			if wi == 2:
				m.boss_pos = m.player_pos + Vector2.RIGHT * 30.0
			var element = str(variant).trim_suffix("_resonance") if str(variant).ends_with("_resonance") else str(variant)
			var special = variant == "signature" or str(variant).ends_with("_resonance")
			if special:
				m.stacks = m.stack_threshold()
			if m.data.elements.has(element):
				m.element_id = element
				m.element_charges = int(m.data.elements[element].charges)
			var multiplier = 2.2 if special else 1.0
			if m.data.elements.has(element):
				multiplier *= float(m.data.elements[element].multiplier)
			m.step({"attack":true})
			var total = int(timings[wi][0]) + int(timings[wi][1]) + int(timings[wi][2])
			_check(m.attack.definition.startup_ticks == timings[wi][0] and m.attack.definition.active_ticks == timings[wi][1] and m.attack.definition.recovery_ticks == timings[wi][2], "%s %s keeps exact timing" % [weapons[wi],variant])
			_advance(m, int(timings[wi][0]) - 1)
			_near(m.boss_hp, 1000.0, "%s %s startup has no damage" % [weapons[wi],variant])
			_advance(m, int(timings[wi][1]) + 1)
			# Dagger rounds each half to one thousandth, then totals both hits.
			var expected = snappedf(damages[wi] * multiplier / (2.0 if wi == 2 else 1.0),0.001) * (2.0 if wi == 2 else 1.0)
			_near(1000.0 - m.boss_hp, expected, "%s %s correct direct total" % [weapons[wi],variant])
			_check(m.stacks == (1 if variant == "basic" else 0), "%s %s stack contract" % [weapons[wi],variant])
			m.pending_input = ""
			_advance(m, total - m.state_age)
			_check(m.player_state == "idle", "%s %s ends on same weapon duration" % [weapons[wi],variant])
		var cancel = _model(weapons[wi])
		cancel.step({"attack":true})
		_advance(cancel,int(timings[wi][3]) - 1)
		_check(cancel.player_state == "attack", "%s remains committed before cancel" % weapons[wi])
		cancel.step({"dodge":true})
		_check(cancel.player_state == "dodge", "%s cancels on exact weapon tick" % weapons[wi])
		_check(cancel.stack_threshold() == timings[wi][4], "%s has exact base stack threshold" % weapons[wi])

func _test_dagger_events() -> void:
	var m = _model("W03")
	m.boss_pos = m.player_pos + Vector2.RIGHT * 30.0
	m.step({"attack":true})
	_advance(m,4)
	_near(m.boss_hp,1000,"Dagger waits through age4")
	m.step()
	_near(m.boss_hp,992.5,"Dagger first event7.5 at age5")
	_advance(m,4)
	_near(m.boss_hp,992.5,"Dagger does not repeat first event through age9")
	m.step()
	_near(m.boss_hp,985,"Dagger second event7.5 at age10")
	_check(m.stacks == 1 and m.attack.hit_events.size() == 2,"Two dagger hits produce one stack and two event IDs")
	var late = _model("W03")
	late.boss_pos = Vector2(420,184)
	late.step({"attack":true})
	_advance(late,9)
	late.boss_pos = late.player_pos + Vector2.RIGHT * 30.0
	late.step()
	_near(late.boss_hp,992.5,"Missing first dagger event does not suppress second")
	_check(late.stacks == 1,"Second-only dagger hit earns one stack")
	var fire = _model("W03")
	fire.boss_pos = fire.player_pos + Vector2.RIGHT * 30.0
	fire.fire_charges = 2
	fire.step({"attack":true})
	_advance(fire,5)
	var expiry = fire.fire_expires_tick
	_advance(fire,5)
	_check(fire.fire_expires_tick == expiry,"One action's second dagger hit does not refresh fire again")
	_advance(fire,115)
	_near(1000.0-fire.boss_hp,32.25,"Dagger fire direct20.25 plus exact DOT12")
	_check(fire.fire_expires_tick == -1 and fire.stacks == 0,"Dagger fire expires after final tick without stacks")

func _test_chain_and_geometry() -> void:
	for variant in ["basic","signature","lightning","resonance"]:
		for distance in [30.0,35.999,36.0,40.0]:
			var m = _model("W05")
			m.boss_pos = m.player_pos + Vector2.RIGHT * distance
			if variant in ["signature","resonance"]:
				m.stacks = m.stack_threshold()
			if variant in ["lightning","resonance"]:
				m.element_id = "lightning"
				m.element_charges = 3
			_swing(m)
			_check((m.boss_hp < 1000.0) == (distance >= 36.0), "Chain %s footpoint minimum at %.3f" % [variant,distance])
	var chain = _model("W05")
	chain.step({"attack":true})
	var shape: Dictionary = chain.player_attack_shape()
	_check(not Geometry.contains(shape,chain.player_pos + Vector2.RIGHT * 10.0),"Chain drawn annular sector has no inner damage")
	_check(Geometry.contains(shape,chain.player_pos + Vector2.RIGHT * 30.0),"Chain annular sector has outer damage")
	_check(not Geometry2D.is_point_in_polygon(chain.player_pos + Vector2.RIGHT * 10.0,Geometry.polygon(shape)),"Chain polygon preserves its inner hole")
	_check(Geometry2D.is_point_in_polygon(chain.player_pos + Vector2.RIGHT * 30.0,Geometry.polygon(shape)),"Chain polygon matches the outer damage sector")
	var spear = _model("W02")
	spear.stacks = spear.stack_threshold()
	spear.step({"attack":true})
	_check(spear.player_attack_shape().length == 76.0 and spear.player_attack_shape().width == 18.0,"Spear signature is length76 width18")
	var hammer = _model("W04")
	hammer.stacks = hammer.stack_threshold()
	hammer.step({"attack":true})
	_check(hammer.player_attack_shape().shape == "disk" and hammer.player_attack_shape().radius == 24.0 and hammer.player_attack_shape().origin == Vector2(312,184),"Hammer signature uses forward32 disk radius24")

func _test_action_snapshot() -> void:
	var m = _model("W02")
	m.step({"attack":true})
	m.weapon_id = "W04"
	m.oaths.assign(["O01"])
	_advance(m,12)
	_near(m.boss_hp,973,"Running spear snapshot ignores later weapon/oath mutation")
	_check(m.attack.weapon == "W02" and m.player_attack_shape().shape == "line","Running action retains weapon geometry")
	_advance(m,29)
	_check(m.player_state == "attack","Running spear retains duration42")
	m.step()
	_check(m.player_state == "idle","Running spear finishes at42 despite hammer equipped")

func _test_oath_damage() -> void:
	for id in ["O01","O02","O05","O07","O08","O10"]:
		for kind in ["basic","signature","fire","resonance"]:
			var m = _model()
			_equip_oath(m,id)
			if kind in ["signature","resonance"]:
				m.stacks = m.stack_threshold()
			if kind in ["fire","resonance"]:
				m.fire_charges = 2
			var multiplier = 1.0
			if kind in ["signature","resonance"]:
				multiplier *= 2.2
			if kind in ["fire","resonance"]:
				multiplier *= 1.35
			if id == "O01":
				multiplier *= 1.15 if kind == "basic" else (0.85 if kind in ["signature","resonance"] else 1.0)
			if id == "O02" and kind in ["signature","resonance"]:
				multiplier *= 1.25
			if id in ["O05","O07"]:
				multiplier *= 0.92
			if id == "O08" and kind in ["fire","resonance"]:
				multiplier *= 0.85
			if id == "O10" and kind == "basic":
				multiplier *= 0.9
			_swing(m)
			_near(1000.0-m.boss_hp,snappedf(18.0*multiplier,0.001),"%s %s direct modifier" % [id,kind])
	for id in ["O03","O04"]:
		for hit_distance in [40.0,50.0]:
			var m = _model()
			_equip_oath(m,id)
			m.boss_pos = m.player_pos + Vector2.RIGHT * (50.0 if hit_distance <= 40.0 else 40.0)
			m.step({"attack":true})
			_advance(m,8)
			m.boss_pos = m.player_pos + Vector2.RIGHT * hit_distance
			m.step()
			var enhanced = (id == "O03" and hit_distance <= 40.0) or (id == "O04" and hit_distance > 40.0)
			_near(1000.0-m.boss_hp,20.7 if enhanced else 16.2,"%s evaluates live hit distance%.1f" % [id,hit_distance])
	var combined = _model()
	combined.oaths.assign(["O01","O05","O07"])
	_swing(combined)
	_near(1000-combined.boss_hp,snappedf(18*1.15*0.92*0.92,0.001),"Different oath direct modifiers multiply before one final rounding")
	var dot = _model()
	dot.oaths.assign(["O05","O07","O08"])
	dot.debug_apply_fire()
	_advance(dot,120)
	_near(dot.boss_hp,988,"Oath direct burdens do not reduce fire DOT")
	var defense = _model()
	_equip_oath(defense,"O12")
	defense.frost_guard_until = 180
	defense.debug_damage_player(40)
	defense.step()
	_near(defense.player_hp,71.2,"O12 and existing frost protection multiply40x0.9x0.8")

func _test_oath_resources() -> void:
	var m = _model()
	m.stacks = 6
	_equip_oath(m,"O02")
	_check(m.stacks == 6 and m.stack_threshold() == 8 and m.next_attack_kind() == "basic","O02 preserves6stacks but disarms sword signature6/8")
	var quick = _model()
	quick.stacks = 5
	_equip_oath(quick,"O10")
	_check(quick.stack_threshold() == 5 and quick.next_attack_kind() == "signature","O10 arms existing5stacks without generating resources")
	var hammer = _model("W04")
	_equip_oath(hammer,"O10")
	_check(hammer.stack_threshold() == 3,"O10 hammer threshold clamps at3")
	var hp = _model()
	_equip_oath(hp,"O06")
	_near(hp.player_hp,85,"O06 clamps current health to new max85")
	hp.player_hp = 60
	_equip_oath(hp,"O07")
	_near(hp.player_max_hp(),105,"O07 adds20 maximum to existing build")
	_near(hp.player_hp,80,"O07 adds20 current health once")
	_equip_oath(hp,"O11")
	_near(hp.player_max_hp(),95,"O11 maximum health burden adds with O06/O07")
	_near(hp.phase_heal(),25,"O11 raises future transition reward25")
	var pouch = _model()
	pouch.fire_charges = 2
	_equip_oath(pouch,"O08")
	_check(pouch.fire_charges == 2 and pouch.element_max_charges("fire") == 3,"O08 does not grant held charges immediately")
	pouch.debug_spawn_fire(pouch.player_pos)
	pouch.step()
	_check(pouch.fire_charges == 3 and pouch.pickups.is_empty(),"O08 pickup replenishes to new maximum")
	for element in ["fire","frost","lightning","void"]:
		_check(pouch.element_max_charges(element) == int(pouch.data.elements[element].charges)+1,"O08 adds one maximum for " + element)
	var warmth = _model()
	_equip_oath(warmth,"O09")
	_near(warmth.move_speed(),90.24,"O09 actual movement speed90.24")
	_check(warmth.ground_lifetime() == 960,"O09 actual ground lifetime960")
	warmth.debug_spawn_fire(Vector2(400,184))
	_advance(warmth,959)
	_check(warmth.pickups.size() == 1,"O09 pickup survives through959")
	warmth.step()
	_check(warmth.pickups.is_empty(),"O09 pickup expires960")
	for held in [["O05"],["O12"],["O05","O12"],["O06","O09"]]:
		var movement = _model()
		movement.oaths.assign(held)
		if held.has("O05"):
			_near(movement.dodge_distance(),74.52 if held.has("O12") else 82.8,"O05 combined actual dodge distance")
		elif held.has("O12"):
			_near(movement.dodge_distance(),64.8,"O12 actual dodge distance64.8")
		else:
			_near(movement.move_speed(),101.0688,"O06/O09 movement modifiers multiply")

func _kill_phase(m) -> void:
	m.player_pos = Vector2(280,184)
	m.boss_pos = Vector2(320,184)
	m.player_facing = Vector2.RIGHT
	m.boss_hp = 1
	m.step({"attack":true})
	_advance(m,int(m.weapon_definition().startup_ticks))

func _test_oath_selection() -> void:
	var m = _model("W01","official")
	m.player_hp = 50
	_kill_phase(m)
	_near(m.player_hp,65,"Phase reward applies before first oath choice")
	_advance(m,90)
	_check(m.selection_pending and m.oath_candidates.size() == 3 and m.phase_id == 2,"P1 completion offers three legal seeded choices after relocation")
	var frozen = m.tick
	var remaining = m.transition_ticks_remaining
	_advance(m,300,{"attack":true,"dodge":true,"move":Vector2.RIGHT})
	_check(m.tick == frozen and m.transition_ticks_remaining == remaining and m.pending_input == "","Selection freezes all combat time and rejects input")
	_check(not m.choose_oath("BAD") and m.selection_pending,"Unknown choice cannot resume or modify build")
	# Arrange the offer to isolate resource side effects from seeded availability.
	m.oath_candidates.assign(["O11"])
	_check(m.choose_oath("O11"),"Valid offered oath confirms once")
	_near(m.player_hp,65,"O11 does not retroactively duplicate already received phase heal")
	_check(m.transition_ticks_remaining == 60 and m.pending_input == "","Choice preserves whole60-tick ready warning and clears input")
	_check(not m.choose_oath("O11"),"Repeated confirm cannot duplicate an oath")
	_advance(m,60)
	_check(m.player_state == "idle" and m.transition_ticks_remaining == 0,"Choice resumes combat after60ticks")
	for phase in [2,3,4]:
		m.player_hp = 50
		_kill_phase(m)
		_near(m.player_hp,75,"O11 subsequent phase reward is25")
		_advance(m,90)
		_check(m.selection_pending == (phase <= 3),"Only completed P1..P3 offer oath choices P%d" % phase)
		if m.selection_pending:
			_check(m.choose_oath(),"Skip resumes without adding an oath")
		_advance(m,60)
	_check(m.phase_id == 5 and m.oaths == ["O11"],"P4 reachesP5 without a fourth selection")
	var excluded = _model()
	for held in [["O01"],["O02"],["O03"],["O04"],["O10"]]:
		excluded.oaths.assign(held)
		var legal: Array[String] = excluded.legal_oaths()
		for id in held:
			_check(not legal.has(id),"Owned oath never offered again " + id)
			for banned in excluded.data.oaths[id].excludes:
				_check(not legal.has(banned),"Excludes conflicting choice %s with %s" % [banned,id])
	excluded.oaths.assign(["O05","O07","O08"])
	_check(excluded.legal_oaths().is_empty(),"Three-oath build cannot acquire a fourth")
	for mode in ["practice","prototype"]:
		var other = _model("W01",mode)
		_kill_phase(other)
		_check(not other.selection_pending and other.oaths.is_empty(),mode + " does not offer official oath rewards")

func _test_altars() -> void:
	var m = _model()
	m.player_pos = m.altars[0].pos
	m.stacks = 5
	m.fire_charges = 2
	var previous = m.weapon_id
	var offered: String = m.altars[0].weapon
	_advance(m,32)
	_check(m.weapon_id == previous and m.altars[0].progress == 32,"Altar waits for33 idle ticks")
	m.step()
	_check(m.weapon_id == offered and m.altars[0].weapon == previous,"Altar performs atomic weapon exchange")
	_check(m.stacks == 0 and m.fire_charges == 2 and m.player_hp == 100,"Swap resets stack but preserves element and health")
	_check(not m.altars[0].armed,"Swap disarms the same altar")
	_advance(m,100)
	_check(m.weapon_id == offered,"Remaining at altar never swaps back automatically")
	m.player_pos = Vector2(m.altars[0].pos) + Vector2.RIGHT * 20.0
	m.step()
	_check(not m.altars[0].armed,"Exactly20px does not rearm altar")
	m.player_pos.x += 0.1
	m.step()
	_check(m.altars[0].armed,"Outside20px rearms altar")
	m.player_pos = m.altars[0].pos
	_advance(m,33)
	_check(m.weapon_id == previous and m.altars[0].weapon == offered,"Reentered altar swaps the original item back")
	var all_ids: Array[String] = [m.weapon_id]
	for altar in m.altars:
		all_ids.append(str(altar.weapon))
	all_ids.sort()
	_check(all_ids == ["W01","W02","W03","W04","W05"],"Repeated exchange preserves exactly five unique weapons")
	for interruption in ["attack","move","dodge","hit"]:
		var interrupted = _model()
		interrupted.player_pos = interrupted.altars[0].pos
		_advance(interrupted,32)
		var command: Dictionary = {}
		if interruption == "hit":
			interrupted.debug_damage_player(10)
		elif interruption == "move":
			command.move = Vector2.RIGHT
		else:
			command[interruption] = true
		interrupted.step(command)
		_check(interrupted.weapon_id == "W01" and interrupted.altars[0].progress == 0,"33rd-tick %s cancels altar without swapping" % interruption)
	var transit = _model()
	transit.player_pos = transit.altars[0].pos
	_advance(transit,40,{"move":Vector2.RIGHT})
	_check(transit.weapon_id == "W01","Running through altar cannot swap")
	var practice = _model("W02","practice",3)
	practice.player_pos = practice.altars[2].pos
	_advance(practice,33)
	_check(practice.weapon_id != "W02" and practice.mode == "practice" and practice.oaths.is_empty(),"Practice uses the same altars without official oath rewards")

func _test_streams() -> void:
	var first = _model("W03","official")
	var second = _model("W03","official")
	_check(first.altars == second.altars,"Same seed and starting weapon reproduce altar layout")
	var before: Dictionary = first.stream_states()
	for index in range(100):
		first.cosmetic_random()
	var after: Dictionary = first.stream_states()
	for stream in ["layout","boss","oath","element"]:
		_check(before[stream] == after[stream],"Cosmetic calls leave %s stream untouched" % stream)
	_check(before.cosmetic != after.cosmetic,"Cosmetic stream advances independently")
	first._begin_oath_selection()
	second._begin_oath_selection()
	_check(first.oath_candidates == second.oath_candidates,"Cosmetic calls do not change seeded oath offers")
	_check(first.stream_states().boss == before.boss and first.stream_states().element == before.element,"Generating oath candidates does not consume boss or element RNG")
	var layouts: Dictionary = {}
	for seed in range(12):
		var m = Model.new()
		m.reset(seed,"official",1,"W01")
		var ids: Array[String] = []
		for altar in m.altars:
			ids.append(str(altar.weapon))
		layouts[str(ids)] = true
	_check(layouts.size() > 1,"Different seeds can change altar assignments")
