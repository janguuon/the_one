extends RefCounted
## Gameplay bindings are separate from the permanent menu recovery controls.
const ACTIONS = ["move_up", "move_down", "move_left", "move_right", "attack", "dodge", "pause"]
const NAMES = {"move_up":"위로 이동", "move_down":"아래로 이동", "move_left":"왼쪽 이동", "move_right":"오른쪽 이동", "attack":"공격", "dodge":"회피", "pause":"일시정지"}
const JOY_ACTIONS = ["attack", "dodge", "pause"]
const RESERVED_KEYS = [KEY_ENTER, KEY_KP_ENTER, KEY_F1, KEY_R, KEY_TAB]

static func defaults() -> Dictionary:
	return {"show_particles":true, "debug_visible":false, "fullscreen":false,
		"reduced_effects":false, "master_volume":0.8, "music_volume":0.65,
		"sfx_volume":0.8, "music_muted":false, "sfx_muted":false,
		"stick_deadzone":0.24, "keyboard":default_keyboard(), "gamepad":default_gamepad()}

static func default_keyboard() -> Dictionary:
	return {"move_up":[KEY_W, KEY_UP], "move_down":[KEY_S, KEY_DOWN], "move_left":[KEY_A, KEY_LEFT],
		"move_right":[KEY_D, KEY_RIGHT], "attack":[KEY_J], "dodge":[KEY_SPACE, KEY_K], "pause":[KEY_ESCAPE]}

static func default_gamepad() -> Dictionary:
	return {"attack":JOY_BUTTON_X, "dodge":JOY_BUTTON_A, "pause":JOY_BUTTON_START}

static func sanitize(raw: Variant) -> Dictionary:
	var result := defaults()
	var repaired := false
	if not raw is Dictionary:
		return {"settings":result, "repaired":true}
	for key in ["show_particles", "debug_visible", "fullscreen", "reduced_effects", "music_muted", "sfx_muted"]:
		if raw.has(key):
			if raw[key] is bool: result[key] = raw[key]
			else: repaired = true
	for key in ["master_volume", "music_volume", "sfx_volume", "stick_deadzone"]:
		if raw.has(key):
			if (raw[key] is float or raw[key] is int) and is_finite(float(raw[key])):
				var low := 0.1 if key == "stick_deadzone" else 0.0
				var high := 0.6 if key == "stick_deadzone" else 1.0
				result[key] = clampf(float(raw[key]), low, high)
				repaired = repaired or float(result[key]) != float(raw[key])
			else: repaired = true
	if raw.has("keyboard"):
		if valid_keyboard(raw.keyboard):
			for action in ACTIONS:
				result.keyboard[action] = []
				for code in raw.keyboard[action]: result.keyboard[action].append(int(code))
		else: repaired = true
	if raw.has("gamepad"):
		if valid_gamepad(raw.gamepad):
			for action in JOY_ACTIONS: result.gamepad[action] = int(raw.gamepad[action])
		else: repaired = true
	return {"settings":result, "repaired":repaired}

static func allowed_key(code: int, action: String) -> bool:
	if code in RESERVED_KEYS or (code == KEY_ESCAPE and action != "pause"):
		return false
	return (code >= KEY_SPACE and code <= KEY_ASCIITILDE) or code in [KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_INSERT, KEY_DELETE, KEY_CAPSLOCK, KEY_BACKSPACE]

static func valid_keyboard(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	var used: Array[int] = []
	for action in ACTIONS:
		var values: Variant = raw.get(action)
		if not values is Array or values.is_empty() or values.size() > 2: return false
		for key in values:
			if not (key is int or key is float) or not is_finite(float(key)) or float(key) != floor(float(key)): return false
			var code := int(key)
			if not allowed_key(code, action) or used.has(code): return false
			used.append(code)
	return true

static func valid_gamepad(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	var used: Array[int] = []
	for action in JOY_ACTIONS:
		var key: Variant = raw.get(action)
		if not (key is int or key is float) or not is_finite(float(key)) or float(key) != floor(float(key)): return false
		var code := int(key)
		if code not in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER] or used.has(code): return false
		used.append(code)
	return true

static func rebind(settings: Dictionary, action: String, code: int, joy: bool = false) -> String:
	var mapping: Dictionary = settings.gamepad.duplicate(true) if joy else settings.keyboard.duplicate(true)
	if action not in (JOY_ACTIONS if joy else ACTIONS): return "변경할 수 없는 행동입니다"
	if not joy and not allowed_key(code, action): return "Enter · Esc · Tab · R · F1은 메뉴와 복구용으로 남깁니다"
	if joy and code not in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]: return "얼굴 버튼 · 어깨 버튼 · Start를 사용하세요 / Back 취소"
	for other in mapping:
		if other != action and ((int(mapping[other]) == code) if joy else mapping[other].has(code)):
			return "%s에 이미 지정되어 있습니다" % NAMES[other]
	mapping[action] = code if joy else [code]
	settings["gamepad" if joy else "keyboard"] = mapping
	return ""

static func install(settings: Dictionary) -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, float(settings.stick_deadzone))
		for code in settings.keyboard[action]:
			var event := InputEventKey.new()
			event.physical_keycode = int(code)
			InputMap.action_add_event(action, event)
		if settings.gamepad.has(action):
			var event := InputEventJoypadButton.new()
			event.button_index = int(settings.gamepad[action])
			InputMap.action_add_event(action, event)
	for entry in [["move_left",JOY_AXIS_LEFT_X,-1.0],["move_right",JOY_AXIS_LEFT_X,1.0],["move_up",JOY_AXIS_LEFT_Y,-1.0],["move_down",JOY_AXIS_LEFT_Y,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = int(entry[1])
		event.axis_value = float(entry[2])
		InputMap.action_add_event(entry[0], event)

static func keyboard_label(settings: Dictionary, action: String) -> String:
	var labels: Array[String] = []
	for code in settings.keyboard[action]: labels.append(OS.get_keycode_string(int(code)))
	return " / ".join(labels)

static func gamepad_label(settings: Dictionary, action: String) -> String:
	return {JOY_BUTTON_A:"A / 남",JOY_BUTTON_B:"B / 동",JOY_BUTTON_X:"X / 서",JOY_BUTTON_Y:"Y / 북",JOY_BUTTON_START:"Start",JOY_BUTTON_BACK:"Back",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB"}.get(int(settings.gamepad[action]), "?")
