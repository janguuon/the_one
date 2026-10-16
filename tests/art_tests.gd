extends SceneTree
## Validates shipped raster assets and animation selection without changing combat.
const Art = preload("res://scripts/pixel_art.gd")
const Combat = preload("res://scripts/combat_model.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _run() -> void:
	var art := Art.new()
	_check(art.arena != null, "Original arena image loads")
	_check(art.arena.get_size() == Vector2(640, 360), "Arena is sampled onto the 640x360 logical grid")
	_check(art.human_frames.size() == 40, "Human has 5 source directions and 8 pose frames")
	_check(art.boss_frames.size() == 18, "Boss has 3 views and 6 shared pose frames")
	_check(art.relic_frames.size() == 10, "All five weapons, altar and four shape-coded elements load")
	_validate_frames(art.human_frames, Vector2i(48, 48), "human")
	_validate_frames(art.boss_frames, Vector2i(104, 104), "boss")
	_validate_frames(art.relic_frames, Vector2i(40, 40), "relic")
	for row in range(5):
		_check(art.human_frames[row * 8 + 1].get_image().get_data() != art.human_frames[row * 8 + 2].get_image().get_data(), "Human direction %d has genuinely different nearest-sampled walking pixels" % row)
	for row in range(3):
		_check(art.boss_frames[row * 6].get_image().get_data() != art.boss_frames[row * 6 + 1].get_image().get_data(), "Boss view %d has genuinely different breathing pixels" % row)
	_test_views(art)
	_test_actor_states(art)
	_test_boss_states(art)
	_test_cosmetic_independence(art)
	_test_weapon_visual_geometry(art)
	_test_reduced_effect_policy(art)
	print("ART TESTS: %d checks, %d failures" % [checks, failures.size()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _validate_frames(frames: Array[ImageTexture], expected_size: Vector2i, label: String) -> void:
	for index in range(frames.size()):
		var frame := frames[index].get_image()
		_check(frame.get_size() == expected_size, "%s frame %d uses logical pixels" % [label, index])
		var used := frame.get_used_rect()
		_check(used.size.x > 3 and used.size.y > 3, "%s frame %d contains a visible sprite" % [label, index])
		var alpha_pixels := 0
		var transparent_pixels := 0
		for y in range(frame.get_height()):
			for x in range(frame.get_width()):
				var alpha := frame.get_pixel(x, y).a
				if alpha > 0.5:
					alpha_pixels += 1
				elif alpha < 0.1:
					transparent_pixels += 1
		_check(alpha_pixels > 12 and transparent_pixels > alpha_pixels / 4, "%s frame %d preserves real transparency" % [label, index])


func _test_views(art) -> void:
	var directions := [Vector2.UP, Vector2(1, -1), Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1), Vector2.LEFT, Vector2(-1, -1)]
	var views := []
	for direction in directions:
		views.append(art.human_direction(direction))
	_check(views[0].row == 0 and views[4].row == 4, "North and south have distinct original art")
	_check(views[2].row == views[6].row and not views[2].flip and views[6].flip, "East/west mirror the same source view")
	_check(views[1].row == views[7].row and views[3].row == views[5].row, "Diagonal mirrors select matching hand/body views")
	_check(art.human_direction(Vector2.ZERO).row == 4, "Zero-vector fallback remains a valid visible view")
	for index in range(4):
		var element: String = ["fire", "frost", "lightning", "void"][index]
		_check(art.element_frame(element) == 6 + index, "Element %s selects its unique geometric sprite" % element)


func _test_actor_states(art) -> void:
	var model := Combat.new()
	model.reset(7, "official", 1)
	model.player_state = "idle"
	var idle: Dictionary = art.human_pose(model)
	model.player_state = "move"
	model.tick = 0
	var step_a: Dictionary = art.human_pose(model)
	model.tick = 7
	var step_b: Dictionary = art.human_pose(model)
	_check(step_a.frame != step_b.frame and step_a.frame != idle.frame, "Walking animates distinct stride frames")
	model.player_state = "attack"
	model.attack = {"age": 0, "definition": model.weapon_definition()}
	var startup: Dictionary = art.human_pose(model)
	model.attack.age = int(model.weapon_definition().startup_ticks)
	var active: Dictionary = art.human_pose(model)
	model.attack.age = int(model.weapon_definition().startup_ticks) + int(model.weapon_definition().active_ticks)
	var recovery: Dictionary = art.human_pose(model)
	_check(startup.frame != active.frame and active.frame != recovery.frame, "Weapon timing selects preparation, release, and recovery art")
	model.player_state = "dodge"
	model.state_age = 0
	var roll_a: Dictionary = art.human_pose(model)
	model.state_age = 8
	var roll_b: Dictionary = art.human_pose(model)
	_check(roll_a.frame == roll_b.frame and not is_equal_approx(roll_a.rotation, roll_b.rotation), "Dodge uses compact pose and combat-clock tumble")
	model.player_state = "hurt"
	_check(art.human_pose(model).frame != recovery.frame, "Hurt has a separate visible stagger pose")
	model.player_hp = 0.0
	var death: Dictionary = art.human_pose(model)
	_check(death.frame >= 0 and death.frame < 40 and death.rotation > 0.5, "Death uses a collapsed body pose")
	model.player_hp = 100
	model.player_state = "attack"
	for id in model.data.weapons:
		model.weapon_id = id
		model.attack = {"age": int(model.weapon_definition().startup_ticks), "definition": model.weapon_definition()}
		_check(art.human_pose(model).column == 4, "%s releases at its actual active timing" % id)


func _test_boss_states(art) -> void:
	var model := Combat.new()
	model.reset(7, "practice", 4)
	model.boss_state = "approach"
	model.tick = 0
	var idle: Dictionary = art.boss_pose(model)
	model.tick = 30
	_check(art.boss_pose(model).frame != idle.frame, "Boss breathes between two rib/arm poses")
	var state_frames := []
	for state in ["telegraph", "execute", "recover"]:
		model.boss_state = state
		state_frames.append(int(art.boss_pose(model).frame))
	_check(state_frames[0] != state_frames[1] and state_frames[1] != state_frames[2], "Boss warning, strike, and recovery have separate poses")
	model.boss_hp = 0
	_check(art.boss_pose(model).column == 5, "Boss destruction selects collapse art")
	model.boss_hp = 10
	model.boss_facing = Vector2.UP
	var north: Dictionary = art.boss_pose(model)
	model.boss_facing = Vector2.DOWN
	_check(north.row != art.boss_pose(model).row, "Boss turns between original front and back views")


func _test_cosmetic_independence(art) -> void:
	var model := Combat.new()
	model.reset(19, "official", 1)
	var baseline := model.stream_states().duplicate(true)
	for index in range(1000):
		art.human_pose(model)
		art.boss_pose(model)
		art.human_direction(Vector2.from_angle(float(index)))
	_check(model.tick == 0 and model.player_hp == 100 and model.stacks == 0, "Sampling animations never advances combat or resources")
	_check(model.stream_states() == baseline, "Art never consumes layout, boss, reward, or cosmetic RNG streams")


func _test_weapon_visual_geometry(art) -> void:
	var model := Combat.new()
	for index in range(8):
		model.reset(29, "official", 1, "W02")
		model.boss_enabled = false
		model.player_facing = Vector2.from_angle(float(index) * TAU / 8.0)
		model.step({"attack": true})
		var initial_hand: Vector2 = art.weapon_pose(model).hand
		var original_facing: Vector2 = model.attack.facing
		for age in range(0, 19):
			if age in [0, 12, 18]:
				var visual: Dictionary = art.weapon_pose(model)
				var geometry: Dictionary = model.player_attack_shape()
				_check(Vector2(visual.direction).is_equal_approx(Vector2(geometry.facing)), "Spear view %d age %d stays aligned with real line hit geometry" % [index, age])
				if age == 12:
					_check((Vector2(visual.hand) - initial_hand).dot(original_facing) > 5.0, "Spear view %d reaches forward at its active hit" % index)
			model.step({})
	model.reset(29, "official", 1, "W02")
	model.boss_enabled = false
	model.player_facing = Vector2.RIGHT
	model.step({"attack": true})
	model.player_facing = Vector2.LEFT
	model.weapon_id = "W01"
	var snapshot: Dictionary = art.weapon_pose(model)
	_check(snapshot.weapon == "W02" and Vector2(snapshot.direction) == Vector2.RIGHT, "In-flight weapon art keeps the started attack's weapon and facing snapshot")
	model.reset(29, "official", 1, "W04")
	model.boss_enabled = false
	model.step({"attack": true})
	var raised: Dictionary = art.weapon_pose(model)
	for age in range(28):
		model.step({})
	var landed: Dictionary = art.weapon_pose(model)
	_check(Vector2(raised.hand).y < Vector2(landed.hand).y and absf(Vector2(landed.direction).angle_to(model.player_facing)) < 0.1, "Hammer raises above the hand then drops toward its aimed impact")


func _test_reduced_effect_policy(art) -> void:
	var model := Combat.new()
	model.reset(29, "official", 1)
	model.player_invulnerable_until = 100
	model.player_state = "hurt"
	art.reduced_effects = false
	var full: Dictionary = art.effect_policy(model)
	_check(full.hurt_flash and full.dodge_trails > 0, "Regular effects include hit emphasis and optional dodge afterimages")
	art.reduced_effects = true
	var reduced: Dictionary = art.effect_policy(model)
	_check(not reduced.hurt_flash and reduced.dodge_trails == 0 and reduced.death_debris == 0, "Reduced effects suppress hit flicker, afterimages, and death particles")
	var held_icon: int = art.element_frame("frost")
	model.element_id = "frost"
	model.element_charges = 1
	var before := model.stream_states().duplicate(true)
	for index in range(12):
		art.reduced_effects = not art.reduced_effects
		art.effect_policy(model)
		_check(art.element_frame("frost") == held_icon, "Effect settings preserve the mandatory distinct frost icon")
	_check(model.element_charges == 1 and model.player_invulnerable_until == 100 and model.stream_states() == before, "Effect settings never change guard resources, immunity, or combat RNG")
	art.reduced_effects = false
