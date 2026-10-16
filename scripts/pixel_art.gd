extends RefCounted
## M5 original raster assets. Presentation only: never writes to CombatModel.
## The atlas uses five human source directions; west-facing views mirror east.
## All animation clocks derive from combat ticks, so pause/hitstop stop actors.

const HUMAN_PATH := "res://assets/art/first-human-atlas.png"
const BOSS_PATH := "res://assets/art/mujeo-atlas.png"
const RELICS_PATH := "res://assets/art/relics-atlas-v2.png"
const ARENA_PATH := "res://assets/art/arena-primordial.png"
const PHASE_TINTS := [Color("a8bcb9"), Color("b6dce4"), Color("e0d5aa"), Color("c8b2dc"), Color("d9ccb6")]
const ELEMENT_COLORS := {"fire": Color("f3b16c"), "frost": Color("b6deeb"), "lightning": Color("f4e8a4"), "void": Color("b597cf")}
const WEAPON_HEIGHTS := {"W01": 28.0, "W02": 39.0, "W03": 23.0, "W04": 32.0, "W05": 33.0}
const CENTER := Vector2(320, 184)
const RADII := Vector2(260, 126)

var arena: ImageTexture
var human_frames: Array[ImageTexture] = []
var boss_frames: Array[ImageTexture] = []
var relic_frames: Array[ImageTexture] = []
var source_sizes: Dictionary = {}
var reduced_effects := false
var _human_death_started := -1.0
var _boss_death_started := -1.0


func _init() -> void:
	# Keep source files untouched. Nearest sampling into small runtime frame
	# textures gives one stable logical pixel grid even for generated atlases.
	var floor_image := _source_image(ARENA_PATH)
	if floor_image != null:
		source_sizes.arena = floor_image.get_size()
		floor_image.resize(640, 360, Image.INTERPOLATE_NEAREST)
		arena = ImageTexture.create_from_image(floor_image)
	human_frames = _atlas(HUMAN_PATH, 8, 5, 48)
	boss_frames = _atlas(BOSS_PATH, 6, 3, 104)
	relic_frames = _atlas(RELICS_PATH, 5, 2, 40)


func _atlas(path: String, columns: int, rows: int, frame_size: int) -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	var sheet := _source_image(path)
	if sheet == null:
		return frames
	source_sizes[path] = sheet.get_size()
	for row in range(rows):
		for column in range(columns):
			var start := Vector2i(floori(float(column) * sheet.get_width() / columns), floori(float(row) * sheet.get_height() / rows))
			var end := Vector2i(floori(float(column + 1) * sheet.get_width() / columns), floori(float(row + 1) * sheet.get_height() / rows))
			var frame := sheet.get_region(Rect2i(start, end - start))
			frame.resize(frame_size, frame_size, Image.INTERPOLATE_NEAREST)
			frames.append(ImageTexture.create_from_image(frame))
	return frames


func _source_image(path: String) -> Image:
	# Imported textures keep working inside an exported PCK. Opening PNG bytes
	# directly through Image.load_from_file would only work in the source tree.
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null


## row = N, NE, E, SE, S. Eight directions share five original views.
func human_direction(direction: Vector2) -> Dictionary:
	var vector := direction.normalized() if direction.length_squared() > 0.001 else Vector2.DOWN
	var degrees := rad_to_deg(atan2(absf(vector.x), -vector.y))
	return {"row": clampi(roundi(degrees / 45.0), 0, 4), "flip": vector.x < -0.01}


func human_pose(model) -> Dictionary:
	var view := human_direction(model.player_facing)
	var column := 0
	var rotation := 0.0
	var offset := Vector2.ZERO
	if model.player_hp <= 0.0 or model.player_state == "dead":
		column = 7
		rotation = PI * 0.46
		offset = Vector2(0, 8)
	elif model.player_state == "move":
		column = 1 + posmod(int(model.tick / 7), 2)
	elif model.player_state == "attack" and not model.attack.is_empty():
		var definition: Dictionary = model.attack.get("definition", model.weapon_definition())
		var age := int(model.attack.get("age", model.state_age))
		column = 3 if age < int(definition.startup_ticks) else 4 if age < int(definition.startup_ticks) + int(definition.active_ticks) else 5
	elif model.player_state == "dodge":
		column = 6
		# A compact roll pose rotates through a full tumble over the real dodge.
		rotation = TAU * float(model.state_age) / maxf(1.0, float(model.data.player.dodge_ticks))
		offset = Vector2(0, 16)
	elif model.player_state == "hurt":
		column = 7
	else:
		offset.y = -float(posmod(int(model.tick / 36), 2))
	return {"frame": int(view.row) * 8 + column, "row": int(view.row), "column": column, "flip": bool(view.flip), "rotation": rotation, "offset": offset}


func boss_pose(model) -> Dictionary:
	var column := 0
	if model.boss_hp <= 0.0:
		column = 5
	elif model.boss_state == "telegraph":
		column = 2
	elif model.boss_state == "execute":
		column = 3
	elif model.boss_state == "recover":
		column = 4
	else:
		column = posmod(int(model.tick / 30), 2)
	var direction: Vector2 = model.boss_facing
	var row := 0 if direction.y > absf(direction.x) * 0.6 else 2 if direction.y < -absf(direction.x) * 0.6 else 1
	return {"frame": row * 6 + column, "column": column, "row": row, "flip": direction.x < -0.01}


## Animation follows the attack snapshot, including a spear's straight thrust.
func weapon_pose(model) -> Dictionary:
	var facing: Vector2 = model.player_facing
	var weapon := str(model.weapon_id)
	var hand := Vector2(-3 if bool(human_direction(facing).flip) else 3, -17)
	var direction := facing
	if model.player_state == "attack" and not model.attack.is_empty():
		facing = Vector2(model.attack.get("facing", facing))
		weapon = str(model.attack.get("weapon", weapon))
		hand.x = -3 if bool(human_direction(facing).flip) else 3
		var age := float(model.attack.get("age", model.state_age))
		var definition: Dictionary = model.attack.get("definition", model.weapon_definition())
		var startup := float(definition.startup_ticks)
		var active := float(definition.active_ticks)
		var progress := clampf(age / maxf(1.0, startup + active), 0.0, 1.0)
		if weapon == "W02":
			# Line hit geometry reads as a line in every source/mirrored view.
			direction = facing
			var extension := -4.0 * clampf(age / startup, 0.0, 1.0) if age < startup else 10.0 * (1.0 - clampf((age - startup) / active, 0.0, 1.0))
			hand += facing * extension
		elif weapon == "W04":
			# Raise the short shaft, then drive the heavy head down toward aim.
			direction = facing.rotated(lerpf(-1.9, 0.0, progress))
			hand.y -= 5.0 * (1.0 - progress)
		else:
			direction = facing.rotated(lerpf(-1.1, 0.9, progress))
	return {"direction": direction, "hand": hand, "weapon": weapon}


func effect_policy(model) -> Dictionary:
	return {"hurt_flash": not reduced_effects and model.is_player_invulnerable() and model.player_state != "dodge" and posmod(model.tick, 6) < 3,
		"dodge_trails": 0 if reduced_effects else 2, "death_debris": 0 if reduced_effects else 8}


func draw_arena(canvas: Node2D, model, _cosmetic_time: float = 0.0) -> void:
	canvas.draw_rect(Rect2(0, 0, 640, 360), Color("02080a"))
	if arena != null:
		# Align the generated rim to the unchanged ground ellipse. The outer
		# darkness is ornamental; the gameplay boundary still comes from Geometry.
		canvas.draw_texture_rect(arena, Rect2(50, 7, 540, 360), false, Color("b1c3c4"))
	var phase := clampi(int(model.phase_id), 1, 5)
	var tint: Color = PHASE_TINTS[phase - 1]
	if phase >= 4 and boss_frames.size() == 18:
		# The true body stays motionless behind the world in the final phase.
		var large := Rect2(194, -115, 252, 252)
		canvas.draw_texture_rect(boss_frames[1], large, false, Color(tint, 0.10 if phase == 4 else 0.17))
	for i in range(32):
		var angle := float(i) * TAU / 32.0
		var position := (CENTER + Vector2(cos(angle) * (RADII.x + 6), sin(angle) * (RADII.y + 4))).round()
		if phase == 2:
			canvas.draw_rect(Rect2(position + Vector2(-2, -4), Vector2(2, 4 + posmod(i, 4))), Color(tint, 0.55))
		elif phase == 3:
			canvas.draw_line(position, position + Vector2(3, -4 - posmod(i, 5)), Color(tint, 0.42), 1)
		elif phase >= 4:
			canvas.draw_rect(Rect2(position, Vector2(2, 2)), Color(tint, 0.35))
	# Broken one-pixel dotted rim is a precise boundary cue over the art.
	for i in range(112):
		var angle := float(i) * TAU / 112.0
		var position := (CENTER + Vector2(cos(angle), sin(angle)) * RADII).round()
		canvas.draw_rect(Rect2(position, Vector2.ONE), Color(tint, 0.29))


func draw_player(canvas: Node2D, model, cosmetic_time: float = 0.0) -> void:
	if human_frames.size() != 40:
		return
	var p: Vector2 = model.player_pos.round()
	var pose := human_pose(model)
	var effects := effect_policy(model)
	_shadow(canvas, p + Vector2(0, 1), Vector2(9, 3), 0.55)
	var dead: bool = model.player_hp <= 0.0
	if dead:
		if _human_death_started < 0.0:
			_human_death_started = cosmetic_time
		var collapse := clampf((cosmetic_time - _human_death_started) / 0.50, 0.0, 1.0)
		pose.rotation = lerpf(0.0, PI * 0.46, collapse)
		pose.offset = Vector2(0, lerpf(0.0, 22.0, collapse))
	else:
		_human_death_started = -1.0
	var tint := Color.WHITE
	if bool(effects.hurt_flash):
		tint = Color(1.45, 1.24, 0.95, 1.0)
	if model.player_state == "dodge":
		var direction: Vector2 = model.player_facing
		for i in range(int(effects.dodge_trails), 0, -1):
			_actor(canvas, human_frames[pose.frame], p - direction * float(i * 6), Vector2(48, 48), Vector2(24, 42) - Vector2(pose.offset), bool(pose.flip), float(pose.rotation), Color("536d6e", 0.12 + 0.06 * (3 - i)))
	_actor(canvas, human_frames[pose.frame], p, Vector2(48, 48), Vector2(24, 42) - Vector2(pose.offset), bool(pose.flip), float(pose.rotation), Color(tint, 0.62) if dead else tint)
	if dead:
		for i in range(int(effects.death_debris)):
			canvas.draw_rect(Rect2(p + Vector2(posmod(i * 7, 19) - 9, -posmod(i * 11, 9)), Vector2.ONE), Color("89958c", 0.5))
		return
	# The foot marker communicates actual aim and is never hidden by a cape.
	var facing: Vector2 = model.player_facing
	var tip := p + facing * 11.0
	var side := facing.orthogonal() * 2.0
	canvas.draw_polyline(PackedVector2Array([tip - facing * 3 + side, tip, tip - facing * 3 - side]), Color("c9d3bc"), 1)
	var ready := clampf(1.0 - float(model.next_dodge_tick - model.tick) / float(model.data.player.dodge_cooldown), 0.0, 1.0)
	canvas.draw_arc(p, 9.0, -PI / 2, -PI / 2 + TAU * maxf(0.001, ready), 24, Color("8ea696") if ready >= 1.0 else Color("3b605e"), 1)
	if model.player_state != "dodge":
		var held_weapon := weapon_pose(model)
		draw_weapon(canvas, p + Vector2(held_weapon.hand), Vector2(held_weapon.direction), str(held_weapon.weapon), 0.82)
	if model.element_charges > 0:
		_draw_relic(canvas, element_frame(str(model.element_id)), Rect2(p + Vector2(-15, -26), Vector2(10, 10)), Color.WHITE)
	if model.frost_guard_until > model.tick:
		canvas.draw_arc(p + Vector2(0, -17), 15, 0, TAU, 6, Color("b6deeb"), 1)


func draw_boss(canvas: Node2D, model, cosmetic_time: float = 0.0) -> void:
	if boss_frames.size() != 18:
		return
	var p: Vector2 = model.boss_pos.round()
	var pose := boss_pose(model)
	var phase := clampi(int(model.phase_id), 1, 5)
	var tint: Color = PHASE_TINTS[phase - 1]
	_shadow(canvas, p + Vector2(0, 2), Vector2(31, 8), 0.58)
	if phase >= 4 and model.boss_hp > 0.0:
		for i in range(2, 0, -1):
			_actor(canvas, boss_frames[pose.frame], p + Vector2(-i * 9, i * 2), Vector2(104, 104), Vector2(52, 100), bool(pose.flip), 0, Color(tint, 0.10))
	var modulate_color := tint.lightened(0.22)
	if model.boss_hp <= 0.0:
		if _boss_death_started < 0.0:
			_boss_death_started = cosmetic_time
		var collapse := clampf((cosmetic_time - _boss_death_started) / 0.65, 0.0, 1.0)
		if collapse < 0.22:
			pose.frame = int(pose.row) * 6 + 4
		modulate_color = Color(tint.darkened(0.28 * collapse), lerpf(1.0, 0.55, collapse))
	else:
		_boss_death_started = -1.0
	_actor(canvas, boss_frames[pose.frame], p, Vector2(104, 104), Vector2(52, 100), bool(pose.flip), 0.0, modulate_color)
	if model.boss_hp <= 0.0:
		return
	# Pixel joint/chest changes reuse the shared body rather than five full sets.
	var chest := p + Vector2(0, -65)
	if int(pose.row) == 2:
		chest.y += 9
	if phase >= 2:
		var radius := 3 if phase == 2 else 4
		var beat := 0.5 if reduced_effects else 0.5 + 0.25 * sin(float(model.tick) * 0.15)
		for i in range(8):
			var a := TAU * float(i) / 8.0
			canvas.draw_rect(Rect2((chest + Vector2(cos(a), sin(a)) * radius).round(), Vector2.ONE), Color(tint, beat))
	if model.boss_state in ["telegraph", "execute"]:
		var alpha := 0.95 if model.boss_state == "execute" else 0.5 if reduced_effects else 0.5 + 0.2 * sin(float(model.boss_age) * 0.17)
		canvas.draw_rect(Rect2(chest + Vector2(-1, -1), Vector2(2, 2)), Color("eddfb0", alpha))


func draw_weapon(canvas: Node2D, p: Vector2, direction: Vector2, id: String, scale_value: float = 1.0) -> void:
	var index := clampi(int(id.trim_prefix("W")) - 1, 0, 4)
	if relic_frames.size() != 10:
		return
	var size := float(WEAPON_HEIGHTS.get(id, 28.0)) * scale_value
	canvas.draw_set_transform(p.round(), direction.angle() + PI / 4, Vector2.ONE)
	canvas.draw_texture_rect(relic_frames[index], Rect2(-size * 0.14, -size * 0.86, size, size), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_altar(canvas: Node2D, altar: Dictionary, _cosmetic_time: float = 0.0) -> void:
	var p: Vector2 = Vector2(altar.pos).round()
	_draw_relic(canvas, 5, Rect2(p + Vector2(-19, -20), Vector2(38, 32)), Color.WHITE)
	draw_weapon(canvas, p + Vector2(-6, -6), Vector2(0.7, -0.7), str(altar.weapon), 0.60)
	var progress := clampf(float(altar.get("progress", 0)) / 33.0, 0.0, 1.0)
	if progress > 0.0:
		canvas.draw_arc(p, 19, -PI / 2, -PI / 2 + TAU * progress, 32, Color("f3b16c"), 2)


func draw_pickup(canvas: Node2D, pickup: Dictionary, model) -> void:
	var state := str(pickup.get("state", "ground"))
	if state not in ["flying", "ground", "grounded"]:
		return
	var p: Vector2 = Vector2(pickup.get("pos", Vector2.ZERO)).round()
	var foot := p
	var element := str(pickup.get("element", pickup.get("element_id", "fire")))
	var color: Color = ELEMENT_COLORS.get(element, ELEMENT_COLORS.fire)
	_shadow(canvas, foot, Vector2(7, 2), 0.4)
	if state == "flying":
		var progress := clampf(float(pickup.get("age", 0)) / float(model.data.fire.flight_ticks), 0.0, 1.0)
		p.y -= roundf(sin(progress * PI) * 22.0)
	else:
		p.y -= 6.0 + roundf(sin(float(model.tick) * 0.08 + float(pickup.get("id", 0))) * 1.5)
	var ttl := int(pickup.get("ttl", 600))
	if ttl >= 120 or posmod(model.tick, 12) >= 5:
		_draw_relic(canvas, element_frame(element), Rect2(p - Vector2(8, 12), Vector2(16, 16)), Color.WHITE)
		# The small luminous shape floats; danger remains flat on the floor.
		canvas.draw_arc(foot, 9, 0, TAU, 24, Color(color, 0.55), 1)


func element_frame(element: String) -> int:
	return {"fire": 6, "frost": 7, "lightning": 8, "void": 9}.get(element, 6)


func _draw_relic(canvas: Node2D, frame: int, rect: Rect2, tint: Color) -> void:
	if relic_frames.size() == 10:
		canvas.draw_texture_rect(relic_frames[clampi(frame, 0, 9)], rect, false, tint)


func _actor(canvas: Node2D, texture: Texture2D, p: Vector2, size: Vector2, anchor: Vector2, flip: bool, rotation: float, tint: Color) -> void:
	# A negative texture rectangle flips its pixels but Godot normalizes its
	# size around the rectangle origin. Reflect the local transform instead so
	# both the sprite and its socket remain anchored at the actual footpoint.
	canvas.draw_set_transform(p, rotation, Vector2(-1, 1) if flip else Vector2.ONE)
	canvas.draw_texture_rect(texture, Rect2(-anchor, size), false, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _shadow(canvas: Node2D, position: Vector2, radius: Vector2, alpha: float) -> void:
	# Pixel-stepped ellipses keep sprite shadows on the same grid.
	for y in range(-int(radius.y), int(radius.y) + 1):
		var half_width := floorf(radius.x * sqrt(maxf(0.0, 1.0 - pow(float(y) / maxf(1.0, radius.y), 2))))
		canvas.draw_rect(Rect2(position + Vector2(-half_width, y), Vector2(half_width * 2 + 1, 1)), Color(0.0, 0.0, 0.0, alpha))
