extends SceneTree
## Real scene input callbacks and persisted profiles; no combat-strength overrides.
const Main = preload("res://scenes/main.tscn")
const Inputs = preload("res://scripts/input_settings.gd")
const Store = preload("res://scripts/profile_store.gd")
const PATH = "user://m5-ui/profile.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition: failures.append(message)

func _key(main, key: Key, down: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	main._unhandled_input(event)

func _joy(main, button: JoyButton, down: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = down
	main._unhandled_input(event)

func _scene():
	var main = Main.instantiate()
	main.profile_path = PATH
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	return main

func _run() -> void:
	var settings := Inputs.defaults()
	_check(Inputs.valid_keyboard(settings.keyboard), "Default keyboard bindings are valid and unique")
	_check(Inputs.valid_gamepad(settings.gamepad), "Default pad bindings are valid and unique")
	for action in Inputs.ACTIONS:
		var remapped := settings.duplicate(true)
		_check(Inputs.rebind(remapped, action, KEY_L).is_empty() and remapped.keyboard[action] == [KEY_L], "Every keyboard action can be rebound: " + action)
	_check(not Inputs.rebind(settings, "attack", KEY_SPACE).is_empty(), "Duplicate keyboard binding is rejected")
	_check(not Inputs.rebind(settings, "attack", KEY_R).is_empty(), "Retry shortcut cannot be consumed by a gameplay binding")
	_check(not Inputs.rebind(settings, "dodge", KEY_F1).is_empty(), "Debug shortcut remains reserved")
	_check(not Inputs.rebind(settings, "attack", KEY_ENTER).is_empty(), "Menu confirmation remains reserved")
	_check(not Inputs.rebind(settings, "move_up", KEY_ESCAPE).is_empty(), "Escape recovery cannot be reassigned")
	_check(not Inputs.rebind(settings, "attack", JOY_BUTTON_A, true).is_empty(), "Duplicate pad action is rejected")
	_check(Inputs.rebind(settings, "attack", JOY_BUTTON_Y, true).is_empty(), "Pad face button is configurable")
	_check(not Inputs.rebind(settings, "attack", JOY_BUTTON_BACK, true).is_empty(), "Pad Back remains reserved for capture cancellation")
	var dirty := settings.duplicate(true)
	dirty.keyboard.dodge = dirty.keyboard.attack.duplicate()
	dirty.gamepad.pause = dirty.gamepad.attack
	dirty.master_volume = INF
	dirty.music_volume = -3.0
	dirty.stick_deadzone = 8.0
	var cleaned := Inputs.sanitize(dirty)
	_check(cleaned.repaired and Inputs.valid_keyboard(cleaned.settings.keyboard) and Inputs.valid_gamepad(cleaned.settings.gamepad), "Corrupt and conflicting input maps recover safely")
	_check(cleaned.settings.master_volume == 0.8 and cleaned.settings.music_volume == 0.0 and cleaned.settings.stick_deadzone == 0.6, "Nonfinite volumes and deadzone bounds are sanitized")
	var legacy := {"schema":1,"settings":{"show_particles":false,"fullscreen":false,"debug_visible":true},"discovered_weapons":["W01","W02"],"highest_phase":4,"seen_patterns":["claw"],"official_records":[],"best_record":{}}
	var migrated := Store.sanitize_profile(legacy)
	_check(migrated.valid and str(migrated.error).is_empty(), "Existing M4 schema 1 profile upgrades without a corruption warning")
	_check(not migrated.profile.settings.show_particles and migrated.profile.settings.debug_visible and migrated.profile.highest_phase == 4, "M5 defaults preserve all old settings and progression")
	_check(migrated.profile.settings.keyboard == Inputs.default_keyboard() and migrated.profile.pattern_hit_counts.is_empty(), "Old profiles gain default bindings and empty experience")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	_check(Store.save_profile(PATH, Store.defaults()) == OK, "M5 fixture starts from a clean valid profile")
	var main = _scene()
	main._open_settings("title")
	main.menu_index = 4
	_key(main, KEY_ENTER)
	_key(main, KEY_ENTER, false)
	_check(main.screen == "controls", "Settings opens keyboard and pad remapping")
	main.menu_index = 4
	_key(main, KEY_ENTER)
	_key(main, KEY_ENTER, false)
	_check(main.capture_action == "attack", "Selected action enters capture without leaking confirmation")
	_key(main, KEY_SPACE)
	_key(main, KEY_SPACE, false)
	_check(main.capture_action == "attack" and main.settings.keyboard.attack == [KEY_J], "Conflicting key keeps capture active and original mapping intact")
	_key(main, KEY_L)
	_check(main.capture_action.is_empty() and main.rebind_release_gate and main.settings.keyboard.attack == [KEY_L], "Fresh key replaces attack mapping and waits for release")
	_key(main, KEY_L)
	_check(main.screen == "controls" and main.model.total_attacks == 0, "Held capture key does not confirm or start an attack")
	_key(main, KEY_L, false)
	main._begin_binding("dodge", false)
	_key(main, KEY_ESCAPE)
	_key(main, KEY_ESCAPE, false)
	_check(main.capture_action.is_empty() and main.settings.keyboard.dodge == [KEY_SPACE,KEY_K], "Escape cancels capture without changing the old binding")
	main._begin_binding("attack", true)
	_joy(main, JOY_BUTTON_Y)
	_joy(main, JOY_BUTTON_Y, false)
	_check(int(main.settings.gamepad.attack) == JOY_BUTTON_Y, "Actual pad-button callback stores a configurable face button")
	main._begin_binding("dodge", true)
	_joy(main, JOY_BUTTON_BACK)
	_joy(main, JOY_BUTTON_BACK, false)
	_check(main.capture_action.is_empty() and int(main.settings.gamepad.dodge) == JOY_BUTTON_A, "Pad Back cancels button capture without needing a keyboard")
	_check(Inputs.rebind(main.settings, "pause", KEY_P).is_empty(), "Pause may gain a new key while Escape remains recovery")
	main._install_inputs()
	main._start_run("practice", 1)
	main.model.boss_enabled = false
	_key(main, KEY_J)
	main._physics_process(1.0/60)
	_key(main, KEY_J, false)
	_check(main.model.total_attacks == 0, "The replaced old attack key no longer attacks")
	_key(main, KEY_L)
	main._physics_process(1.0/60)
	_check(main.model.total_attacks == 1, "The new attack key starts exactly one action")
	for i in range(45): main._physics_process(1.0/60)
	_check(main.model.total_attacks == 1, "Holding a remapped attack does not repeat")
	_key(main, KEY_L, false)
	main.model.element_id = "fire"
	main.model.element_charges = 2
	_key(main, KEY_L)
	main._physics_process(1.0/60)
	_key(main, KEY_L, false)
	main._read_events()
	_check(main.run_element_uses.fire == 1 and main.model.element_charges == 1, "Actual elemental attack consumes and records one use even when presentation is reread")
	for i in range(45): main._physics_process(1.0/60)
	main.model.stacks = main.model.stack_threshold()
	_key(main, KEY_L)
	main._physics_process(1.0/60)
	_key(main, KEY_L, false)
	_check(main.run_element_uses.fire == 2 and main.model.element_charges == 0 and main.model.stacks == 0, "Actual resonance records one elemental use while spending both resources")
	_check(main._dominant_element({"fire":2,"frost":2}) == "fire" and main._dominant_element({}).is_empty(), "Ending element ties and a no-element run have stable meanings")
	_check(main._ending_title("W01", {"fire":2}) != main._ending_title("W04", {"fire":2}), "Ending title reflects the equipped weapon")
	_key(main, KEY_P)
	_key(main, KEY_P, false)
	_check(main.screen == "paused", "Remapped pause key opens pause")
	_key(main, KEY_ESCAPE)
	_key(main, KEY_ESCAPE, false)
	_check(main.screen == "playing", "Fixed Escape recovery resumes after pause rebind")
	main._open_codex("paused")
	var tick: int = main.model.tick
	var wall: float = main.wall_seconds
	for i in range(60): main._physics_process(1.0/60)
	_check(main.model.tick == tick and main.wall_seconds == wall, "Codex freezes combat and excludes reading time from records")
	for tab in range(4):
		main.codex_tab = tab
		_check(main._codex_entries().size() == [5,4,12,15][tab], "Codex contains the full data-driven category %d" % tab)
	main.codex_tab = 3
	main.menu_index = 0
	for i in range(14): _key(main, KEY_DOWN)
	_check(main.menu_index == 14 and main.codex_scroll == 8, "Pattern list scrolls to the fifteenth entry")
	_key(main, KEY_TAB)
	_check(main.codex_tab == 0 and main.menu_index == 0, "Tab cycles categories and resets selection safely")
	_check(main._codex_pattern_hint("claw").is_empty(), "Unseen patterns reveal no hint")
	main.profile.seen_patterns.append("claw")
	main.profile.pattern_hit_counts.claw = 1
	_check(main._codex_pattern_hint("claw") != main.codex.patterns.claw.hint, "One hit does not reveal the response principle")
	main.profile.pattern_hit_counts.claw = 2
	_check(main._codex_pattern_hint("claw") == main.codex.patterns.claw.hint, "Repeated two-hit experience reveals the exact pattern principle")
	main.developer_practice = false
	main.model.mode = "official"
	main.model.tick += 1
	main.model.events.assign([{"type":"player_hit","cause":"재의 발톱","damage":26}])
	main._read_events()
	main._read_events()
	_check(main.profile.pattern_hit_counts.claw == 3, "One live hit cannot count twice when presentation is read again")
	main.model.mode = "practice"
	main.model.tick += 1
	main._read_events()
	_check(main.profile.pattern_hit_counts.claw == 3, "Practice cannot increase official pattern experience")
	main.settings.master_volume = 0.3
	main.settings.music_muted = true
	main.settings.reduced_effects = true
	main.model.mode = "official"
	main._record_result("abandoned")
	main._save_profile_now()
	main.free()
	main = _scene()
	_check(main.settings.keyboard.attack == [KEY_L] and int(main.settings.gamepad.attack) == JOY_BUTTON_Y, "Keyboard and pad bindings survive an actual scene reload")
	_check(main.settings.master_volume == 0.3 and main.settings.music_muted and main.settings.reduced_effects, "Volume, mute and reduced-effects settings survive reload")
	_check(main.profile.pattern_hit_counts.claw == 3, "Pattern experience survives save and reload")
	_check(main.official_records.size() == 1 and int(main.official_records[0].element_uses.fire) == 2, "Actual elemental use counts persist in the official record")
	main.screen = "controls"
	main.menu_index = 11
	main._activate_menu()
	_check(main.settings.keyboard == Inputs.default_keyboard() and main.settings.gamepad == Inputs.default_gamepad(), "One menu action restores recoverable default bindings")
	main.free()
	await process_frame
	await process_frame
	# The headless mixer runs on wall time; drain its final stopped voice too.
	await create_timer(0.08).timeout
	print("M5 UI: %d checks, %d failures" % [checks,failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
