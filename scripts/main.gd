extends Node2D
## Presentation owns real time and fresh button edges. CombatModel owns every rule.

const Combat = preload("res://scripts/combat_model.gd")
const Geometry = preload("res://scripts/combat_geometry.gd")
const ProfileStore = preload("res://scripts/profile_store.gd")
const InputSettings = preload("res://scripts/input_settings.gd")
const AudioDirector = preload("res://scripts/audio_director.gd")
const PixelArt = preload("res://scripts/pixel_art.gd")
const CENTER = Vector2(320, 184)
const RADII = Vector2(260, 126)
const ASH = Color("b8c5bc")
const MUTED = Color("78928d")
const EMBER = Color("f3b16c")
const DANGER = Color("d8d4bd")
const FIRE = Color("e58b50")
const FROST = Color("b6deeb")
const LIGHTNING = Color("f4e8a4")
const VOID = Color("b597cf")
const BG = Color("050c10")
const PATTERN_NAMES = {
	"claw": "재의 발톱", "rupture": "첫 균열", "pulse": "최초의 맥동",
	"territory": "서리의 영토", "rings": "맞물리는 고리", "horizon": "얼어붙는 지평",
	"heartbeat": "세 번째 심장", "dash": "번개의 궤적", "thrust": "멎은 심장",
	"echo": "남은 칼날", "footprints": "지워지지 않는 발자국", "fractures": "갈라진 순간",
	"execution": "최초의 처형", "last_horizon": "마지막 지평", "nameless_end": "이름 없는 끝",
}
const PHASE_NAMES = ["형체를 얻은 악", "땅을 삼키는 악", "박동하는 악", "기억하는 악", "이름 없는 끝"]
const PHASE_WORDS = ["THE FIRST SHAPE", "THE DEVOURING GROUND", "THE THIRD HEART", "THE REMEMBERING DARK", "THE NAMELESS END"]

var model = Combat.new()
var screen: String = "title"
var debug_visible: bool = false
var menu_index: int = 0
var cosmetic_time: float = 0.0
var hitstop_remaining: float = 0.0
var hitstop_guard: float = 0.0
var wall_seconds: float = 0.0
var attack_pressed: bool = false
var dodge_pressed: bool = false
var seed_value: int = 1
var font: SystemFont
var korean_font: SystemFont
var particles: Array[Dictionary] = []
var notices: Array[Dictionary] = []
var floor_marks: Array[Vector2] = []
var capture_path: String = ""
var capture_wait: int = 8
var capture_done: bool = false
var smoke: bool = false
var capture_tick: int = 0
var menu_axis_direction: int = 0
var unlocked_practice: int = 1
var official_records: Array[Dictionary] = []
var practice_phase: int = 1
var run_start_phase: int = 1
var run_mode: String = "official"
var result_recorded: bool = false
var attack_held: bool = false
var dodge_held: bool = false
var require_attack_release: bool = false
var require_dodge_release: bool = false
var was_transition: bool = false
var developer_practice: bool = false
var profile_path: String = "user://profile.json"
var profile_enabled: bool = true
var profile_saved_phase: int = 1
var profile: Dictionary = {}
var discovered_weapons: Array[String] = ["W01"]
var starting_weapon: String = "W01"
var run_start_weapon: String = "W01"
var settings: Dictionary = InputSettings.defaults()
var settings_return: String = "title"
var seed_input: String = "1"
var developer_screen: String = ""
var codex: Dictionary = {}
var codex_tab: int = 0
var codex_return: String = "title"
var codex_scroll: int = 0
var capture_action: String = ""
var capture_joy: bool = false
var controls_message: String = ""
var controls_return: String = "settings"
var rebind_release_gate: bool = false
var audio_director: Node
var pixel_art: RefCounted = PixelArt.new()
var pattern_hit_stamps: Dictionary = {}
var run_element_uses: Dictionary = {"fire":0, "frost":0, "lightning":0, "void":0}
var attack_event_tick: int = -1
var closing: bool = false


func _ready() -> void:
	codex = JSON.parse_string(FileAccess.get_file_as_string("res://data/encyclopedia.json"))
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Noto Sans", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	korean_font = SystemFont.new()
	korean_font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	korean_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	profile = ProfileStore.defaults()
	if profile_enabled:
		var loaded := ProfileStore.load_profile(profile_path, "user://m3_practice.json")
		profile = loaded.profile
		unlocked_practice = int(profile.highest_phase)
		profile_saved_phase = unlocked_practice
		if not str(loaded.error).is_empty():
			notices.append({"text": str(loaded.error), "life": 7.0})
	for id in profile.discovered_weapons:
		if not discovered_weapons.has(str(id)):
			discovered_weapons.append(str(id))
	for record in profile.official_records:
		official_records.append(record)
	settings = profile.settings.duplicate(true)
	audio_director = AudioDirector.new()
	# Headless scene tests inspect cues while advancing many combat minutes in
	# one CPU frame. Dedicated audio tests and native play use the real mixer.
	audio_director.playback_enabled = DisplayServer.get_name() != "headless"
	add_child(audio_director)
	audio_director.configure(settings)
	debug_visible = bool(settings.debug_visible)
	_apply_display_setting()
	_install_inputs()
	get_tree().auto_accept_quit = false
	for i in range(92):
		var theta := float(i) * 2.3999632
		var radius := sqrt(float(i + 1) / 94.0)
		floor_marks.append(CENTER + Vector2(cos(theta) * 249.0, sin(theta) * 116.0) * radius)
	var autostart := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--autostart" or arg == "--smoke":
			smoke = arg == "--smoke"
			autostart = true
		elif arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--capture-tick="):
			capture_tick = int(arg.trim_prefix("--capture-tick="))
		elif arg.begins_with("--dev-screen="):
			developer_screen = arg.get_slice("=", 1)
			profile_enabled = false
			developer_practice = true
		elif arg.begins_with("--weapon="):
			starting_weapon = arg.get_slice("=", 1)
			developer_practice = true
		elif arg == "--mode=prototype":
			run_mode = "prototype"
		elif arg.begins_with("--practice=") or arg.begins_with("--phase="):
			run_start_phase = clampi(int(arg.get_slice("=", 1)), 1, 5)
			run_mode = "practice"
			developer_practice = true
			autostart = true
	if not model.data.weapons.has(starting_weapon):
		starting_weapon = "W01"
	model.reset(seed_value, run_mode, run_start_phase, starting_weapon)
	if autostart:
		_start_run(run_mode, run_start_phase)
	if developer_screen in ["weapons", "settings", "seed", "oaths", "codex", "controls", "audio"]:
		screen = developer_screen
		if screen == "oaths":
			model.oath_candidates.assign(["O01", "O07", "O12"])
			model.selection_pending = true
	queue_redraw()


func _install_inputs() -> void:
	InputSettings.install(settings)


func _unhandled_input(event: InputEvent) -> void:
	if closing:
		return
	if event is InputEventKey and event.echo:
		return
	if not capture_action.is_empty():
		_capture_binding(event)
		return
	if rebind_release_gate:
		# A key/button used to bind must be released before any menu confirmation.
		if (event is InputEventKey or event is InputEventJoypadButton) and not event.pressed:
			rebind_release_gate = false
			attack_held = false
			dodge_held = false
			require_attack_release = false
			require_dodge_release = false
		return
	var fresh_attack := false
	var fresh_dodge := false
	if event.is_action_released("attack"):
		attack_held = false
		require_attack_release = false
	if event.is_action_released("dodge"):
		dodge_held = false
		require_dodge_release = false
	if event.is_action_pressed("attack"):
		fresh_attack = not attack_held and not require_attack_release
		attack_held = true
	if event.is_action_pressed("dodge"):
		fresh_dodge = not dodge_held and not require_dodge_release
		dodge_held = true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			debug_visible = not debug_visible
			settings.debug_visible = debug_visible
			_save_profile_now()
			return
		if event.keycode == KEY_R and screen in ["playing", "paused", "result"]:
			_retry_run()
			return
		if screen == "seed":
			if event.keycode >= KEY_0 and event.keycode <= KEY_9:
				if seed_input.length() < 9:
					seed_input += str(event.keycode - KEY_0)
				return
			if event.keycode == KEY_BACKSPACE:
				seed_input = seed_input.left(maxi(0, seed_input.length() - 1))
				return
	var escape: bool = event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE
	var pad_back: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B and screen != "playing" and int(settings.gamepad.attack) != JOY_BUTTON_B
	if event.is_action_pressed("pause") or escape or pad_back:
		if screen == "playing":
			screen = "paused"
			menu_index = 0
		elif screen == "paused":
			screen = "playing"
		elif screen == "settings":
			screen = settings_return
			menu_index = 0
		elif screen in ["audio", "controls"]:
			screen = "settings"
			menu_index = 0
		elif screen == "codex":
			screen = codex_return
			menu_index = 0
		elif screen in ["practice", "weapons", "seed", "result"]:
			screen = "title"
			menu_index = 0
		_clear_action_boundary()
		return
	if screen != "playing":
		if screen == "codex":
			_codex_input(event)
			return
		var menu_direction := 0
		if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
			var direction := 1 if event.axis_value > 0.55 else -1 if event.axis_value < -0.55 else 0
			menu_direction = direction if direction != 0 and direction != menu_axis_direction else 0
			menu_axis_direction = direction
		elif event.is_action_pressed("move_up") or (event is InputEventKey and event.pressed and event.keycode == KEY_UP) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_UP):
			menu_direction = -1
		elif event.is_action_pressed("move_down") or (event is InputEventKey and event.pressed and event.keycode == KEY_DOWN) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_DOWN):
			menu_direction = 1
		if menu_direction != 0:
			menu_index = posmod(menu_index + menu_direction, _menu_count())
			audio_director.menu_action(false)
		if screen == "audio" and event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]:
			_adjust_audio(-1 if event.keycode == KEY_LEFT else 1)
			return
		if fresh_attack or (event is InputEventKey and event.pressed and event.keycode == KEY_ENTER):
			_activate_menu()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var point := get_global_mouse_position()
			for i in range(_menu_count()):
				if _menu_rect(i).has_point(point):
					menu_index = i
					_activate_menu()
					break
		return
	if model.player_state == "transition" or model.selection_pending:
		return
	if fresh_attack:
		attack_pressed = true
	if fresh_dodge:
		dodge_pressed = true


func _menu_count() -> int:
	match screen:
		"practice", "weapons": return 6
		"title": return 6
		"paused": return 6
		"oaths": return model.oath_candidates.size() + 1
		"settings": return 7
		"controls": return 13
		"audio": return 7
		_: return 3


func _menu_rect(index: int) -> Rect2:
	if screen in ["practice", "weapons"]:
		return Rect2(182, 111 + index * 28, 276, 24)
	if screen == "oaths":
		return Rect2(55, 109 + index * 47, 530, 42)
	if screen == "title":
		return Rect2(190, 171 + index * 25, 260, 22)
	if screen == "paused":
		return Rect2(180, 155 + index * 25, 280, 22)
	if screen == "settings":
		return Rect2(146, 107 + index * 27, 348, 24)
	if screen == "audio":
		return Rect2(146, 107 + index * 27, 348, 24)
	if screen == "controls":
		return Rect2(128, 65 + index * 19, 384, 18)
	return Rect2(206, 230 + index * 27, 228, 23)


func _activate_menu() -> void:
	audio_director.menu_action(true)
	if screen == "title":
		match menu_index:
			0:
				developer_practice = false
				if not discovered_weapons.has(starting_weapon):
					starting_weapon = "W01"
				_start_run("official", 1)
			1: _open_practice()
			2:
				screen = "weapons"
				menu_index = int(starting_weapon.trim_prefix("W")) - 1
			3:
				screen = "seed"
				seed_input = str(seed_value)
				menu_index = 0
			4: _open_settings("title")
			5: _open_codex("title")
	elif screen == "practice":
		if menu_index == 5:
			screen = "title"
			menu_index = 1
		elif menu_index < unlocked_practice:
			practice_phase = menu_index + 1
			developer_practice = false
			if not discovered_weapons.has(starting_weapon):
				starting_weapon = "W01"
			_start_run("practice", practice_phase)
	elif screen == "weapons":
		var selected := "W%02d" % (menu_index + 1)
		if menu_index == 5:
			screen = "title"
			menu_index = 2
		elif discovered_weapons.has(selected):
			starting_weapon = selected
			screen = "title"
			menu_index = 0
	elif screen == "seed":
		if menu_index == 0:
			seed_value = maxi(1, int(seed_input))
			screen = "title"
			menu_index = 3
		elif menu_index == 1:
			_new_seed()
			seed_input = str(seed_value)
		else:
			screen = "title"
			menu_index = 3
	elif screen == "oaths":
		var choice := str(model.oath_candidates[menu_index]) if menu_index < model.oath_candidates.size() else ""
		if model.choose_oath(choice):
			screen = "playing"
			menu_index = 0
	elif screen == "settings":
		match menu_index:
			0: settings.show_particles = not bool(settings.show_particles)
			1:
				settings.fullscreen = not bool(settings.fullscreen)
				_apply_display_setting()
			2:
				debug_visible = not debug_visible
				settings.debug_visible = debug_visible
			3:
				screen = settings_return
				menu_index = 0
			4:
				screen = "controls"
				menu_index = 0
			5:
				screen = "audio"
				menu_index = 0
			6: settings.reduced_effects = not bool(settings.reduced_effects)
		_save_profile_now()
	elif screen == "controls":
		if menu_index < 7:
			_begin_binding(InputSettings.ACTIONS[menu_index], false)
		elif menu_index < 10:
			_begin_binding(InputSettings.JOY_ACTIONS[menu_index - 7], true)
		elif menu_index == 10:
			settings.stick_deadzone = 0.1 if float(settings.stick_deadzone) >= 0.59 else minf(0.6, float(settings.stick_deadzone) + 0.05)
			_install_inputs()
		elif menu_index == 11:
			settings.keyboard = InputSettings.default_keyboard()
			settings.gamepad = InputSettings.default_gamepad()
			settings.stick_deadzone = 0.24
			_install_inputs()
			controls_message = "기본 조작을 복원했습니다"
		else:
			screen = "settings"
			menu_index = 4
		_save_profile_now()
	elif screen == "audio":
		_adjust_audio(1)
	elif screen == "paused":
		match menu_index:
			0: screen = "playing"
			1: _retry_run()
			2:
				_record_result("abandoned")
				screen = "title"
				menu_index = 0
			3: _retry_run(true)
			4: _open_settings("paused")
			5: _open_codex("paused")
	elif screen == "result":
		if menu_index == 0:
			_retry_run()
		elif menu_index == 2:
			_retry_run(true)
		else:
			if run_mode == "practice":
				_open_practice()
			else:
				screen = "title"
				menu_index = 0
	_clear_action_boundary()


func _clear_action_boundary() -> void:
	attack_pressed = false
	dodge_pressed = false
	model.clear_input()
	require_attack_release = attack_held
	require_dodge_release = dodge_held


func _open_settings(from_screen: String) -> void:
	settings_return = from_screen
	screen = "settings"
	menu_index = 0
	_clear_action_boundary()


func _begin_binding(action: String, joy: bool) -> void:
	capture_action = action
	capture_joy = joy
	controls_message = "새 %s을 누르세요 / Esc · Back 취소" % ("패드 버튼" if joy else "키")
	_clear_action_boundary()


func _capture_binding(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventJoypadButton) and not event.pressed:
		attack_held = false
		dodge_held = false
		require_attack_release = false
		require_dodge_release = false
		return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK):
		capture_action = ""
		controls_message = "변경을 취소했습니다"
		rebind_release_gate = true
		return
	var code := -1
	if capture_joy and event is InputEventJoypadButton and event.pressed:
		code = event.button_index
	elif not capture_joy and event is InputEventKey and event.pressed:
		code = int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	if code < 0:
		return
	var error := InputSettings.rebind(settings, capture_action, code, capture_joy)
	if not error.is_empty():
		controls_message = error + " / Esc 취소"
		return
	capture_action = ""
	controls_message = "저장했습니다 / 버튼을 놓고 계속하세요"
	_install_inputs()
	_clear_action_boundary()
	rebind_release_gate = true
	_save_profile_now()


func _adjust_audio(direction: int) -> void:
	var key: String = ["master_volume", "music_volume", "sfx_volume", "music_muted", "sfx_muted", "", ""][menu_index]
	if menu_index < 3:
		var value := float(settings[key]) + float(direction) * 0.1
		settings[key] = 0.0 if value > 1.05 else clampf(snappedf(value, 0.1), 0, 1)
	elif menu_index < 5:
		settings[key] = not bool(settings[key])
	elif menu_index == 5:
		for name in ["master_volume", "music_volume", "sfx_volume", "music_muted", "sfx_muted"]:
			settings[name] = InputSettings.defaults()[name]
	else:
		screen = "settings"
		menu_index = 5
	_save_profile_now()


func _open_codex(from_screen: String) -> void:
	codex_return = from_screen
	screen = "codex"
	codex_scroll = 0
	menu_index = 0
	_clear_action_boundary()


func _codex_entries() -> Array:
	match codex_tab:
		0: return ProfileStore.WEAPON_IDS.duplicate()
		1: return ProfileStore.ELEMENT_IDS.duplicate()
		2: return ProfileStore.OATH_IDS.duplicate()
		_: return ProfileStore.PATTERN_IDS.duplicate()


func _codex_input(event: InputEvent) -> void:
	var key := int(event.keycode) if event is InputEventKey and event.pressed else 0
	var button := int(event.button_index) if event is InputEventJoypadButton and event.pressed else -1
	var horizontal := -1 if key == KEY_LEFT or button == JOY_BUTTON_DPAD_LEFT or button == JOY_BUTTON_LEFT_SHOULDER else 1 if key in [KEY_RIGHT, KEY_TAB] or button in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER] else 0
	var vertical := -1 if key == KEY_UP or button == JOY_BUTTON_DPAD_UP else 1 if key == KEY_DOWN or button == JOY_BUTTON_DPAD_DOWN else 0
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
		var axis := 1 if event.axis_value > 0.55 else -1 if event.axis_value < -0.55 else 0
		vertical = axis if axis != 0 and axis != menu_axis_direction else 0
		menu_axis_direction = axis
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: vertical = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: vertical = 1
		elif event.button_index == MOUSE_BUTTON_LEFT and get_global_mouse_position().y < 75:
			horizontal = 0
			codex_tab = clampi(int((get_global_mouse_position().x - 56) / 132), 0, 3)
			menu_index = 0
	if horizontal != 0:
		codex_tab = posmod(codex_tab + horizontal, 4)
		menu_index = 0
	if vertical != 0:
		menu_index = posmod(menu_index + vertical, _codex_entries().size())
	codex_scroll = clampi(menu_index - 3, 0, maxi(0, _codex_entries().size() - 7))


func _pattern_id_from_cause(cause_text: String) -> String:
	if PATTERN_NAMES.has(cause_text):
		return cause_text
	for id in PATTERN_NAMES:
		if cause_text == str(PATTERN_NAMES[id]) or cause_text.begins_with(str(PATTERN_NAMES[id]) + " "):
			return str(id)
	return ""


func _apply_display_setting() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)


func _new_seed() -> void:
	# OS time never consumes any seeded combat/layout/oath stream.
	var candidate := int(Time.get_ticks_usec() % 999999999) + 1
	seed_value = candidate if candidate != seed_value else posmod(candidate, 999999999) + 1


func _open_practice() -> void:
	screen = "practice"
	menu_index = clampi(practice_phase - 1, 0, unlocked_practice - 1)
	_clear_action_boundary()


func _retry_run(new_seed: bool = false) -> void:
	if screen in ["playing", "paused"]:
		_record_result("abandoned")
	if new_seed:
		_new_seed()
	starting_weapon = run_start_weapon
	_start_run(run_mode, run_start_phase)


func _start_run(selected_mode: String = "official", start_phase: int = 1) -> void:
	run_mode = selected_mode
	run_start_phase = start_phase
	run_start_weapon = starting_weapon
	model.reset(seed_value, selected_mode, start_phase, starting_weapon)
	audio_director.start_run(selected_mode, start_phase)
	print("RUN START mode=", selected_mode, " weapon=", starting_weapon, " streams=", model.stream_states())
	screen = "playing"
	menu_index = 0
	hitstop_remaining = 0.0
	hitstop_guard = 0.0
	wall_seconds = 0.0
	attack_pressed = false
	dodge_pressed = false
	particles.clear()
	notices.clear()
	result_recorded = false
	pattern_hit_stamps.clear()
	run_element_uses = {"fire":0, "frost":0, "lightning":0, "void":0}
	attack_event_tick = -1
	was_transition = false
	require_attack_release = attack_held
	require_dodge_release = dodge_held


func _record_result(value: String) -> void:
	if result_recorded or model.mode != "official" or developer_practice or value == "safety_error":
		return
	result_recorded = true
	official_records.append({"result": value, "phase": model.highest_phase_reached, "seed": seed_value,
		"seconds": wall_seconds, "ticks": model.tick, "weapon_id": model.weapon_id, "oaths": model.oaths.duplicate(), "element_uses":run_element_uses.duplicate()})
	profile.best_record = ProfileStore.best_record(official_records, profile.get("best_record", {}))
	if official_records.size() > ProfileStore.MAX_RECORDS:
		official_records = official_records.slice(-ProfileStore.MAX_RECORDS)
	_save_profile_now()


func _physics_process(delta: float) -> void:
	if closing:
		return
	if screen == "playing" and model.selection_pending:
		screen = "oaths"
		menu_index = 0
		_clear_action_boundary()
	if screen != "playing":
		_update_audio(delta)
		attack_pressed = false
		dodge_pressed = false
		return
	wall_seconds += delta
	hitstop_guard = maxf(0.0, hitstop_guard - delta)
	var command := {
		"move": Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"attack": attack_pressed,
		"dodge": dodge_pressed,
	}
	attack_pressed = false
	dodge_pressed = false
	# 67 ms is four 60 Hz steps rounded to the nearest half millisecond.
	if hitstop_remaining > 0.0005:
		_update_audio(delta)
		model.queue_frozen_input(command)
		hitstop_remaining = maxf(0.0, hitstop_remaining - delta)
		return
	model.step(command)
	_read_events()
	if model.selection_pending:
		screen = "oaths"
		menu_index = 0
		_clear_action_boundary()
	var transition_now: bool = model.player_state == "transition"
	if transition_now or was_transition:
		attack_pressed = false
		dodge_pressed = false
		model.clear_input()
		require_attack_release = attack_held
		require_dodge_release = dodge_held
	was_transition = transition_now
	if model.mode == "official" and not developer_practice:
		unlocked_practice = maxi(unlocked_practice, model.highest_phase_reached)
		_save_practice_progress()
	if model.hitstop_ms > 0.0:
		if hitstop_guard <= 0.0:
			hitstop_remaining = model.hitstop_ms / 1000.0
			hitstop_guard = 0.1
		model.hitstop_ms = 0.0
	if not model.result.is_empty():
		_record_result(model.result)
		screen = "result"
		menu_index = 0
	_update_audio(delta)


func _update_audio(delta: float) -> void:
	if audio_director == null: return
	audio_director.set_suspended(screen in ["paused", "settings", "controls", "audio", "codex", "oaths"] or (screen == "playing" and hitstop_remaining > 0.0005))
	audio_director.update(model, screen, delta)


func _process(delta: float) -> void:
	cosmetic_time += delta
	for i in range(particles.size() - 1, -1, -1):
		particles[i]["life"] -= delta
		particles[i]["pos"] += particles[i]["vel"] * delta
		if particles[i]["life"] <= 0.0:
			particles.remove_at(i)
	for i in range(notices.size() - 1, -1, -1):
		notices[i]["life"] -= delta
		if notices[i]["life"] <= 0.0:
			notices.remove_at(i)
	queue_redraw()
	if not capture_path.is_empty() and not capture_done and model.tick >= capture_tick:
		capture_wait -= 1
		if capture_wait <= 0:
			capture_done = true
			_capture.call_deferred()
	if smoke and model.tick >= 120:
		print("PRESENTATION_SMOKE_OK ticks=", model.tick, " viewport=", get_viewport_rect().size)
		_request_quit(0, false)


func _save_practice_progress() -> void:
	if not profile_enabled or unlocked_practice <= profile_saved_phase:
		return
	profile_saved_phase = unlocked_practice
	_save_profile_now()


func _save_profile_now() -> void:
	if audio_director != null:
		audio_director.configure(settings)
	if not profile_enabled:
		return
	profile.settings = settings.duplicate(true)
	profile.discovered_weapons = discovered_weapons.duplicate()
	profile.highest_phase = unlocked_practice
	profile.official_records = official_records.duplicate(true)
	profile.best_record = ProfileStore.best_record(official_records, profile.get("best_record", {}))
	var error := ProfileStore.save_profile(profile_path, profile)
	if error != OK:
		notices.append({"text": "저장하지 못했습니다 / 현재 실행의 진행은 유지됩니다", "life": 6.0})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit(0, true)


func _request_quit(exit_code: int = 0, save_run: bool = true) -> void:
	if closing:
		return
	closing = true
	# Persist before the asynchronous mixer drain, so another close event cannot
	# duplicate a record or accept any further combat/menu input.
	if save_run:
		if screen in ["playing", "paused", "oaths"] or (screen in ["settings", "controls", "audio"] and settings_return == "paused") or (screen == "codex" and codex_return == "paused"):
			_record_result("abandoned")
		_save_profile_now()
	_clear_action_boundary()
	capture_done = true
	set_physics_process(false)
	set_process(false)
	if audio_director != null:
		await audio_director.shutdown()
	get_tree().quit(exit_code)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(capture_path)
	print("CAPTURE ", capture_path, " error=", error)
	await _request_quit(int(error), false)


func _read_events() -> void:
	if audio_director != null:
		audio_director.consume_events(model.events, model)
	for event in model.events:
		var type: String = str(event.get("type", ""))
		if type == "attack":
			var element := str(event.get("element", ""))
			if run_element_uses.has(element) and attack_event_tick != model.tick:
				run_element_uses[element] += 1
				attack_event_tick = model.tick
		elif type in ["boss_hit", "damage_boss", "hit_boss"]:
			var position: Vector2 = event.get("pos", model.boss_pos - Vector2(0, 20))
			_emit_sparks(position, EMBER)
		elif type in ["player_hit", "damage_player", "hit_player"]:
			_emit_sparks(model.player_pos - Vector2(0, 8), Color("e27265"))
			if model.mode == "official" and not developer_practice:
				var id := _pattern_id_from_cause(str(event.get("cause", "")))
				if not id.is_empty() and int(pattern_hit_stamps.get(id, -1)) != model.tick:
					pattern_hit_stamps[id] = model.tick
					profile.pattern_hit_counts[id] = mini(1000000, int(profile.pattern_hit_counts.get(id, 0)) + 1)
					_save_profile_now()
		elif type in ["pickup", "pickup_collected", "fire_collected"]:
			var element: String = str(event.get("element", model.element_id))
			_emit_sparks(model.player_pos - Vector2(0, 8), _element_color(element))
			notices.append({"text": "%s ACQUIRED / RELEASE, THEN PRESS ATTACK" % _element_name(element), "life": 1.8})
		elif type == "phase_reached":
			if model.mode == "official" and not developer_practice:
				unlocked_practice = maxi(unlocked_practice, int(event.get("phase", model.phase_id)))
		elif type == "phase_transition":
			particles.clear()
			notices.clear()
		elif type == "phase_started":
			notices.append({"text": "P%d / %s" % [model.phase_id, PHASE_WORDS[model.phase_id - 1]], "life": 1.6})
		elif type == "weapon_swap":
			var weapon: String = str(event.weapon)
			notices.append({"text": "%s / 스택 초기화 / 기운 유지" % _weapon_name(weapon), "life": 2.6})
			if model.mode == "official" and not developer_practice and not discovered_weapons.has(weapon):
				discovered_weapons.append(weapon)
				_save_profile_now()
		elif type == "telegraph" and model.mode == "official" and not developer_practice:
			var id := str(event.get("pattern", ""))
			if not id.is_empty() and not profile.seen_patterns.has(id):
				profile.seen_patterns.append(id)
				_save_profile_now()


func _emit_sparks(position: Vector2, color: Color) -> void:
	if not bool(settings.show_particles) or bool(settings.reduced_effects):
		return
	for i in range(7):
		var angle := cosmetic_time * 3.7 + float(i) * TAU / 7.0
		particles.append({"pos": position, "vel": Vector2.from_angle(angle) * (12.0 + i * 4.0), "life": 0.35 + i * 0.025, "color": color})


func _draw() -> void:
	pixel_art.reduced_effects = bool(settings.reduced_effects)
	draw_rect(Rect2(0, 0, 640, 360), BG)
	_draw_arena()
	_draw_altars()
	for pickup in model.pickups:
		_draw_pickup(pickup)
	# Cosmetic fragments stay below the actors and the shared danger geometry.
	for particle in particles:
		var color: Color = particle["color"]
		color.a = clampf(particle["life"] * 2.5, 0.0, 1.0)
		draw_rect(Rect2((particle["pos"] as Vector2).round(), Vector2(2, 2)), color)
	if model.player_pos.y < model.boss_pos.y:
		_draw_player()
		_draw_boss()
	else:
		_draw_boss()
		_draw_player()
	# Ground danger outlines stay visible even where large silhouettes overlap.
	for hazard in model.hazards:
		_draw_hazard(hazard)
	_draw_attack()
	_draw_hud()
	if debug_visible:
		_draw_debug()
	if screen == "title":
		_draw_title()
	elif screen == "practice":
		_draw_practice()
	elif screen == "paused":
		_draw_pause()
	elif screen == "result":
		_draw_result()
	elif screen == "weapons":
		_draw_weapons()
	elif screen == "seed":
		_draw_seed()
	elif screen == "settings":
		_draw_settings()
	elif screen == "oaths":
		_draw_oaths()
	elif screen == "controls":
		_draw_controls()
	elif screen == "audio":
		_draw_audio_settings()
	elif screen == "codex":
		_draw_codex()
	elif model.player_state == "transition":
		_draw_transition()


func _ellipse(center: Vector2, radii: Vector2, count: int = 96) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(count):
		var angle := float(i) * TAU / float(count)
		points.append((center + Vector2(cos(angle), sin(angle)) * radii).round())
	return points


func _draw_arena() -> void:
	pixel_art.draw_arena(self, model, cosmetic_time)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not points.is_empty():
		closed.append(points[0])
	return closed


func _sector(origin: Vector2, facing: Vector2, radius: float, arc: float) -> PackedVector2Array:
	var points := PackedVector2Array([origin])
	var center_angle := facing.angle()
	for i in range(33):
		points.append(origin + Vector2.from_angle(center_angle - arc / 2.0 + arc * i / 32.0) * radius)
	return points


func _draw_hazard(hazard: Dictionary) -> void:
	var origin: Vector2 = hazard.get("origin", model.boss_pos)
	var facing: Vector2 = hazard.get("facing", Vector2.DOWN)
	var active: bool = hazard.get("phase", "telegraph") == "active"
	var echo: bool = bool(hazard.get("echo", false)) or bool(hazard.get("dashed", false))
	var progress: float = clampf(float(hazard.get("progress", 0)), 0.0, 1.0)
	var outline := Color("f1d7b2") if active else VOID if echo else Color("9eb6aa")
	var fill := Color(0.93, 0.61, 0.36, 0.30) if active else Color(outline, 0.045 + progress * 0.11)
	var shape: String = hazard.get("shape", "sector")
	# The exact same shape dictionary drives collision and clipped fill geometry.
	for polygon in Geometry.polygons(hazard):
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, fill)
	if shape == "sector":
		var radius: float = float(hazard.get("radius", 56))
		var arc: float = float(hazard.get("arc_radians", deg_to_rad(140)))
		var points := Geometry.polygon(hazard)
		_outline(points, outline, echo, active)
		draw_arc(origin, radius - 3, facing.angle() - arc / 2, facing.angle() - arc / 2 + arc * maxf(progress, 0.001), 40, EMBER, 1.0)
	elif shape in ["line", "capsule"]:
		var length: float = float(hazard.get("length", 196))
		var width: float = float(hazard.get("width", 24))
		var side := facing.orthogonal() * width / 2.0
		var end: Vector2 = hazard.get("end", origin + facing * length)
		var points := Geometry.polygon(hazard)
		_outline(points, outline, echo, active)
		draw_line(origin, origin.lerp(end, progress), EMBER, 2)
		for i in range(1, 6):
			var point := origin + facing * (length * i / 6.0)
			draw_line(point - side * 0.28, point + side * 0.28, outline, 1)
	elif shape == "ring":
		var radius: float = float(hazard.get("radius", 28))
		var width: float = float(hazard.get("width", 8))
		draw_arc(origin, radius - width / 2.0, 0, TAU, 128, outline, 1)
		draw_arc(origin, radius + width / 2.0, 0, TAU, 128, outline, 1)
		if not active:
			draw_arc(origin, radius, -PI / 2, -PI / 2 + TAU * maxf(progress, 0.001), 96, EMBER, 2)
	elif shape in ["disk", "annulus"]:
		var radius: float = float(hazard.get("inner_radius", 64.0)) if shape == "annulus" else float(hazard.get("radius", 64.0))
		_outline(_ellipse(origin, Vector2.ONE * radius), outline, echo, active)
		if not active:
			draw_arc(origin, radius - 3, -PI / 2, -PI / 2 + TAU * maxf(progress, 0.001), 64, EMBER, 1)
		# Fine boundary circles mark the player's 6 px foot radius, so a center
		# on the nominal boundary is visibly still unsafe.
		if shape == "annulus":
			draw_arc(origin, maxf(1, radius - 6), 0, TAU, 80, Color(outline, 0.28), 1)
		else:
			draw_arc(origin, radius + 6, 0, TAU, 80, Color(outline, 0.28), 1)
	elif shape == "corridor":
		for polygon in Geometry.polygons(hazard):
			_outline(polygon, outline, echo, active)
	var number := int(hazard.get("number", 0))
	if number > 0:
		var label: Vector2 = hazard.get("label_pos", origin + facing * 24.0)
		if shape in ["disk", "annulus", "ring"]:
			var boundary := float(hazard.get("inner_radius", 64)) if shape == "annulus" else float(hazard.get("radius", 64))
			label = origin + Vector2((number - 1) * 15 - 15, -boundary - 9)
		label = Vector2(clampf(label.x, 25, 615), clampf(label.y, 66, 296))
		draw_circle(label, 6, BG)
		draw_arc(label, 6, 0, TAU, 16, outline, 1)
		_text(str(number), label + Vector2(-3, 3), 9, outline)


func _outline(points: PackedVector2Array, color: Color, dashed: bool = false, active: bool = false) -> void:
	if points.size() < 2:
		return
	if dashed and not active:
		var distance := 0.0
		for i in range(points.size()):
			var start := points[i]
			var finish := points[(i + 1) % points.size()]
			var length := start.distance_to(finish)
			var count := maxi(1, ceili(length))
			for j in range(count):
				if int(distance + float(j) * length / count) % 7 < 4:
					draw_line(start.lerp(finish, float(j) / count), start.lerp(finish, float(j + 1) / count), color, 1)
			distance += length
	else:
		draw_polyline(_closed(points), color, 2.0 if active else 1.0)


func _draw_player() -> void:
	pixel_art.draw_player(self, model, cosmetic_time)


func _draw_boss() -> void:
	pixel_art.draw_boss(self, model, cosmetic_time)


func _draw_attack() -> void:
	if model.attack.is_empty() or model.player_state != "attack":
		return
	var age: int = int(model.attack.get("age", model.state_age))
	var definition: Dictionary = model.attack.get("definition", model.weapon_definition())
	var visible := false
	for window in definition.hit_windows:
		if age >= int(window[0]) and age < int(window[1]):
			visible = true
	if not visible:
		return
	var kind: String = model.attack.get("kind", "basic")
	var shape: Dictionary = model.player_attack_shape()
	var element: String = str(model.attack.get("element", ""))
	var color := _element_color(element) if not element.is_empty() else EMBER if kind == "signature" else ASH
	for polygon in Geometry.polygons(shape):
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, Color(color, 0.13))
			_outline(polygon, color, false, true)
	if kind == "resonance":
		for polygon in Geometry.polygons(shape):
			_outline(polygon, Color("f4e8a4"), true)


func _weapon_name(id: String) -> String:
	return str(model.data.weapons.get(id, {}).get("name", id))


func _draw_weapon(p: Vector2, direction: Vector2, id: String, scale_value: float = 1.0) -> void:
	pixel_art.draw_weapon(self, p, direction, id, scale_value)


func _draw_altars() -> void:
	for altar in model.altars:
		var p: Vector2 = altar.pos
		var progress := float(altar.progress) / 33.0
		pixel_art.draw_altar(self, altar, cosmetic_time)
		if progress > 0:
			_centered("제단 교체 %.0f%% / 교체 시 스택 초기화 · 기운 유지" % (progress * 100), 285, 10, EMBER, true)
		elif p.distance_to(model.player_pos) < 28:
			_text("가만히 서서 교체", p + Vector2(-30, 23), 8, ASH, true)


func _draw_pickup(pickup: Dictionary) -> void:
	pixel_art.draw_pickup(self, pickup, model)


func _element_name(element: String) -> String:
	return {"fire": "FLAME", "frost": "FROST", "lightning": "LIGHTNING", "void": "VOID"}.get(element, "NONE")


func _element_color(element: String) -> Color:
	return {"fire": FIRE, "frost": FROST, "lightning": LIGHTNING, "void": VOID}.get(element, EMBER)


func _draw_element(p: Vector2, size: float, element: String, muted: bool = false) -> void:
	var color := Color("304346") if muted else _element_color(element)
	match element:
		"frost":
			_outline(_ellipse(p, Vector2.ONE * size, 6), color)
			draw_line(p + Vector2(-size * 0.6, 0), p + Vector2(size * 0.6, 0), color, 1)
		"lightning":
			var zigzag := PackedVector2Array([p + Vector2(1, -size), p + Vector2(-size * 0.7, 1), p + Vector2(size * 0.4, -1), p + Vector2(-1, size)])
			draw_polyline(zigzag, color, 2)
		"void":
			draw_arc(p, size, 0, TAU, 16, color, 2)
		_:
			_draw_flame(p, size, color)


func _draw_flame(p: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array([p + Vector2(0, -size * 1.2), p + Vector2(size, size * 0.7), p + Vector2(size * 0.15, size * 0.35), p + Vector2(-size * 0.7, size * 0.8)])
	draw_colored_polygon(points, color)
	draw_line(p + Vector2(0, -size * 0.4), p + Vector2(1, size * 0.3), Color("f8d6a0"), 1)


func _text(value: String, point: Vector2, size: int = 10, color: Color = ASH, korean: bool = false) -> void:
	draw_string(korean_font if korean else font, point.round(), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _centered(value: String, y: float, size: int = 12, color: Color = ASH, korean: bool = false) -> void:
	var selected_font: Font = korean_font if korean else font
	var width := selected_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, Vector2((640 - width) / 2.0, y), size, color, korean)


func _draw_hud() -> void:
	_text("THE ONE", Vector2(22, 22), 15, Color("b8bca8"))
	_text("FIRST EMBER", Vector2(23, 33), 8, MUTED)
	_text("P%d / %s" % [model.phase_id, model.mode.to_upper()], Vector2(498, 21), 9, MUTED)
	_text("F1  DEBUG", Vector2(541, 33), 8, MUTED)
	_text(" ".join(model.oaths), Vector2(22, 46), 8, MUTED)
	_centered("무저 / " + PHASE_NAMES[model.phase_id - 1], 18, 11, ASH, true)
	for i in range(5):
		var rect := Rect2(184 + i * 55, 25, 52, 6)
		var phase := i + 1
		var remaining := clampf(model.boss_hp / model.phase_hp_max, 0, 1) if phase == model.phase_id else 1.0 if phase > model.phase_id else 0.0
		draw_rect(rect, Color("0a1418"))
		draw_rect(Rect2(rect.position + Vector2.ONE, Vector2(50 * remaining, 4)), Color("b5b09a") if phase == model.phase_id else Color("4d6260"))
		draw_rect(rect, EMBER if phase == model.phase_id else Color("405453"), false, 1)
		_text("P%d" % phase, rect.position + Vector2(19, 15), 7, EMBER if phase == model.phase_id else MUTED)
	if screen == "playing" or screen == "paused":
		var hint := "거리와 빈틈을 읽고, 최초의 힘을 빼앗으세요"
		if model.boss_state == "telegraph":
			hint = PATTERN_NAMES.get(model.boss_pattern, "") + " / 형상 · 진행 · 순서를 확인하세요"
		elif model.boss_state == "recover":
			hint = "공격 기회 / 다음 예고에 대비하세요"
		elif model.boss_state == "execute":
			hint = PATTERN_NAMES.get(model.boss_pattern, "") + " / 공격이 끝날 때까지 읽으세요"
		_centered(hint, 53, 10, EMBER if model.boss_state == "recover" else MUTED, true)
		_draw_sequence()
	# The lower margin lies entirely outside the playable ellipse.
	draw_rect(Rect2(0, 315, 640, 45), Color("081216"))
	draw_line(Vector2(20, 315), Vector2(620, 315), Color("293d3f"), 1)
	_text("LIFE", Vector2(23, 328), 9, MUTED)
	_text("%03d / %d" % [ceili(maxf(0.0, model.player_hp)), int(model.player_max_hp())], Vector2(23, 341), 9, ASH)
	draw_rect(Rect2(90, 322, 101, 6), Color("233336"))
	draw_rect(Rect2(90, 322, 100.0 * maxf(0, model.player_hp) / model.player_max_hp(), 6), Color("adbaa2"))
	_text(_weapon_name(model.weapon_id), Vector2(90, 341), 9, MUTED, true)
	_text("STACK", Vector2(219, 328), 8, MUTED)
	for i in range(model.stack_threshold()):
		var color := EMBER if i < model.stacks else Color("263c3f")
		draw_rect(Rect2(243 + i * 6, 322, 4, 6), color)
	_text(_element_name(model.element_id), Vector2(212, 341), 7, _element_color(model.element_id) if model.element_charges > 0 else MUTED)
	for i in range(model.element_charges):
		_draw_element(Vector2(278 + i * 10, 338), 3, model.element_id)
	var kind: String = model.next_attack_kind()
	var name_text: String = {"basic": "기본 공격", "signature": str(model.weapon_definition().signature_name), "fire": "화염 공격", "frost": "서리 공격", "lightning": "번개 공격", "void": "공허 공격", "resonance": "공명 · " + str(model.weapon_definition().signature_name)}.get(kind, kind)
	_text("NEXT", Vector2(326, 328), 8, MUTED)
	_text(name_text, Vector2(359, 329), 12, _element_color(model.element_id) if model.element_charges > 0 else EMBER if kind == "signature" else ASH, true)
	_text("RESONANCE + " + _element_name(model.element_id) if kind == "resonance" else "PRESS " + InputSettings.keyboard_label(settings, "attack"), Vector2(359, 342), 8, MUTED)
	_text("%02d:%02d" % [int(wall_seconds) / 60, int(wall_seconds) % 60], Vector2(551, 329), 12, ASH)
	_text("P%d %04d" % [model.phase_id, ceili(maxf(0, model.boss_hp))], Vector2(551, 342), 8, MUTED)
	_centered("%s  공격   %s  회피   %s / Esc  일시정지" % [InputSettings.keyboard_label(settings, "attack"), InputSettings.keyboard_label(settings, "dodge"), InputSettings.keyboard_label(settings, "pause")], 355, 8, MUTED, true)
	if not notices.is_empty():
		_centered(notices[-1]["text"], 299, 10, EMBER, true)
	if developer_practice and screen == "playing":
		_text("DEV PRACTICE / DOES NOT UNLOCK PROGRESS", Vector2(23, 309), 8, VOID)


func _draw_sequence() -> void:
	var sequence: Dictionary = {}
	for hazard in model.hazards:
		var number := int(hazard.get("number", 0))
		if number > 0 and not sequence.has(number):
			sequence[number] = hazard
	var numbers := sequence.keys()
	numbers.sort()
	for index in range(numbers.size()):
		var hazard: Dictionary = sequence[numbers[index]]
		var active: bool = hazard.get("phase", "telegraph") == "active"
		var seconds := maxf(0, float(int(hazard.get("start_tick", model.boss_age)) - model.boss_age) / 60.0)
		var color := EMBER if active else VOID if bool(hazard.get("echo", false)) else ASH
		var x := 320.0 - numbers.size() * 24.0 + index * 48.0
		draw_rect(Rect2(x, 59, 45, 13), Color(BG, 0.85))
		_text("%d %s" % [numbers[index], "NOW" if active else "%.1f" % seconds], Vector2(x + 3, 69), 8, color)


func _draw_debug() -> void:
	draw_arc(model.player_pos, float(model.data.player.radius), 0, TAU, 24, Color("a8edbb"), 1)
	draw_arc(model.boss_pos, float(model.data.boss.body_radius), 0, TAU, 32, Color("65a1bc"), 1)
	draw_arc(model.boss_pos, float(model.data.boss.hurt_radius), 0, TAU, 32, Color("ba86c9"), 1)
	draw_line(model.player_pos, model.player_pos + model.player_facing * 24, Color("a8edbb"), 1)
	draw_rect(Rect2(12, 76, 250, 82), Color(0.01, 0.03, 0.04, 0.90))
	_text("MODE %s | SEED %d" % [model.mode, seed_value], Vector2(18, 88), 9, EMBER)
	_text("TICK %d  WALL %.2fs" % [model.tick, wall_seconds], Vector2(18, 99), 9)
	_text("PLAYER %s age=%d inv=%s" % [model.player_state, model.state_age, str(model.is_player_invulnerable())], Vector2(18, 110), 9)
	_text("BOSS P%d %s %s %d" % [model.phase_id, model.boss_pattern, model.boss_state, model.boss_age], Vector2(18, 121), 9)
	_text("ELEMENT %s:%d | FROST %d" % [model.element_id, model.element_charges, maxi(0, model.frost_guard_until - model.tick)], Vector2(18, 132), 9)
	_text("HITSTOP %.0fms | TRANSITION %d" % [hitstop_remaining * 1000, model.transition_ticks_remaining], Vector2(18, 143), 9)
	_text("TOTAL HP %.1f | UNLOCK P%d" % [model.total_boss_hp(), unlocked_practice], Vector2(18, 154), 9)
	if not model.attack.is_empty():
		draw_polyline(_closed(Geometry.polygon(model.player_attack_shape())), Color("7fbe91"), 1)


func _overlay() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color(0.015, 0.035, 0.045, 0.91))
	var top := 62 if screen == "practice" else 82
	draw_line(Vector2(215, top), Vector2(425, top), Color("3a5150"), 1)
	draw_line(Vector2(215, 304), Vector2(425, 304), Color("3a5150"), 1)


func _button(label: String, index: int, enabled: bool = true, korean: bool = false) -> void:
	var rect := _menu_rect(index)
	var selected := menu_index == index
	draw_rect(rect, Color("2d4141") if selected else Color("101e23"))
	draw_rect(rect, Color("a0aa96") if selected else Color("324b4c"), false, 1)
	_centered(label, rect.position.y + 16, 10, Color("eee2bf") if selected and enabled else MUTED if enabled else Color("465a5b"), korean)
	if selected:
		var x := rect.position.x - 10
		draw_colored_polygon(PackedVector2Array([Vector2(x, rect.position.y + 8), Vector2(x + 4, rect.position.y + 12), Vector2(x, rect.position.y + 16)]), EMBER)


func _draw_title() -> void:
	_overlay()
	_centered("THE ONE", 101, 40, Color("d1d0b7"))
	_centered("최초의 불씨", 127, 17, ASH, true)
	_centered("아직, 첫날은 오지 않았다.", 153, 10, MUTED, true)
	_button("정식 도전 / P1부터 시작", 0, true, true)
	_button("잔향 연습 / 도달한 페이즈", 1, true, true)
	_button("시작 무기 / " + _weapon_name(starting_weapon), 2, true, true)
	_button("시드 / %d" % seed_value, 3, true, true)
	_button("설정 / 로컬 저장", 4, true, true)
	_button("불씨의 기록 / 도감", 5, true, true)
	_centered("UP / DOWN SELECT   J / ENTER / X CONFIRM", 333, 8, ASH)
	var best: Dictionary = profile.get("best_record", {})
	var footer := "M5 / THE FIRST EMBER / FIVE PHASES · ONE WAR"
	if not best.is_empty():
		footer = "BEST %.1fs / SEED %d / %s" % [float(best.get("seconds", 0)), int(best.get("seed", 1)), str(best.get("weapon_id", "W01"))]
	_centered(footer, 348, 8, MUTED)
	if not notices.is_empty():
		_centered(notices[-1]["text"], 65, 9, EMBER, true)


func _draw_weapons() -> void:
	_overlay()
	_centered("시작 무기", 88, 22, ASH, true)
	_centered("정식 도전의 제단에서 교체하면 다음 도전부터 선택", 103, 9, MUTED, true)
	for i in range(5):
		var id := "W%02d" % (i + 1)
		var found := discovered_weapons.has(id)
		_button(_weapon_name(id) + ("  [선택됨]" if id == starting_weapon else "" if found else "  [미발견]"), i, found, true)
		_draw_weapon(Vector2(199, 127 + i * 28), Vector2(0.7, -0.7), id, 0.55)
	_button("돌아가기 / ESC", 5, true, true)
	_centered("발견은 위력을 올리지 않습니다 / 연습에서는 새 발견 없음", 321, 10, MUTED, true)
	_centered("선택 무기: " + _weapon_name(starting_weapon), 339, 10, EMBER, true)


func _draw_seed() -> void:
	_overlay()
	_centered("도전의 시드", 116, 23, ASH, true)
	_centered("%s_" % seed_input, 158, 24, EMBER)
	_centered("숫자 1~999999999 / BACKSPACE 지우기", 180, 10, MUTED, true)
	_centered("제단 배치 · 각인 후보 · 보스 순서 · P5 기운에 반영", 202, 9, MUTED, true)
	_button("입력한 시드 사용", 0, true, true)
	_button("새 시드 뽑기", 1, true, true)
	_button("돌아가기", 2, true, true)
	_centered("같은 시드여도 이동과 선택에 따라 전투가 달라집니다", 325, 9, MUTED, true)


func _draw_settings() -> void:
	_overlay()
	_centered("설정", 77, 24, ASH, true)
	_centered("변경 즉시 로컬 프로필에 저장됩니다", 96, 10, MUTED, true)
	_button("장식 파티클: " + ("켜짐" if bool(settings.show_particles) else "꺼짐"), 0, true, true)
	_button("화면: " + ("전체 화면" if bool(settings.fullscreen) else "창 모드"), 1, true, true)
	_button("개발 판정 표시: " + ("켜짐" if debug_visible else "꺼짐"), 2, true, true)
	_button("돌아가기 / ESC", 3, true, true)
	_button("조작 재지정 / 키보드 · 게임패드", 4, true, true)
	_button("음향 / 음량 · 음악 · 효과음", 5, true, true)
	_button("효과 줄이기: " + ("켜짐" if bool(settings.reduced_effects) else "꺼짐"), 6, true, true)
	_centered("위험 예고와 공격 판정은 효과 설정과 관계없이 표시", 321, 9, MUTED, true)
	_centered("진행 중 전투는 저장하지 않습니다", 340, 10, EMBER, true)


func _draw_controls() -> void:
	_overlay()
	_centered("조작 재지정", 39, 21, ASH, true)
	_centered("메뉴는 방향키 · Enter · Esc로 언제든 조작할 수 있습니다", 55, 9, MUTED, true)
	for i in range(7):
		var action: String = InputSettings.ACTIONS[i]
		_button("키보드  %s : %s" % [InputSettings.NAMES[action], InputSettings.keyboard_label(settings, action)], i, true, true)
	for i in range(3):
		var action: String = InputSettings.JOY_ACTIONS[i]
		_button("패드  %s : %s" % [InputSettings.NAMES[action], InputSettings.gamepad_label(settings, action)], i + 7, true, true)
	_button("왼쪽 스틱 데드존 : %.0f%%" % (float(settings.stick_deadzone) * 100), 10, true, true)
	_button("기본 조작 복원", 11, true, true)
	_button("돌아가기 / ESC", 12, true, true)
	_centered(controls_message if not controls_message.is_empty() else "항목 선택 후 새 키 / 버튼 · 중복 불가 · R/F1/Enter/Tab 예약", 330, 9, EMBER, true)
	_centered("이동은 왼쪽 스틱 / 패드 메뉴는 D-pad · LB/RB도 지원", 348, 8, MUTED, true)
	if not capture_action.is_empty():
		draw_rect(Rect2(68, 125, 504, 88), Color("0b181e"))
		draw_rect(Rect2(68, 125, 504, 88), EMBER, false, 1)
		_centered(InputSettings.NAMES[capture_action] + " / " + ("패드 버튼" if capture_joy else "키보드"), 150, 16, ASH, true)
		_centered(controls_message, 181, 10, EMBER, true)


func _draw_audio_settings() -> void:
	_overlay()
	_centered("음향", 77, 24, ASH, true)
	_centered("좌우로 10%씩 조절 / 확인으로 증가", 96, 10, MUTED, true)
	_button("전체 음량 : %.0f%%" % (float(settings.master_volume) * 100), 0, true, true)
	_button("음악 음량 : %.0f%%" % (float(settings.music_volume) * 100), 1, true, true)
	_button("효과음 음량 : %.0f%%" % (float(settings.sfx_volume) * 100), 2, true, true)
	_button("음악 : " + ("음소거" if settings.music_muted else "켜짐"), 3, true, true)
	_button("효과음 : " + ("음소거" if settings.sfx_muted else "켜짐"), 4, true, true)
	_button("음향 기본값 복원", 5, true, true)
	_button("돌아가기 / ESC", 6, true, true)
	_centered("소리를 꺼도 형상과 진행 표시로 모든 공격을 읽을 수 있습니다", 324, 9, MUTED, true)
	_centered("일시정지 · 각인 선택 · 히트스톱에서 전투 소리도 멈춥니다", 343, 9, MUTED, true)


func _draw_codex() -> void:
	_overlay()
	_centered("불씨의 기록", 35, 23, ASH, true)
	var tabs := ["무기", "기운", "각인", "무저의 기억"]
	for i in range(4):
		var rect := Rect2(56 + i * 132, 49, 128, 22)
		draw_rect(rect, Color("344645") if i == codex_tab else Color("101e23"))
		_text(tabs[i], rect.position + Vector2(12, 15), 11, EMBER if i == codex_tab else MUTED, true)
	var entries := _codex_entries()
	for i in range(codex_scroll, mini(entries.size(), codex_scroll + 7)):
		var id: String = str(entries[i])
		var known: bool = discovered_weapons.has(id) if codex_tab == 0 else profile.seen_patterns.has(id) if codex_tab == 3 else true
		var label: String = _weapon_name(id) if codex_tab == 0 else str(codex.elements[id].name) if codex_tab == 1 else str(model.data.oaths[id].name) if codex_tab == 2 else str(PATTERN_NAMES[id])
		if not known: label = "미발견 무기" if codex_tab == 0 else "아직 보지 못한 기억"
		var y := 91 + (i - codex_scroll) * 29
		draw_rect(Rect2(56, y - 14, 174, 25), Color("344645") if menu_index == i else Color("101e23"))
		_text("%02d  %s" % [i + 1, label], Vector2(64, y + 3), 10, EMBER if menu_index == i else MUTED, true)
	var selected: String = str(entries[menu_index])
	var known: bool = discovered_weapons.has(selected) if codex_tab == 0 else profile.seen_patterns.has(selected) if codex_tab == 3 else true
	var name: String = _weapon_name(selected) if codex_tab == 0 else str(codex.elements[selected].name) if codex_tab == 1 else str(model.data.oaths[selected].name) if codex_tab == 2 else str(PATTERN_NAMES[selected])
	_text(name if known else "아직 기록되지 않은 가능성", Vector2(251, 100), 17, ASH, true)
	if not known:
		_draw_wrapped("정식 도전에서 제단의 무기를 쥐면 기록됩니다." if codex_tab == 0 else "정식 도전에서 이 공격을 마주하면 기록됩니다.", Vector2(251, 132), 325, MUTED)
	elif codex_tab == 0:
		var data: Dictionary = model.data.weapons[selected]
		_draw_wrapped(str(codex.weapons[selected].description), Vector2(251, 129), 325, ASH)
		_text("준비 %d / 실행 %d / 회복 %d 틱" % [data.startup_ticks, data.active_ticks, data.recovery_ticks], Vector2(251, 177), 10, MUTED, true)
		_text("사거리 %dpx · 스택 %d · 비기 %s" % [data.reach, data.stack_threshold, data.signature_name], Vector2(251, 196), 10, EMBER, true)
		_draw_wrapped(str(codex.weapons[selected].principle), Vector2(251, 224), 325, MUTED)
	elif codex_tab == 1:
		_draw_element(Vector2(557, 97), 9, selected)
		_draw_wrapped(str(codex.elements[selected].description), Vector2(251, 133), 325, ASH)
		_draw_wrapped(str(codex.elements[selected].principle), Vector2(251, 214), 325, MUTED)
	elif codex_tab == 2:
		var oath: Dictionary = model.data.oaths[selected]
		_draw_wrapped("이점 / " + str(oath.benefit), Vector2(251, 135), 325, ASH)
		_draw_wrapped("부담 / " + str(oath.burden), Vector2(251, 190), 325, EMBER)
		var exclusions: Array[String] = []
		for id in oath.excludes: exclusions.append(str(model.data.oaths[id].name))
		_draw_wrapped("함께 새길 수 없음 / " + (" · ".join(exclusions) if not exclusions.is_empty() else "없음"), Vector2(251, 247), 325, MUTED)
	else:
		_draw_wrapped(str(codex.patterns[selected].description), Vector2(251, 135), 325, ASH)
		var count := int(profile.pattern_hit_counts.get(selected, 0))
		_text("정식 도전 피격 경험 / %d" % count, Vector2(251, 192), 10, MUTED, true)
		_draw_wrapped(_codex_pattern_hint(selected), Vector2(251, 220), 325, EMBER if count >= 2 else MUTED)
	_centered("좌우 / Tab / LB·RB  분류   위아래 / 스크롤  기록   Esc / %s  돌아가기" % InputSettings.gamepad_label(settings, "pause"), 322, 9, MUTED, true)
	_centered("해금은 능력치를 올리지 않습니다 / 연습은 새로운 기록을 남기지 않습니다", 344, 8, MUTED, true)


func _codex_pattern_hint(id: String) -> String:
	if not profile.seen_patterns.has(id): return ""
	if int(profile.pattern_hit_counts.get(id, 0)) < 2:
		return "같은 패턴을 두 번 이상 맞은 뒤 대응 원리가 떠오릅니다."
	return str(codex.patterns[id].hint)


func _draw_wrapped(value: String, point: Vector2, width: float, color: Color) -> void:
	var line := ""
	var y := point.y
	for character in value:
		if korean_font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > width:
			_text(line, Vector2(point.x, y), 11, color, true)
			line = character
			y += 18
		else:
			line += character
	if not line.is_empty(): _text(line, Vector2(point.x, y), 11, color, true)


func _draw_oaths() -> void:
	_overlay()
	_centered("불씨에 새길 맹세", 78, 23, ASH, true)
	_centered("전투와 기록 시간 정지 / 이동으로 선택 · 공격으로 확정", 96, 10, MUTED, true)
	for i in range(model.oath_candidates.size()):
		var id: String = str(model.oath_candidates[i])
		var oath: Dictionary = model.data.oaths[id]
		var rect := _menu_rect(i)
		draw_rect(rect, Color("2d4141") if menu_index == i else Color("101e23"))
		draw_rect(rect, EMBER if menu_index == i else Color("324b4c"), false, 1)
		_text("%s  %s" % [id, oath.name], rect.position + Vector2(12, 15), 11, EMBER if menu_index == i else ASH, true)
		_text(str(oath.benefit), rect.position + Vector2(14, 31), 10, ASH, true)
		_text(str(oath.burden), rect.position + Vector2(280, 31), 10, MUTED, true)
	_button("건너뛰기 / 지금 상태 유지", model.oath_candidates.size(), true, true)
	_centered("확정 후 1초 예고 / 공격키를 놓고 다시 누르세요", 322, 10, MUTED, true)
	if developer_practice:
		_centered("DEV PREVIEW / NO PROFILE UNLOCKS", 345, 8, VOID)


func _draw_practice() -> void:
	_overlay()
	_centered("잔향 연습", 92, 20, ASH, true)
	_centered("도달한 페이즈만 연습할 수 있습니다", 106, 10, MUTED, true)
	for i in range(5):
		var unlocked := i < unlocked_practice
		_button("P%d  %s%s" % [i + 1, PHASE_NAMES[i], "" if unlocked else "  [잠김]"], i, unlocked, true)
	_button("돌아가기 / ESC", 5, true, true)
	_centered("체력 100 / 스택 0 / 기운·각인 없음 / 선택한 페이즈에서 종료", 289, 10, ASH, true)
	_centered("시작 무기: " + _weapon_name(starting_weapon) + " / 정식 도달 페이즈만 해금", 321, 10, MUTED, true)
	_centered("해금은 로컬 저장 / 연습 결과는 정식 기록에 포함되지 않음", 337, 9, MUTED, true)


func _draw_pause() -> void:
	_overlay()
	_centered("PAUSED", 110, 27, ASH)
	_centered("%s / P%d / SEED %d" % [model.mode.to_upper(), model.phase_id, seed_value], 135, 10, MUTED)
	_button("RESUME  /  ESC", 0)
	_button("RETRY / SAME SEED", 1)
	_button("중단하고 타이틀로 / 전투는 저장하지 않음", 2, true, true)
	_button("RETRY / NEW SEED", 3)
	_button("설정", 4, true, true)
	_button("불씨의 기록 / 도감", 5, true, true)
	_centered("도달 · 발견 · 기록 · 설정은 로컬 프로필에 남습니다", 325, 10, MUTED, true)


func _draw_result() -> void:
	_overlay()
	if model.result == "safety_error":
		_centered("전투 배치를 다시 준비해 주세요", 130, 20, ASH, true)
		_centered("안전한 공격 경로를 만들지 못했습니다.", 158, 11, MUTED, true)
		_centered("INVALID RUN / NO OFFICIAL RECORD / RETRY AVAILABLE", 181, 8, MUTED)
	elif model.result == "victory":
		for i in range(6):
			draw_colored_polygon(PackedVector2Array([Vector2(300 - i * 3, 83), Vector2(340 + i * 3, 83), Vector2(475 + i * 16, 218), Vector2(165 - i * 16, 218)]), Color(0.80, 0.62, 0.31, 0.018))
		_draw_ending_emblem()
		_centered("첫 새벽", 128, 30, Color("f0dbad"), true)
		_centered("그들은 나중에, 그를 신이라 불렀다.", 158, 12, ASH, true)
		_centered(_ending_title(model.weapon_id, run_element_uses), 181, 11, EMBER, true)
	elif model.result == "practice_complete":
		_centered("연습 P%d 완료" % run_start_phase, 130, 24, Color("d7dbce"), true)
		_centered(PHASE_NAMES[run_start_phase - 1], 158, 12, ASH, true)
		_centered("PRACTICE ONLY / NO OFFICIAL RECORD OR UNLOCK", 181, 9, MUTED)
	elif model.result == "prototype_complete":
		_centered("시제품 1페이즈 완료", 130, 22, Color("e0d7b6"), true)
		_centered("The first shape has fallen.", 158, 11, ASH)
		_centered("P1 COMPLETE  /  PROTOTYPE ENDS HERE", 179, 9, MUTED)
	else:
		_centered("연습 실패" if model.mode == "practice" else "THE EMBER FADES", 130, 26, Color("c2b09b"), model.mode == "practice")
		_centered("아직, 첫날은 오지 않았다.", 157, 12, ASH, true)
		var cause_name: String = PATTERN_NAMES.get(model.cause, model.cause)
		_centered("P%d / 피해 원인: %s" % [model.phase_id, cause_name], 181, 10, EMBER, true)
	_centered("TIME %02d:%02d / P%d BOSS %d HP / SEED %d / %s" % [int(wall_seconds) / 60, int(wall_seconds) % 60, model.phase_id, ceili(maxf(0, model.boss_hp)), seed_value, model.weapon_id], 205, 9, MUTED)
	_button("RETRY  /  SAME SEED", 0)
	_button("RETURN TO PRACTICE" if model.mode == "practice" else "RETURN TO TITLE", 1)
	_button("RETRY / NEW SEED", 2)
	_centered("UP / DOWN  SELECT    J / ENTER  CONFIRM    R  RETRY", 321, 8, MUTED)
	_centered("SAVED OFFICIAL RECORDS: %d / PRACTICE UNLOCKED: P%d" % [official_records.size(), unlocked_practice], 337, 8, MUTED)


func _dominant_element(uses: Dictionary) -> String:
	var chosen := ""
	var largest := 0
	# Stable ties follow the order of first world-properties: flame, frost, lightning, void.
	for id in ProfileStore.ELEMENT_IDS:
		if int(uses.get(id, 0)) > largest:
			chosen = id
			largest = int(uses[id])
	return chosen


func _ending_title(weapon: String, uses: Dictionary) -> String:
	var element := _dominant_element(uses)
	var prefix: String = {"fire":"불을 빼앗은", "frost":"겨울을 건넌", "lightning":"박동을 움켜쥔", "void":"무저를 품은"}.get(element, "스스로 빛난")
	var title: String = {"W01":"개벽의 칼날", "W02":"새벽의 가시", "W03":"쌍생의 박동", "W04":"세계의 초석", "W05":"윤회의 사슬"}.get(weapon, "최초의 불씨")
	return prefix + " · " + title


func _draw_ending_emblem() -> void:
	var element := _dominant_element(run_element_uses)
	var color := _element_color(element) if not element.is_empty() else ASH
	if pixel_art.human_frames.size() == 40:
		draw_texture_rect(pixel_art.human_frames[0], Rect2(300, 47, 40, 40), false, Color(color, 0.9))
	pixel_art.draw_weapon(self, Vector2(332, 78), Vector2.UP, model.weapon_id, 0.6)
	if not element.is_empty():
		_draw_element(Vector2(304, 60), 6, element)


func _draw_transition() -> void:
	draw_rect(Rect2(0, 83, 640, 214), Color(0.015, 0.035, 0.045, 0.88))
	var remaining: int = model.transition_ticks_remaining
	var next_phase: int = mini(5, model.phase_id + 1) if remaining > 60 else model.phase_id
	_centered("P%d / %s" % [next_phase, PHASE_NAMES[next_phase - 1]], 157, 22, ASH, true)
	_centered("인간의 불씨는 꺼지지 않았다.", 185, 12, MUTED, true)
	_centered("+%d LIFE / STACK AND HELD ELEMENT RETAINED" % int(model.phase_heal()), 207, 8, EMBER)
	_centered("REPOSITIONING" if remaining > 60 else "RESUME IN %.1f" % (float(remaining) / 60.0), 232, 12, ASH)
	_centered("공격과 회피는 버튼을 놓고 다시 누르세요", 254, 10, MUTED, true)
