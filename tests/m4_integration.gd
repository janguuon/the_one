extends SceneTree
## Targeted scene/save boundary tests arrange rare states deliberately.
## tests/m4_playthrough.gd supplies separate normal-input combat evidence.
const Main = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/profile_store.gd")
const PATH = "user://m4-integration/profile.json"
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures.append(message)

func _scene():
	var main = Main.instantiate()
	main.profile_path = PATH
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	return main

func _ticks(main, count: int) -> void:
	for index in range(count):
		main._physics_process(1.0 / 60.0)

func _key(main, key: Key, down: bool = true) -> void:
	var event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	main._unhandled_input(event)

func _run() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	_check(Store.save_profile(PATH, Store.defaults()) == OK, "Integration fixture writes a valid fresh profile")
	var main = _scene()
	_key(main, KEY_ENTER)
	_key(main, KEY_ENTER, false)
	main.model.boss_enabled = false
	var altar: Dictionary = main.model.altars[0]
	var found: String = altar.weapon
	main.model.player_pos = altar.pos
	main.model.stacks = 4
	main.model.element_id = "fire"
	main.model.element_charges = 2
	_ticks(main, 33)
	_check(main.model.weapon_id == found and main.model.stacks == 0, "Real scene ticks complete one stationary altar exchange")
	_check(main.model.element_id == "fire" and main.model.element_charges == 2, "Scene altar exchange preserves held fire")
	var saved: Dictionary = Store.load_profile(PATH).profile
	_check(saved.discovered_weapons.has(found), "Official altar discovery is persisted immediately before the run ends")
	main._record_result("abandoned")
	main._record_result("abandoned")
	saved = Store.load_profile(PATH).profile
	_check(saved.official_records.size() == 1 and saved.official_records[0].result == "abandoned", "An interrupted official run saves exactly one abandoned record")
	_check(saved.official_records[0].weapon_id == found, "The record retains the actual equipped weapon")
	main.free()

	main = _scene()
	_check(main.discovered_weapons.has(found), "A new scene restores the discovered starting weapon")
	main.screen = "weapons"
	main.menu_index = int(found.trim_prefix("W")) - 1
	_key(main, KEY_ENTER)
	_key(main, KEY_ENTER, false)
	_check(main.starting_weapon == found, "The unlocked weapon can be chosen through the actual menu")
	main._start_run("practice", 1)
	main.model.boss_enabled = false
	_check(main.model.weapon_id == found and main.model.oaths.is_empty(), "Practice starts with the selected weapon and no oaths")
	altar = main.model.altars[0]
	var practice_found: String = altar.weapon
	main.model.player_pos = altar.pos
	_ticks(main, 33)
	_check(main.model.weapon_id == practice_found, "Practice also supports the live altar exchange")
	saved = Store.load_profile(PATH).profile
	_check(saved.discovered_weapons.size() == 2 and saved.official_records.size() == 1, "Practice exchange creates neither discoveries nor official records")
	main.model.debug_start_pattern("claw")
	main._read_events()
	saved = Store.load_profile(PATH).profile
	_check(saved.seen_patterns.is_empty(), "A practice telegraph cannot add an official seen-pattern entry")
	main.free()

	main = _scene()
	main.starting_weapon = "W01"
	main._start_run("official", 1)
	main.model.boss_enabled = false
	main.model.debug_start_pattern("claw")
	main._read_events()
	saved = Store.load_profile(PATH).profile
	_check(saved.seen_patterns.has("claw"), "An official telegraph persists its seen-pattern ID")
	main.model.player_pos = Vector2(280,184)
	main.model.boss_pos = Vector2(320,184)
	main.model.player_facing = Vector2.RIGHT
	main.model.boss_hp = 18.0
	_key(main, KEY_J)
	_key(main, KEY_J, false)
	for index in range(115):
		_ticks(main, 1)
		if main.screen == "oaths":
			break
	_check(main.screen == "oaths" and main.model.selection_pending, "A finishing hit opens the real oath choice screen")
	saved = Store.load_profile(PATH).profile
	_check(saved.highest_phase == 2, "Phase reach is on disk before choosing an oath")
	var tick_before: int = main.model.tick
	var wall_before: float = main.wall_seconds
	_ticks(main, 300)
	_check(main.model.tick == tick_before and main.wall_seconds == wall_before, "Oath selection excludes all decision time from combat and wall-time records")
	var selected: String = main.model.oath_candidates[0]
	main.menu_index = 0
	_key(main, KEY_J)
	_check(main.screen == "playing" and main.model.oaths.has(selected), "Attack confirmation applies exactly the highlighted oath")
	_ticks(main, 70)
	_check(main.model.total_attacks == 1, "Holding oath confirmation across the countdown cannot spend an attack")
	_key(main, KEY_J, false)
	_key(main, KEY_J)
	_ticks(main, 1)
	_check(main.model.total_attacks == 2, "Release and a new attack press work after oath selection")
	_key(main, KEY_J, false)
	main.settings.show_particles = false
	main.settings.debug_visible = true
	main._save_profile_now()
	main.free()
	main = _scene()
	_check(not main.settings.show_particles and main.debug_visible, "Settings survive closing and reconstructing the scene")
	_check(main.unlocked_practice == 2, "M4 full-profile reload preserves the reached practice phase")
	main._start_run("official", 1)
	var old_seed: int = main.seed_value
	main._retry_run(true)
	_check(main.seed_value != old_seed and main.model.tick == 0 and main.model.phase_id == 1, "New-seed retry starts a clean official P1 run")
	_check(main.model.oaths.is_empty() and main.model.stacks == 0 and main.model.element_charges == 0, "Retry discards the prior run build and resources")
	main.free()
	print("M4 INTEGRATION: %d checks, %d failures" % [checks, failures.size()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)
