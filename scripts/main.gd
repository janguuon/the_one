extends Node2D
## Presentation owns real time and fresh button edges. CombatModel owns every rule.

const Combat = preload("res://scripts/combat_model.gd")
const Geometry = preload("res://scripts/combat_geometry.gd")
const CENTER = Vector2(320, 184)
const RADII = Vector2(260, 126)
const ASH = Color("b8c5bc")
const MUTED = Color("78928d")
const EMBER = Color("f3b16c")
const DANGER = Color("d8d4bd")
const FIRE = Color("e58b50")
const BG = Color("050c10")

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


func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Noto Sans", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	korean_font = SystemFont.new()
	korean_font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	korean_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_install_inputs()
	for i in range(92):
		var theta := float(i) * 2.3999632
		var radius := sqrt(float(i + 1) / 94.0)
		floor_marks.append(CENTER + Vector2(cos(theta) * 249.0, sin(theta) * 116.0) * radius)
	model.reset(seed_value)
	for arg in OS.get_cmdline_user_args():
		if arg == "--autostart" or arg == "--smoke":
			smoke = arg == "--smoke"
			_start_run()
		elif arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--capture-tick="):
			capture_tick = int(arg.trim_prefix("--capture-tick="))
	if screen == "playing":
		model.reset(seed_value)
	queue_redraw()


func _install_inputs() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	_bind("attack", [KEY_J], JOY_BUTTON_X)
	_bind("dodge", [KEY_SPACE, KEY_K], JOY_BUTTON_A)
	_bind("pause", [KEY_ESCAPE], JOY_BUTTON_START)
	var motion_data := [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0], ["move_up", JOY_AXIS_LEFT_Y, -1.0], ["move_down", JOY_AXIS_LEFT_Y, 1.0]]
	for entry in motion_data:
		var motion := InputEventJoypadMotion.new()
		motion.axis = int(entry[1])
		motion.axis_value = float(entry[2])
		InputMap.action_add_event(entry[0], motion)


func _bind(action: String, keys: Array, joy_button: int = -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.24)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = int(key)
		InputMap.action_add_event(action, event)
	if joy_button >= 0:
		var event := InputEventJoypadButton.new()
		event.button_index = joy_button
		InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			debug_visible = not debug_visible
			return
		if event.keycode == KEY_R and screen != "title":
			_start_run()
			return
	if event.is_action_pressed("pause"):
		if screen == "playing":
			screen = "paused"
			menu_index = 0
			model.clear_input()
		elif screen == "paused":
			screen = "playing"
		attack_pressed = false
		dodge_pressed = false
		return
	if screen != "playing":
		var menu_move := false
		if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
			var direction := 1 if event.axis_value > 0.55 else -1 if event.axis_value < -0.55 else 0
			menu_move = direction != 0 and direction != menu_axis_direction
			menu_axis_direction = direction
		elif event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
			menu_move = true
		if menu_move:
			menu_index = 1 - menu_index if screen != "title" else 0
		if event.is_action_pressed("attack") or (event is InputEventKey and event.pressed and event.keycode == KEY_ENTER):
			_activate_menu()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var point := get_global_mouse_position()
			for i in range(_menu_count()):
				if _menu_rect(i).has_point(point):
					menu_index = i
					_activate_menu()
		return
	if event.is_action_pressed("attack"):
		attack_pressed = true
	if event.is_action_pressed("dodge"):
		dodge_pressed = true


func _menu_count() -> int:
	return 1 if screen == "title" else 2


func _menu_rect(index: int) -> Rect2:
	return Rect2(230, 235 + index * 29, 180, 24)


func _activate_menu() -> void:
	if screen == "title":
		_start_run()
	elif screen == "paused":
		if menu_index == 0:
			screen = "playing"
		else:
			_start_run()
	elif screen == "result":
		if menu_index == 0:
			_start_run()
		else:
			screen = "title"
			menu_index = 0
	attack_pressed = false
	dodge_pressed = false


func _start_run() -> void:
	model.reset(seed_value)
	screen = "playing"
	menu_index = 0
	hitstop_remaining = 0.0
	hitstop_guard = 0.0
	wall_seconds = 0.0
	attack_pressed = false
	dodge_pressed = false
	particles.clear()
	notices.clear()


func _physics_process(delta: float) -> void:
	if screen != "playing":
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
		model.queue_frozen_input(command)
		hitstop_remaining = maxf(0.0, hitstop_remaining - delta)
		return
	model.step(command)
	_read_events()
	if model.hitstop_ms > 0.0:
		if hitstop_guard <= 0.0:
			hitstop_remaining = model.hitstop_ms / 1000.0
			hitstop_guard = 0.1
		model.hitstop_ms = 0.0
	if not model.result.is_empty():
		screen = "result"
		menu_index = 0


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
		get_tree().quit()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(capture_path)
	print("CAPTURE ", capture_path, " error=", error)
	get_tree().quit(int(error))


func _read_events() -> void:
	for event in model.events:
		var type: String = str(event.get("type", ""))
		if type in ["boss_hit", "damage_boss", "hit_boss"]:
			var position: Vector2 = event.get("pos", model.boss_pos - Vector2(0, 20))
			_emit_sparks(position, EMBER)
		elif type in ["player_hit", "damage_player", "hit_player"]:
			_emit_sparks(model.player_pos - Vector2(0, 8), Color("e27265"))
		elif type in ["pickup", "pickup_collected", "fire_collected"]:
			_emit_sparks(model.player_pos - Vector2(0, 8), FIRE)
			notices.append({"text": "FLAME ACQUIRED  /  2 USES", "life": 1.8})


func _emit_sparks(position: Vector2, color: Color) -> void:
	for i in range(7):
		var angle := cosmetic_time * 3.7 + float(i) * TAU / 7.0
		particles.append({"pos": position, "vel": Vector2.from_angle(angle) * (12.0 + i * 4.0), "life": 0.35 + i * 0.025, "color": color})


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), BG)
	_draw_arena()
	for pickup in model.pickups:
		_draw_pickup(pickup)
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
	for particle in particles:
		var color: Color = particle["color"]
		color.a = clampf(particle["life"] * 2.5, 0.0, 1.0)
		draw_rect(Rect2((particle["pos"] as Vector2).round(), Vector2(2, 2)), color)
	_draw_hud()
	if debug_visible:
		_draw_debug()
	if screen == "title":
		_draw_title()
	elif screen == "paused":
		_draw_pause()
	elif screen == "result":
		_draw_result()


func _ellipse(center: Vector2, radii: Vector2, count: int = 96) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(count):
		var angle := float(i) * TAU / float(count)
		points.append((center + Vector2(cos(angle), sin(angle)) * radii).round())
	return points


func _draw_arena() -> void:
	draw_colored_polygon(_ellipse(CENTER + Vector2(0, 8), RADII + Vector2(10, 4)), Color("080f12"))
	draw_colored_polygon(_ellipse(CENTER + Vector2(0, 4), RADII + Vector2(3, 2)), Color("1a2c2e"))
	draw_colored_polygon(_ellipse(CENTER, RADII), Color("122126"))
	draw_polyline(_closed(_ellipse(CENTER, RADII)), Color("3c5352"), 1.0)
	draw_polyline(_closed(_ellipse(CENTER, RADII - Vector2(4, 3))), Color("243b3e"), 1.0)
	for i in range(floor_marks.size()):
		var p := floor_marks[i].round()
		var shade := Color("1d3134") if i % 3 != 0 else Color("253a3c")
		draw_line(p, p + Vector2(3 + i % 8, 0), shade, 1)
		if i % 7 == 0:
			draw_line(p, p + Vector2(3, 3), shade, 1)
	for i in range(11):
		var angle := float(i) * TAU / 11.0 + 0.24
		var edge := CENTER + Vector2(cos(angle), sin(angle)) * (RADII - Vector2(8, 6))
		var inner := CENTER + Vector2(cos(angle + 0.08), sin(angle + 0.08)) * Vector2(177, 87)
		var mid := edge.lerp(inner, 0.6) + Vector2(3, -2)
		draw_polyline(PackedVector2Array([edge.round(), mid.round(), inner.round()]), Color("0b191e"), 2)
		draw_line(mid.round() + Vector2(1, 0), inner.round(), Color("2a3c3d"), 1)
	draw_arc(CENTER, 15.0, 0, TAU, 32, Color("304244"), 1)
	draw_line(CENTER + Vector2(-7, 0), CENTER + Vector2(7, 0), Color("304244"), 1)
	draw_line(CENTER + Vector2(0, -7), CENTER + Vector2(0, 7), Color("304244"), 1)
	# Edge stones are scenery; they never block movement.
	for i in range(30):
		var angle := float(i) * TAU / 30.0
		var p := CENTER + Vector2(cos(angle), sin(angle)) * (RADII + Vector2(5, 5))
		draw_rect(Rect2(p.round(), Vector2(4 + i % 4, 2 + i % 3)), Color("304345"))


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
	var progress: float = clampf(float(hazard.get("progress", 0)), 0.0, 1.0)
	var outline := Color("f1d7b2") if active else Color("9eb6aa")
	var fill := Color(0.93, 0.61, 0.36, 0.30) if active else Color(0.72, 0.79, 0.67, 0.055 + progress * 0.12)
	var shape: String = hazard.get("shape", "sector")
	if shape == "sector":
		var radius: float = float(hazard.get("radius", 56))
		var arc: float = float(hazard.get("arc_radians", deg_to_rad(140)))
		var points := Geometry.polygon(hazard)
		draw_colored_polygon(points, fill)
		draw_polyline(_closed(points), outline, 2.0 if active else 1.0)
		draw_arc(origin, radius - 3, facing.angle() - arc / 2, facing.angle() - arc / 2 + arc * maxf(progress, 0.001), 40, EMBER, 1.0)
	elif shape == "line":
		var length: float = float(hazard.get("length", 196))
		var width: float = float(hazard.get("width", 24))
		var side := facing.orthogonal() * width / 2.0
		var end := origin + facing * length
		var points := Geometry.polygon(hazard)
		draw_colored_polygon(points, fill)
		draw_polyline(_closed(points), outline, 2.0 if active else 1.0)
		draw_line(origin, origin.lerp(end, progress), EMBER, 2)
		for i in range(1, 6):
			var point := origin + facing * (length * i / 6.0)
			draw_line(point - side * 0.28, point + side * 0.28, outline, 1)
	elif shape == "ring":
		var radius: float = float(hazard.get("radius", 28))
		var width: float = float(hazard.get("width", 8))
		draw_arc(origin, radius, 0, TAU, 128, fill, width)
		draw_arc(origin, radius - width / 2.0, 0, TAU, 128, outline, 1)
		draw_arc(origin, radius + width / 2.0, 0, TAU, 128, outline, 1)
		if not active:
			draw_arc(origin, radius, -PI / 2, -PI / 2 + TAU * maxf(progress, 0.001), 96, EMBER, 2)


func _draw_player() -> void:
	var p: Vector2 = model.player_pos.round()
	var state: String = model.player_state
	var facing: Vector2 = model.player_facing
	var invulnerable: bool = model.is_player_invulnerable()
	var hurt_blink: bool = invulnerable and state != "dodge" and model.tick % 6 < 3
	var cloth := Color("c8c5ae") if not hurt_blink else Color("f7e4ca")
	var dark_cloth := Color("727c72")
	if model.player_hp <= 0:
		draw_colored_polygon(PackedVector2Array([p + Vector2(-8, -2), p + Vector2(6, -5), p + Vector2(11, 0), p + Vector2(-5, 2)]), dark_cloth)
		return
	draw_colored_polygon(_ellipse(p + Vector2(0, 1), Vector2(9, 3), 16), Color(0, 0, 0, 0.40))
	var roll_ready := clampf(1.0 - float(model.next_dodge_tick - model.tick) / float(model.data.player.dodge_cooldown), 0.0, 1.0)
	draw_arc(p, 9.0, -PI / 2, -PI / 2 + TAU * maxf(0.001, roll_ready), 24, Color("8ea696") if roll_ready >= 1.0 else Color("3b605e"), 1)
	if state == "dodge":
		var back := p - facing * 10.0
		draw_line(back, p, Color("4d6a66"), 6)
		draw_line(back - facing * 5.0, back, Color("2d4748"), 4)
		draw_circle(p + Vector2(0, -5), 5.0, cloth)
		draw_line(p + Vector2(-3, -7), p + Vector2(4, -3), dark_cloth, 2)
	else:
		var step_offset := 0.0
		if state == "move":
			step_offset = sin(model.tick * 0.5) * 2.0
		draw_line(p + Vector2(-2, -5), p + Vector2(-3, step_offset), dark_cloth, 2)
		draw_line(p + Vector2(2, -5), p + Vector2(3, -step_offset), cloth, 2)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -14), p + Vector2(3, -14), p + Vector2(6, -3), p + Vector2(-6, -3)]), dark_cloth)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-3, -14), p + Vector2(2, -14), p + Vector2(4, -5), p + Vector2(-1, -7)]), cloth)
		draw_rect(Rect2(p + Vector2(-3, -20), Vector2(6, 6)), cloth)
		draw_rect(Rect2(p + Vector2(-2, -15), Vector2(4, 2)), Color("333e3b"))
		var sword_origin := p + Vector2(3, -9)
		var sword_direction := facing
		if state == "attack" and not model.attack.is_empty():
			var age: int = int(model.attack.get("age", model.state_age))
			var active_end := float(model.data.sword.startup_ticks) + float(model.data.sword.active_ticks)
			var angle_offset := lerpf(-1.5, 1.0, clampf(float(age) / active_end, 0, 1))
			sword_direction = facing.rotated(angle_offset)
		var sword_tip := sword_origin + sword_direction * 15.0
		draw_line(sword_origin, sword_tip, ASH, 2)
		draw_line(sword_origin - sword_direction.orthogonal() * 3, sword_origin + sword_direction.orthogonal() * 3, dark_cloth, 2)
	# The foot chevron is aim direction, independent of the sprite's height.
	var tip := p + facing * 11.0
	var side := facing.orthogonal() * 2.0
	draw_polyline(PackedVector2Array([tip - facing * 3 + side, tip, tip - facing * 3 - side]), Color("b8c5a0"), 1)
	if model.fire_charges > 0:
		_draw_flame(p + Vector2(-8, -14), 2.5, FIRE)


func _draw_boss() -> void:
	var p: Vector2 = model.boss_pos.round()
	var facing: Vector2 = model.boss_facing
	var telegraph: bool = model.boss_state == "telegraph"
	var active: bool = model.boss_state == "execute"
	var bone := Color("718781")
	var edge := Color("334d4d")
	if model.boss_hp <= 0:
		draw_colored_polygon(_ellipse(p, Vector2(35, 9), 16), Color("091418"))
		draw_line(p + Vector2(-20, -5), p + Vector2(18, -8), bone, 3)
		draw_line(p + Vector2(-7, -3), p + Vector2(8, -16), edge, 4)
		return
	draw_colored_polygon(_ellipse(p + Vector2(0, 2), Vector2(33, 10), 24), Color(0, 0, 0, 0.40))
	var sway := sin(model.tick * 0.035) * 1.2
	var chest := p + Vector2(sway, -30)
	var left_shoulder := chest + Vector2(-13, -8)
	var right_shoulder := chest + Vector2(13, -8)
	var raise := 0.0
	if telegraph:
		raise = -18.0 if model.boss_pattern == "claw" else -10.0
	elif active:
		raise = 15.0
	var left_elbow := p + Vector2(-26, -22)
	var right_elbow := p + Vector2(25, -25 + raise)
	var left_hand := p + Vector2(-21, -5)
	var right_hand := p + Vector2(36, -13 + raise)
	if active and model.boss_pattern == "rupture":
		right_hand = p + facing * 37.0
	for limb in [[left_shoulder, left_elbow, left_hand], [right_shoulder, right_elbow, right_hand]]:
		draw_polyline(PackedVector2Array(limb), Color("0a171b"), 7)
		draw_polyline(PackedVector2Array(limb), edge, 4)
		draw_line(limb[0], limb[1], bone, 1)
		draw_line(limb[1], limb[2], bone, 1)
		for i in range(3):
			var hand: Vector2 = limb[2]
			draw_line(hand + Vector2(i * 2 - 2, 0), hand + Vector2(i * 3 - 3, 8 + i % 2 * 2), bone, 1)
	var body := PackedVector2Array([p + Vector2(-8, -3), chest + Vector2(-13, -11), chest + Vector2(0, -15), chest + Vector2(13, -11), p + Vector2(9, -3), p + Vector2(0, -9)])
	draw_colored_polygon(body, Color("08161a"))
	draw_polyline(_closed(body), edge, 2)
	draw_line(p + Vector2(-5, -13), p + Vector2(-9, 0), bone, 3)
	draw_line(p + Vector2(5, -13), p + Vector2(11, 1), edge, 4)
	for i in range(4):
		var y := -39.0 + i * 5.0
		draw_polyline(PackedVector2Array([p + Vector2(-11 + i, y - 2), p + Vector2(-4, y + 1), p + Vector2(-3, y + 5)]), bone, 1)
		draw_polyline(PackedVector2Array([p + Vector2(11 - i, y - 2), p + Vector2(4, y + 1), p + Vector2(3, y + 5)]), edge.lightened(0.2), 1)
	draw_colored_polygon(_ellipse(chest + Vector2(0, 1), Vector2(4, 7), 12), BG)
	var head := p + Vector2(sway, -52)
	draw_colored_polygon(PackedVector2Array([head + Vector2(-6, -6), head + Vector2(5, -6), head + Vector2(4, 4), head + Vector2(0, 8), head + Vector2(-4, 4)]), bone)
	draw_rect(Rect2(head + Vector2(-4, -2), Vector2(8, 3)), Color("0b1c20"))
	draw_line(head + Vector2(-5, -5), head + Vector2(-12, -15), edge, 3)
	draw_line(head + Vector2(4, -5), head + Vector2(10, -18), bone, 2)
	if telegraph or active:
		var glow := EMBER if active else Color("bfbc9c")
		draw_circle(chest + Vector2(0, 1), 2.0 + sin(model.boss_age * 0.12), glow)
		draw_line(head + Vector2(-3, -1), head + Vector2(-1, -1), glow, 1)


func _draw_attack() -> void:
	if model.attack.is_empty() or model.player_state != "attack":
		return
	var age: int = int(model.attack.get("age", model.state_age))
	var startup := int(model.data.sword.startup_ticks)
	if age < startup or age >= startup + int(model.data.sword.active_ticks):
		return
	var kind: String = model.attack.get("kind", "basic")
	var shape: Dictionary = model.player_attack_shape()
	var facing: Vector2 = shape.facing
	var arc: float = shape.arc_radians
	var reach: float = shape.radius
	var color := EMBER if kind in ["fire", "resonance"] else ASH
	var origin: Vector2 = shape.origin
	var start_angle := facing.angle() - arc / 2.0
	draw_colored_polygon(Geometry.polygon(shape), Color(color, 0.13))
	draw_arc(origin, reach, start_angle, start_angle + arc, 32, color, 2)
	draw_arc(origin, reach - 3, start_angle + 0.1, start_angle + arc - 0.1, 32, Color(color, 0.45), 1)
	if kind == "resonance":
		draw_arc(origin, reach + 3, start_angle, start_angle + arc, 32, Color(FIRE, 0.5), 1)


func _draw_pickup(pickup: Dictionary) -> void:
	var position: Vector2 = pickup.get("pos", Vector2.ZERO)
	var state: String = pickup.get("state", "ground")
	if state not in ["flying", "ground", "grounded"]:
		return
	var p := position.round()
	draw_colored_polygon(_ellipse(p, Vector2(7, 3), 16), Color("4e3826"))
	if state == "flying":
		var progress := clampf(float(pickup.get("age", 0)) / float(model.data.fire.flight_ticks), 0, 1)
		p.y -= sin(progress * PI) * 22.0
	else:
		p.y -= 4.0 + sin(model.tick * 0.08 + float(pickup.get("id", 0))) * 1.5
	var ttl: int = int(pickup.get("ttl", 600))
	_draw_flame(p, 5.0, FIRE)
	if ttl >= 120 or model.tick % 12 >= 5:
		draw_arc(position, 9.0, 0, TAU, 24, Color("976c43"), 1)


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
	_text("P1 / PROTOTYPE", Vector2(512, 21), 9, MUTED)
	_text("F1  DEBUG", Vector2(541, 33), 8, MUTED)
	_centered("MUJEO  /  THE FIRST SHAPE", 20, 10, ASH)
	draw_rect(Rect2(184, 27, 272, 6), Color("0a1418"))
	draw_rect(Rect2(185, 28, 270 * clampf(model.boss_hp / float(model.data.boss.hp), 0, 1), 4), Color("b5b09a"))
	draw_rect(Rect2(184, 27, 272, 6), Color("405453"), false, 1)
	if screen == "playing" or screen == "paused":
		var hint := "CLOSE THE DISTANCE"
		if model.boss_state == "telegraph":
			hint = {"claw": "ASH CLAW  /  LEAVE THE ARC", "rupture": "FIRST RIFT  /  STEP TO THE SIDE", "pulse": "FIRST PULSE  /  ROLL INTO THE WAVE"}.get(model.boss_pattern, "")
		elif model.boss_state == "recover":
			hint = "OPENING  /  STRIKE, THEN WITHDRAW"
		elif model.boss_state == "execute":
			hint = "ASH CLAW" if model.boss_pattern == "claw" else "FIRST RIFT" if model.boss_pattern == "rupture" else "FIRST PULSE"
		_centered(hint, 47, 8, EMBER if model.boss_state == "recover" else MUTED)
	# The lower margin lies entirely outside the playable ellipse.
	draw_rect(Rect2(0, 315, 640, 45), Color("081216"))
	draw_line(Vector2(20, 315), Vector2(620, 315), Color("293d3f"), 1)
	_text("LIFE", Vector2(23, 328), 9, MUTED)
	_text("%03d / %d" % [ceili(maxf(0.0, model.player_hp)), int(model.data.player.hp)], Vector2(23, 341), 9, ASH)
	draw_rect(Rect2(90, 322, 101, 6), Color("233336"))
	draw_rect(Rect2(90, 322, 100.0 * maxf(0, model.player_hp) / float(model.data.player.hp), 6), Color("adbaa2"))
	_text("ASHEN SWORD", Vector2(90, 341), 8, MUTED)
	_text("STACK", Vector2(219, 328), 8, MUTED)
	for i in range(int(model.data.sword.stack_threshold)):
		var color := EMBER if i < model.stacks else Color("263c3f")
		draw_rect(Rect2(253 + i * 8, 322, 5, 6), color)
	_text("FLAME", Vector2(219, 341), 8, MUTED)
	for i in range(int(model.data.fire.charges)):
		_draw_flame(Vector2(257 + i * 13, 338), 3, FIRE if i < model.fire_charges else Color("304346"))
	var kind: String = model.next_attack_kind()
	var name_text: String = {"basic": "ASH CUT", "signature": "GENESIS", "fire": "FLAME CUT", "resonance": "RESONANCE"}.get(kind, kind)
	_text("NEXT", Vector2(326, 328), 8, MUTED)
	_text(name_text, Vector2(359, 329), 12, EMBER if kind != "basic" else ASH)
	_text("PRESS J / X", Vector2(359, 342), 8, MUTED)
	_text("%02d:%02d" % [int(wall_seconds) / 60, int(wall_seconds) % 60], Vector2(551, 329), 12, ASH)
	_text("P1  %04d" % ceili(maxf(0, model.boss_hp)), Vector2(551, 342), 8, MUTED)
	_centered("WASD / ARROWS  MOVE    J / X  ATTACK    SPACE / A  ROLL    ESC  PAUSE", 355, 8, MUTED)
	if not notices.is_empty():
		_centered(notices[-1]["text"], 299, 10, EMBER)


func _draw_debug() -> void:
	draw_arc(model.player_pos, float(model.data.player.radius), 0, TAU, 24, Color("a8edbb"), 1)
	draw_arc(model.boss_pos, float(model.data.boss.body_radius), 0, TAU, 32, Color("65a1bc"), 1)
	draw_arc(model.boss_pos, float(model.data.boss.hurt_radius), 0, TAU, 32, Color("ba86c9"), 1)
	draw_line(model.player_pos, model.player_pos + model.player_facing * 24, Color("a8edbb"), 1)
	draw_rect(Rect2(12, 56, 220, 66), Color(0.01, 0.03, 0.04, 0.90))
	_text("MODE prototype | SEED %d" % seed_value, Vector2(18, 68), 9, EMBER)
	_text("TICK %d  WALL %.2fs" % [model.tick, wall_seconds], Vector2(18, 79), 9)
	_text("PLAYER %s age=%d inv=%s" % [model.player_state, model.state_age, str(model.is_player_invulnerable())], Vector2(18, 90), 9)
	_text("BOSS %s %s %d" % [model.boss_pattern, model.boss_state, model.boss_age], Vector2(18, 101), 9)
	_text("HITSTOP %.0fms | R restart" % (hitstop_remaining * 1000), Vector2(18, 112), 9)
	if not model.attack.is_empty():
		draw_polyline(_closed(Geometry.polygon(model.player_attack_shape())), Color("7fbe91"), 1)


func _overlay() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color(0.015, 0.035, 0.045, 0.91))
	draw_line(Vector2(215, 82), Vector2(425, 82), Color("3a5150"), 1)
	draw_line(Vector2(215, 304), Vector2(425, 304), Color("3a5150"), 1)


func _button(label: String, index: int) -> void:
	var rect := _menu_rect(index)
	var selected := menu_index == index
	draw_rect(rect, Color("2d4141") if selected else Color("101e23"))
	draw_rect(rect, Color("a0aa96") if selected else Color("324b4c"), false, 1)
	_centered(label, rect.position.y + 16, 10, Color("eee2bf") if selected else MUTED)
	if selected:
		draw_colored_polygon(PackedVector2Array([Vector2(220, rect.position.y + 8), Vector2(224, rect.position.y + 12), Vector2(220, rect.position.y + 16)]), EMBER)


func _draw_title() -> void:
	_overlay()
	_centered("THE ONE", 128, 44, Color("d1d0b7"))
	_centered("최초의 불씨", 153, 17, ASH, true)
	_centered("아직, 첫날은 오지 않았다.", 183, 11, MUTED, true)
	_centered("ONE ARENA  /  ONE ADVERSARY  /  YOUR FIRST WAR", 207, 8, MUTED)
	_button("BEGIN  /  J OR ENTER", 0)
	_centered("WASD / LEFT STICK  MOVE     J / X  ATTACK", 279, 8, ASH)
	_centered("SPACE / A  ROLL     ESC / START  PAUSE", 292, 8, ASH)
	_centered("FIRST PLAYABLE  /  ASHEN SWORD + FLAME + PHASE 1", 323, 8, MUTED)
	_centered("PROTOTYPE SHAPES  /  60 HZ COMBAT", 337, 8, MUTED)


func _draw_pause() -> void:
	_overlay()
	_centered("PAUSED", 135, 28, ASH)
	_centered("The first dawn can wait.", 166, 10, MUTED)
	_centered("Combat, pickups and timers are frozen.", 186, 9, MUTED)
	_button("RESUME  /  ESC", 0)
	_button("RETRY PHASE 1", 1)
	_centered("UP / DOWN  SELECT    J / ENTER  CONFIRM", 321, 8, MUTED)


func _draw_result() -> void:
	_overlay()
	var complete: bool = model.result == "prototype_complete"
	if complete:
		_centered("시제품 1페이즈 완료", 130, 22, Color("e0d7b6"), true)
		_centered("The first shape has fallen.", 158, 11, ASH)
		_centered("P1 COMPLETE  /  PROTOTYPE ENDS HERE", 179, 9, MUTED)
	else:
		_centered("THE EMBER FADES", 130, 26, Color("c2b09b"))
		_centered("아직, 첫날은 오지 않았다.", 157, 12, ASH, true)
		var cause_name: String = {"claw": "ASH CLAW", "rupture": "FIRST RIFT", "pulse": "FIRST PULSE"}.get(model.cause, model.cause)
		_centered("CAUSE: " + cause_name, 180, 10, EMBER, true)
	_centered("TIME %02d:%02d  /  BOSS %d HP  /  SEED %d" % [int(wall_seconds) / 60, int(wall_seconds) % 60, ceili(maxf(0, model.boss_hp)), seed_value], 204, 9, MUTED)
	_button("RETRY  /  SAME SEED", 0)
	_button("RETURN TO TITLE", 1)
	_centered("UP / DOWN  SELECT    J / ENTER  CONFIRM    R  RETRY", 321, 8, MUTED)
