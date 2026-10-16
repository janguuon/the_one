extends SceneTree
## Rendering must accept every clipped piece while preserving collision rules.
const Geo = preload("res://scripts/combat_geometry.gd")
const Patterns = preload("res://scripts/boss_patterns.gd")
const CENTER := Vector2(320, 184)
var checks := 0
var failures: Array[String] = []
var timeline_ticks := 0
var polygon_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _run() -> void:
	_test_tangent_wave()
	_test_cache_isolation()
	_test_all_patterns()
	print("GEOMETRY RENDER: %d checks, %d failures, %d timeline ticks, %d clipped polygons" % [checks, failures.size(), timeline_ticks, polygon_count])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _test_tangent_wave() -> void:
	# Actual last_horizon wave at age296: arena intersection leaves a triangle
	# of only 0.00205 square pixels. Its world-coordinate area cancels to zero.
	var shape := {"shape":"ring", "origin":Vector2(320,135), "radius":252.0, "width":8.0}
	var pieces := Geo.polygons(shape)
	var total_area := 0.0
	var tiny_count := 0
	var invalid_count := 0
	for piece in pieces:
		var area := _area(piece)
		total_area += area
		if area < 0.01 and area > 0.0001:
			tiny_count += 1
		if Geometry2D.triangulate_polygon(piece).is_empty():
			invalid_count += 1
	print("TANGENT_WAVE area=",total_area," pieces=",pieces.size()," tiny=",tiny_count," invalid=",invalid_count)
	_check(invalid_count == 0, "Actual P5 tangent wave yields only drawable polygons")
	_check(tiny_count >= 1, "Subpixel tangent fill is preserved rather than silently deleting the failed piece")
	_check(absf(total_area - 1565.34665996092) < 0.0001 and pieces.size() == 12, "Repair preserves the original wave's clipped area and all 12 pieces")
	var originals := _raw_ring_pieces(shape)
	var unchanged := originals.size() == pieces.size()
	for index in range(mini(originals.size(), pieces.size())):
		var original: PackedVector2Array = originals[index]
		var rendered: PackedVector2Array = pieces[index]
		unchanged = unchanged and absf(_area(original) - _area(rendered)) < 0.000001
		for point in original:
			unchanged = unchanged and rendered.has(point)
		unchanged = unchanged and original.size() == rendered.size()
	_check(unchanged, "Every clipped world-coordinate vertex is identical; only winding may change")
	_check(not Geo.contains(shape, Vector2(320,135)) and Geo.contains(shape, Vector2(572,135)), "Rendering correction preserves the exact ring collision definition and its hole")


func _raw_ring_pieces(shape: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var origin: Vector2 = shape.origin
	var inner := float(shape.radius) - float(shape.width) * 0.5
	var outer := float(shape.radius) + float(shape.width) * 0.5
	for index in range(64):
		var a := Vector2.RIGHT.rotated(TAU * float(index) / 64.0)
		var b := Vector2.RIGHT.rotated(TAU * float(index + 1) / 64.0)
		var strip := PackedVector2Array([origin + a * inner, origin + a * outer, origin + b * outer, origin + b * inner])
		for clipped in Geometry2D.intersect_polygons(strip, Geo.arena_polygon()):
			if clipped.size() >= 3:
				result.append(clipped)
	return result


func _test_cache_isolation() -> void:
	Geo.clear_render_cache()
	var shape := {"shape":"ring", "origin":Vector2(320,184), "radius":70.0, "width":8.0}
	var first := Geo.polygons(shape)
	var expected := first.duplicate(true)
	var original_key: int = Geo._clipped_render_cache.keys()[0]
	Geo._clipped_render_cache[original_key] = {"signature":["simulated_hash_collision"],"pieces":first}
	_check(Geo.polygons(shape) == expected, "A matching hash with different exact parameters cannot return another shape's cached fill")
	first.clear()
	_check(Geo.polygons(shape) == expected, "Clearing a caller's returned array cannot erase cached danger geometry")
	var edited := Geo.polygons(shape)
	edited[0][0] = Vector2(-100,-100)
	_check(Geo.polygons(shape) == expected, "Editing a returned point cannot corrupt another frame's cached geometry")
	var decorated := shape.duplicate(true)
	decorated.phase = "active"
	decorated.progress = 0.97
	decorated.event_id = "different_event"
	_check(Geo.polygons(decorated) == expected, "Changing only telegraph progress and event labels preserves identical ground vertices")
	var fixtures := [
		{"shape":"sector","origin":Vector2(320,184),"facing":Vector2.RIGHT,"radius":56.0,"inner_radius":12.0,"arc_radians":1.8},
		{"shape":"line","origin":Vector2(320,184),"facing":Vector2.RIGHT,"length":140.0,"width":24.0},
		{"shape":"ring","origin":Vector2(320,184),"radius":90.0,"width":8.0},
		{"shape":"annulus","origin":Vector2(320,184),"inner_radius":64.0,"outer_radius":800.0},
		{"shape":"disk","origin":Vector2(320,184),"radius":56.0},
		{"shape":"capsule","origin":Vector2(320,184),"facing":Vector2.RIGHT,"end":Vector2(420,220),"width":24.0},
		{"shape":"corridor","origin":Vector2(320,184),"facing":Vector2.RIGHT,"width":60.0},
	]
	for base in fixtures:
		Geo.polygons(base)
		for field in base:
			if field == "shape": continue
			var changed: Dictionary = base.duplicate(true)
			changed[field] = Vector2(base[field]) + Vector2(0.125,-0.0625) if base[field] is Vector2 else float(base[field]) + 0.125
			_check(Geo.polygons(changed) == Geo._render_polygons_uncached(changed,64), "A changed %s %s gets exactly its own geometry after a cached frame" % [base.shape,field])
		_check(Geo.polygons(base,32) == Geo._render_polygons_uncached(base,32), "%s cache respects different polygon sampling counts" % base.shape)
	var arena := Geo.arena_polygon()
	arena[0] = Vector2.ZERO
	_check(Geo.arena_polygon()[0] == Vector2(580,184), "Arena cache remains immutable through caller edits")
	for index in range(200):
		Geo.polygons({"shape":"disk","origin":Vector2(200 + index * 0.125,184),"radius":20.0})
	_check(Geo._clipped_render_cache.size() <= Geo.RENDER_CACHE_LIMIT, "Moving geometry cannot grow the render cache without a bound")
	_check(Geo.polygons(shape) == expected, "Cache eviction regenerates the exact original danger geometry")


func _test_all_patterns() -> void:
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_patterns.json"))
	var states := [{"boss":Vector2(320,135),"player":Vector2(320,280)}, {"boss":Vector2(150,110),"player":Vector2(180,160)}, {"boss":Vector2(485,258),"player":Vector2(500,230)}]
	for id in definitions:
		for index in range(states.size()):
			var runner := Patterns.new()
			runner.configure(72.0,90.24)
			var rng := RandomNumberGenerator.new()
			rng.seed = 1 + index * 17
			var state: Dictionary = states[index]
			runner.start(str(id), state.boss, state.player, rng)
			_check(runner.safety_error.is_empty() and runner.duration > 0, "%s state%d has a legal original or bounded fallback timeline" % [id,index])
			var invalid := ""
			for age in range(runner.duration + 1):
				var snapshot: Dictionary = runner.update(age, state.player)
				timeline_ticks += 1
				for hazard in snapshot.hazards:
					for piece in Geo.polygons(hazard):
						polygon_count += 1
						if Geometry2D.triangulate_polygon(piece).is_empty() and invalid.is_empty():
							invalid = "age%d %s points%s area%.8f" % [age,hazard.get("shape",""),str(piece),_area(piece)]
			_check(invalid.is_empty(), "%s state%d all live and warning fills triangulate%s" % [id,index,"" if invalid.is_empty() else ": " + invalid])


func _area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var area := 0.0
	# Origin-relative products avoid large world-coordinate cancellation.
	for index in range(1, points.size() - 1):
		area += (points[index] - points[0]).cross(points[index + 1] - points[0]) * 0.5
	return absf(area)
