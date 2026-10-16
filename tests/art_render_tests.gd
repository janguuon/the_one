extends SceneTree
## Native-renderer regression for a bug that pose-only tests cannot catch:
## negative texture rectangles moved mirrored bodies away from their footpoint.
const Art = preload("res://scripts/pixel_art.gd")
const FOOT := Vector2(128, 220)
var checks := 0
var failures: Array[String] = []

class SpriteFixture extends Node2D:
	var art
	var texture: Texture2D
	var sprite_size := Vector2.ZERO
	var anchor := Vector2.ZERO
	var flip := false
	func _draw() -> void:
		if texture != null:
			art._actor(self, texture, FOOT, sprite_size, anchor, flip, 0.0, Color.WHITE)


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("art_render_tests.gd requires a native renderer; headless cannot validate sprite placement")
		quit(1)
		return
	var art := Art.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var fixture := SpriteFixture.new()
	fixture.art = art
	viewport.add_child(fixture)
	for row in range(5):
		await _verify_mirror(viewport, fixture, art.human_frames[row * 8], Vector2(48, 48), Vector2(24, 42), "human view %d" % row)
	for row in range(3):
		await _verify_mirror(viewport, fixture, art.boss_frames[row * 6], Vector2(104, 104), Vector2(52, 100), "boss view %d" % row)
	print("NATIVE ART RENDER: %d checks, %d failures | renderer=%s" % [checks, failures.size(), RenderingServer.get_video_adapter_name()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _verify_mirror(viewport: SubViewport, fixture: SpriteFixture, texture: Texture2D, size: Vector2, anchor: Vector2, label: String) -> void:
	fixture.texture = texture
	fixture.sprite_size = size
	fixture.anchor = anchor
	fixture.flip = false
	var normal: Dictionary = await _render(viewport, fixture)
	fixture.flip = true
	var mirrored: Dictionary = await _render(viewport, fixture)
	var a: Rect2i = normal.bounds
	var b: Rect2i = mirrored.bounds
	_check(a.size.x > 3 and a.size.y > 3 and b.size == a.size, "%s actually renders equal nonempty body bounds on both facings" % label)
	var expected_left := int(FOOT.x) * 2 - (a.position.x + a.size.x)
	_check(absi(b.position.x - expected_left) <= 1, "%s reflected bounds stay around the unchanged ground footpoint" % label)
	_check(absf(Vector2(normal.center).x + Vector2(mirrored.center).x - FOOT.x * 2.0) < 1.0, "%s visible body centroids mirror around the ground footpoint" % label)
	_check(a.position.y == b.position.y and normal.pixels == mirrored.pixels, "%s flipping never shifts body height or loses pixels" % label)


func _render(viewport: SubViewport, fixture: SpriteFixture) -> Dictionary:
	fixture.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := viewport.get_texture().get_image()
	var bounds := frame.get_used_rect()
	var center := Vector2.ZERO
	var pixels := 0
	for y in range(frame.get_height()):
		for x in range(frame.get_width()):
			if frame.get_pixel(x, y).a > 0.5:
				center += Vector2(x + 0.5, y + 0.5)
				pixels += 1
	return {"bounds": bounds, "center": center / maxf(1, pixels), "pixels": pixels}
