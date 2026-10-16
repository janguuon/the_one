extends SceneTree
## Sends real Godot keyboard/joy events through Input and Main's callbacks.
## This is device-event validation, not a physical keyboard/controller test.
const Main = preload("res://scenes/main.tscn")
const Policy = preload("res://tests/m3_playthrough.gd")
const Bindings = preload("res://scripts/input_settings.gd")
var held: Dictionary = {}
var max_steps = 160000

func _initialize() -> void:
	call_deferred("_run")

func _key(code: int, down: bool) -> void:
	if bool(held.get(code,false)) == down:
		return
	held[code] = down
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _joy(code: int, down: bool) -> void:
	var id = "joy%d" % code
	if bool(held.get(id,false)) == down:
		return
	held[id] = down
	var event = InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _axis(axis: int, value: float) -> void:
	var event = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _release_all() -> void:
	for code in held.keys():
		if code is int: _key(code,false)
		else: _joy(int(str(code).trim_prefix("joy")),false)
	_axis(JOY_AXIS_LEFT_X,0.0)
	_axis(JOY_AXIS_LEFT_Y,0.0)

func _run() -> void:
	var modes = ["keyboard","gamepad"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--device="): modes = [arg.trim_prefix("--device=")]
		if arg.begins_with("--steps="): max_steps = int(arg.trim_prefix("--steps="))
	var failed = false
	for device in modes:
		var main = Main.instantiate()
		main.profile_enabled = false
		root.add_child(main)
		main.set_process(false)
		main.set_physics_process(false)
		# Thousands of accelerated timeline cues should not queue native mixer
		# work. Real playback and timing are covered by audio/native tests.
		main.audio_director.playback_enabled = false
		# Deliberately use non-default bindings for the full run.
		Bindings.rebind(main.settings,"attack",KEY_U)
		Bindings.rebind(main.settings,"dodge",KEY_I)
		Bindings.rebind(main.settings,"attack",JOY_BUTTON_Y,true)
		Bindings.rebind(main.settings,"dodge",JOY_BUTTON_B,true)
		Bindings.install(main.settings)
		main._start_run("official",1)
		for index in range(max_steps):
			if main.screen == "result":
				break
			if main.screen == "oaths":
				_release_all()
				for item in range(main.model.oath_candidates.size()):
					if device == "keyboard":
						_key(KEY_DOWN,true)
						_key(KEY_DOWN,false)
					else:
						_axis(JOY_AXIS_LEFT_Y,1.0)
						_axis(JOY_AXIS_LEFT_Y,0.0)
				if device == "keyboard":
					_key(KEY_ENTER,true)
					_key(KEY_ENTER,false)
				else:
					_joy(JOY_BUTTON_Y,true)
					_joy(JOY_BUTTON_Y,false)
				continue
			var command: Dictionary = Policy.decide(main.model)
			var movement: Vector2 = command.get("move",Vector2.ZERO)
			if device == "keyboard":
				_key(KEY_A,movement.x < -0.15)
				_key(KEY_D,movement.x > 0.15)
				_key(KEY_W,movement.y < -0.15)
				_key(KEY_S,movement.y > 0.15)
				_key(KEY_U,bool(command.get("attack",false)))
				_key(KEY_I,bool(command.get("dodge",false)))
			else:
				var strength = 0.0 if movement.length() < 0.001 else float(main.settings.stick_deadzone) + movement.length() * (1.0-float(main.settings.stick_deadzone))
				var stick = movement.normalized() * strength
				_axis(JOY_AXIS_LEFT_X,stick.x)
				_axis(JOY_AXIS_LEFT_Y,stick.y)
				_joy(JOY_BUTTON_Y,bool(command.get("attack",false)))
				_joy(JOY_BUTTON_B,bool(command.get("dodge",false)))
			main._physics_process(1.0/60.0)
			main._process(1.0/60.0)
		print("DEVICE_PLAYTHROUGH device=%s result=%s phase=%d ticks=%d wall=%.3f hp=%.3f attacks=%d damage=%.3f" % [device,main.model.result,main.model.phase_id,main.model.tick,main.wall_seconds,main.model.player_hp,main.model.total_attacks,main.model.damage_dealt])
		if max_steps >= 100000 and (main.model.result != "victory" or main.model.phase_history != [1,2,3,4,5] or absf(main.model.damage_dealt - 6000.0)>0.002):
			failed = true
		if max_steps < 100000 and main.model.tick == 0:
			failed = true
		_release_all()
		main.free()
	OS.delay_msec(80)
	quit(1 if failed else 0)
