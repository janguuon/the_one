extends SceneTree

## Scene and input-boundary integration. Events are delivered to the same
## _unhandled_input callback used by devices; this is not a hardware input test.
const MainScene = preload("res://scenes/main.tscn")
const DT = 1.0 / 60.0
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_title_and_fresh_press()
	_test_pause_freezes_combat_and_pickups()
	_test_hitstop_freezes_every_combat_timer()
	_test_natural_death_and_retry()
	_test_completion_and_retry_menu()
	_test_gamepad_event_mapping()
	print("SCENE INTEGRATION: %d checks, %d failures" % [checks, failures.size()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _scene():
	var main = MainScene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.set_process(false)
	return main


func _playing_scene():
	var main = _scene()
	_key(main, KEY_ENTER)
	main.model.boss_enabled = false
	main.model.player_pos = Vector2(280, 184)
	main.model.boss_pos = Vector2(400, 184)
	main.model.player_facing = Vector2.RIGHT
	return main


func _key(main, key: Key, pressed: bool = true, echo: bool = false) -> void:
	var event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	main._unhandled_input(event)


func _joy(main, button: JoyButton, pressed: bool = true) -> void:
	var event = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	main._unhandled_input(event)


func _ticks(main, count: int, delta: float = DT) -> void:
	for index in range(count):
		main._physics_process(delta)


func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures.append(message)


func _test_title_and_fresh_press() -> void:
	var main = _scene()
	_check(main.screen == "title", "Main scene starts at the title screen")
	_ticks(main, 30)
	_check(main.model.tick == 0, "Title screen never advances combat")
	_key(main, KEY_ENTER)
	_check(main.screen == "playing" and main.model.mode == "prototype", "Enter starts prototype mode")
	_ticks(main, 1)
	_check(main.model.total_attacks == 0, "Title confirmation does not become a combat attack")
	main.model.boss_enabled = false
	main.model.player_pos = Vector2(280, 184)
	main.model.boss_pos = Vector2(400, 184)
	main.model.player_facing = Vector2.RIGHT
	_key(main, KEY_J)
	_ticks(main, 1)
	_check(main.model.total_attacks == 1, "Fresh J press starts one sword action")
	for index in range(40):
		_key(main, KEY_J, true, true)
		_ticks(main, 1)
	_check(main.model.total_attacks == 1, "Keyboard repeat echoes do not repeat an attack")
	main.model.debug_spawn_fire(main.model.player_pos)
	_ticks(main, 1)
	for index in range(40):
		_key(main, KEY_J, true, true)
		_ticks(main, 1)
	_check(main.model.fire_charges == 2 and main.model.total_attacks == 1,
		"T04 holding J across fire pickup never auto-attacks or spends fire")
	_key(main, KEY_J, false)
	_key(main, KEY_J)
	_ticks(main, 1)
	_check(main.model.fire_charges == 1 and main.model.total_attacks == 2,
		"T04 release and fresh J press starts exactly one fire attack")
	_key(main, KEY_F1)
	_check(main.debug_visible, "F1 toggles the development overlay")
	main.free()


func _test_pause_freezes_combat_and_pickups() -> void:
	var main = _playing_scene()
	main.model.debug_spawn_fire(Vector2(200, 184))
	_ticks(main, 10)
	var tick_before: int = main.model.tick
	var ttl_before: int = main.model.pickups[0].ttl
	var wall_before: float = main.wall_seconds
	_key(main, KEY_J)
	_key(main, KEY_ESCAPE)
	_check(main.screen == "paused", "Escape opens pause from combat")
	_ticks(main, 120)
	_check(main.model.tick == tick_before and main.model.pickups[0].ttl == ttl_before,
		"T20 pause freezes combat ticks and grounded pickup lifetime")
	_check(is_equal_approx(main.wall_seconds, wall_before), "Pause time is excluded from active wall time")
	_key(main, KEY_ESCAPE)
	_ticks(main, 1)
	_check(main.screen == "playing" and main.model.total_attacks == 0,
		"Resume clears an attack press pending before pause")
	_key(main, KEY_J, true, true)
	_ticks(main, 1)
	_check(main.model.total_attacks == 0, "Held J repeat after resume cannot start an attack")
	_key(main, KEY_ESCAPE)
	_key(main, KEY_J)
	_ticks(main, 1)
	_check(main.screen == "playing" and main.model.total_attacks == 0,
		"J confirming the resume menu does not leak into combat")
	main.free()


func _test_hitstop_freezes_every_combat_timer() -> void:
	var main = _playing_scene()
	main.model.boss_pos = Vector2(320, 184)
	_key(main, KEY_J)
	_ticks(main, 10)
	_check(main.model.boss_hp == 982.0 and main.hitstop_remaining > 0.0,
		"A normal sword hit produces real-time hitstop")
	main.model.debug_spawn_fire(Vector2(200, 184))
	var tick_before: int = main.model.tick
	var state_age_before: int = main.model.state_age
	var ttl_before: int = main.model.pickups[0].ttl
	_ticks(main, 1, 1.0 / 120.0)
	_check(main.model.tick == tick_before and main.model.state_age == state_age_before
		and main.model.pickups[0].ttl == ttl_before,
		"T20 hitstop freezes attack age and pickup lifetime with the combat clock")
	var remaining_before_pause: float = main.hitstop_remaining
	_key(main, KEY_ESCAPE)
	_ticks(main, 60)
	_check(is_equal_approx(main.hitstop_remaining, remaining_before_pause) and main.model.tick == tick_before,
		"Pausing during hitstop also freezes its remaining real-time interval")
	_key(main, KEY_ESCAPE)
	while main.hitstop_remaining > 0.0005:
		_ticks(main, 1, 1.0 / 120.0)
	_check(main.model.tick == tick_before, "Consuming the hitstop interval never advances a partial combat tick")
	_ticks(main, 1)
	_check(main.model.tick == tick_before + 1 and main.model.state_age == state_age_before + 1,
		"Hitstop resumes with one complete 60 Hz combat step")
	_check(main.model.pickups[0].ttl == ttl_before - 1, "Pickup lifetime resumes on the same combat step")
	main.free()


func _test_natural_death_and_retry() -> void:
	var main = _scene()
	_key(main, KEY_ENTER)
	for index in range(5000):
		_ticks(main, 1)
		if main.screen == "result":
			break
	_check(main.screen == "result" and main.model.result == "dead", "Normal boss attacks lead idle play to the death result screen")
	_check(not main.model.cause.is_empty(), "Death result retains the actual last damage cause")
	var tick_before: int = main.model.tick
	_ticks(main, 60)
	_check(main.model.tick == tick_before, "Result screen freezes further combat")
	_key(main, KEY_R)
	_check(main.screen == "playing" and main.model.tick == 0 and main.model.player_hp == 100.0
		and main.model.boss_hp == 1000.0 and main.model.result.is_empty(),
		"R restarts immediately with default health and an empty result")
	_ticks(main, 1)
	_check(main.model.total_attacks == 0, "Retry key never starts an attack")
	main.free()


func _test_completion_and_retry_menu() -> void:
	var main = _playing_scene()
	main.model.boss_pos = Vector2(320, 184)
	main.model.boss_hp = 18.0
	_key(main, KEY_J)
	_ticks(main, 15)
	_check(main.screen == "result" and main.model.result == "prototype_complete",
		"Normal sword finishing hit opens the P1 prototype completion screen")
	_key(main, KEY_J, false)
	_key(main, KEY_ENTER)
	_check(main.screen == "playing" and main.model.boss_hp == 1000.0 and main.model.tick == 0,
		"Completion retry menu starts a fresh P1 run")
	_ticks(main, 1)
	_check(main.model.total_attacks == 0, "Result confirmation never leaks an attack into the new run")
	main.free()


func _test_gamepad_event_mapping() -> void:
	var main = _scene()
	_joy(main, JOY_BUTTON_X)
	_check(main.screen == "playing", "Mapped gamepad X event confirms the title menu")
	main.model.boss_enabled = false
	main.model.player_pos = Vector2(280, 184)
	main.model.boss_pos = Vector2(400, 184)
	_ticks(main, 1)
	_check(main.model.total_attacks == 0, "Gamepad menu confirmation is consumed")
	_joy(main, JOY_BUTTON_X, false)
	_joy(main, JOY_BUTTON_X)
	_ticks(main, 1)
	_check(main.model.total_attacks == 1, "Mapped gamepad X press starts one attack")
	_joy(main, JOY_BUTTON_START)
	_check(main.screen == "paused", "Mapped gamepad Start pauses combat")
	main.free()
