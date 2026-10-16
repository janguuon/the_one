extends RefCounted
## All telegraphs and collision tests share these ground-space definitions.

const RENDER_CACHE_LIMIT := 128
static var _arena_render_cache: Dictionary = {}
static var _clipped_render_cache: Dictionary = {}

static func clamp_arena(point: Vector2, center: Vector2, radii: Vector2, inset: float = 0.0) -> Vector2:
	var inner = radii - Vector2.ONE * inset
	var offset = point - center
	var unit = Vector2(offset.x / inner.x, offset.y / inner.y)
	if unit.length_squared() <= 1.0:
		return point
	# Closest ellipse point via its normal (Lagrange multiplier). Radial
	# normalization would add an unwanted tangential jump at diagonal edges.
	var squared = inner * inner
	var low = 0.0
	var high = maxf(inner.x * absf(offset.x), inner.y * absf(offset.y))
	for i in range(40):
		var probe = Vector2(inner.x * offset.x / (squared.x + high), inner.y * offset.y / (squared.y + high))
		if probe.length_squared() <= 1.0:
			break
		high *= 2.0
	for i in range(40):
		var middle = (low + high) * 0.5
		var probe = Vector2(inner.x * offset.x / (squared.x + middle), inner.y * offset.y / (squared.y + middle))
		if probe.length_squared() > 1.0:
			low = middle
		else:
			high = middle
	return center + Vector2(squared.x * offset.x / (squared.x + high), squared.y * offset.y / (squared.y + high))

static func in_arena(point: Vector2, center: Vector2, radii: Vector2, inset: float = 0.0) -> bool:
	return point.distance_to(clamp_arena(point, center, radii, inset)) < 0.001

static func contains(shape: Dictionary, point: Vector2, radius: float = 0.0) -> bool:
	var origin: Vector2 = shape.get("origin", Vector2.ZERO)
	var facing: Vector2 = shape.get("facing", Vector2.RIGHT)
	var relative = point - origin
	match shape.get("shape", ""):
		"sector":
			var reach: float = shape.get("radius", 0.0)
			var inner: float = shape.get("inner_radius", 0.0)
			var half_arc: float = shape.get("arc_radians", PI) * 0.5
			if relative.length() > reach + radius:
				return false
			if relative.length() + radius < inner:
				return false
			if relative.length() <= radius:
				return true
			if absf(facing.angle_to(relative)) <= half_arc:
				return true
			# A target disk can intersect either radial edge outside the angular span.
			for edge_angle in [-half_arc, half_arc]:
				var edge_start = origin + facing.rotated(edge_angle) * inner
				var edge = origin + facing.rotated(edge_angle) * reach
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, edge_start, edge)) <= radius:
					return true
			return false
		"line":
			var along = relative.dot(facing)
			var across = relative.dot(facing.orthogonal())
			var length: float = shape.get("length", 0.0)
			var half_width: float = shape.get("width", 0.0) * 0.5
			var closest = Vector2(clampf(along, 0.0, length), clampf(across, -half_width, half_width))
			return Vector2(along, across).distance_to(closest) <= radius
		"ring":
			return absf(relative.length() - float(shape.get("radius", 0.0))) <= float(shape.get("width", 0.0)) * 0.5 + radius
		"disk":
			return relative.length() <= float(shape.get("radius", 0.0)) + radius
		"annulus":
			return relative.length() + radius >= float(shape.get("inner_radius", 0.0)) and relative.length() - radius <= float(shape.get("outer_radius", 800.0))
		"corridor":
			# The corridor is the safe gap; both outside half planes are dangerous.
			return absf(relative.dot(facing.orthogonal())) + radius >= float(shape.get("width", 60.0)) * 0.5
		"capsule":
			var end: Vector2 = shape.get("end", origin + facing * float(shape.get("length", 0.0)))
			return point.distance_to(Geometry2D.get_closest_point_to_segment(point, origin, end)) <= float(shape.get("width", 0.0)) * 0.5 + radius
	return false

static func polygon(shape: Dictionary, segments: int = 40) -> PackedVector2Array:
	var points = PackedVector2Array()
	var origin: Vector2 = shape.get("origin", Vector2.ZERO)
	var facing: Vector2 = shape.get("facing", Vector2.RIGHT)
	if shape.get("shape", "") == "line":
		var side = facing.orthogonal() * float(shape.get("width", 0.0)) * 0.5
		var end = origin + facing * float(shape.get("length", 0.0))
		return PackedVector2Array([origin + side, end + side, end - side, origin - side])
	if shape.get("shape", "") == "sector":
		var arc: float = shape.get("arc_radians", PI)
		var inner: float = shape.get("inner_radius", 0.0)
		if inner <= 0.0:
			points.append(origin)
		for i in range(segments + 1):
			points.append(origin + facing.rotated(-arc * 0.5 + arc * float(i) / segments) * float(shape.get("radius", 0.0)))
		if inner > 0.0:
			for i in range(segments, -1, -1):
				points.append(origin + facing.rotated(-arc * 0.5 + arc * float(i) / segments) * inner)
	if shape.get("shape", "") == "disk":
		for i in range(segments):
			points.append(origin + Vector2.RIGHT.rotated(TAU * float(i) / segments) * float(shape.get("radius", 0.0)))
	if shape.get("shape", "") == "capsule":
		var end: Vector2 = shape.get("end", origin + facing * float(shape.get("length", 0.0)))
		var half_width: float = float(shape.get("width", 0.0)) * 0.5
		if end.distance_squared_to(origin) < 0.000001:
			for i in range(segments):
				points.append(origin + Vector2.RIGHT.rotated(TAU * float(i) / segments) * half_width)
			return points
		for i in range(segments / 2 + 1):
			points.append(end + facing.rotated(-PI * 0.5 + PI * float(i) / (segments / 2)) * half_width)
		for i in range(segments / 2 + 1):
			points.append(origin + facing.rotated(PI * 0.5 + PI * float(i) / (segments / 2)) * half_width)
	return points

static func arena_polygon(segments: int = 64) -> PackedVector2Array:
	if _arena_render_cache.has(segments):
		return _arena_render_cache[segments].duplicate()
	var points := PackedVector2Array()
	for i in range(segments):
		var angle: float = TAU * float(i) / segments
		points.append(Vector2(320, 184) + Vector2(cos(angle) * 260.0, sin(angle) * 126.0))
	_arena_render_cache[segments] = points.duplicate()
	return points

static func polygons(shape: Dictionary, segments: int = 64) -> Array[PackedVector2Array]:
	# Progress, event IDs and phase colors change each tick without changing
	# ground geometry. Cache only exact geometry parameters, never these labels.
	var signature: Array = [segments, shape.get("shape", ""), shape.get("origin", Vector2.ZERO), shape.get("facing", Vector2.RIGHT)]
	for field in ["radius", "width", "length", "inner_radius", "outer_radius", "arc_radians", "end"]:
		signature.append(shape.get(field, null))
	var key: int = signature.hash()
	if _clipped_render_cache.has(key):
		var cached: Dictionary = _clipped_render_cache[key]
		# A hash collision can only miss the cache, never return wrong geometry.
		if cached.signature == signature:
			return _copy_render_pieces(cached.pieces)
	var result := _render_polygons_uncached(shape, segments)
	if _clipped_render_cache.size() >= RENDER_CACHE_LIMIT:
		_clipped_render_cache.clear()
	_clipped_render_cache[key] = {"signature": signature, "pieces": _copy_render_pieces(result)}
	return result

static func _copy_render_pieces(pieces: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	# Packed arrays are shared inside ordinary Array.duplicate(true) too.
	# Give callers their own point buffers so presentation edits stay local.
	var copied: Array[PackedVector2Array] = []
	for piece in pieces:
		copied.append(piece.duplicate())
	return copied

static func clear_render_cache() -> void:
	_clipped_render_cache.clear()
	_arena_render_cache.clear()

static func _render_polygons_uncached(shape: Dictionary, segments: int) -> Array[PackedVector2Array]:
	## Rendering consumes the same parameters as contains(). Split rings avoid a
	## polygon with an unfilled hole being accidentally painted as a full disk.
	var raw: Array[PackedVector2Array] = []
	var result: Array[PackedVector2Array] = []
	var origin: Vector2 = shape.get("origin", Vector2.ZERO)
	var facing: Vector2 = shape.get("facing", Vector2.RIGHT)
	var kind: String = str(shape.get("shape", ""))
	if kind == "ring" or kind == "annulus":
		var inner: float = maxf(0.0, float(shape.get("inner_radius", float(shape.get("radius", 0.0)) - float(shape.get("width", 0.0)) * 0.5)))
		var outer: float = float(shape.get("outer_radius", float(shape.get("radius", 0.0)) + float(shape.get("width", 0.0)) * 0.5))
		for i in range(segments):
			var a: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / segments)
			var b: Vector2 = Vector2.RIGHT.rotated(TAU * float(i + 1) / segments)
			raw.append(PackedVector2Array([origin + a * inner, origin + a * outer, origin + b * outer, origin + b * inner]))
	elif kind == "corridor":
		var side: Vector2 = facing.orthogonal()
		var half: float = float(shape.get("width", 60.0)) * 0.5
		for sign_value in [-1.0, 1.0]:
			var near_side: Vector2 = side * half * float(sign_value)
			var far_side: Vector2 = side * 1200.0 * float(sign_value)
			raw.append(PackedVector2Array([origin - facing * 1200.0 + near_side, origin + facing * 1200.0 + near_side, origin + facing * 1200.0 + far_side, origin - facing * 1200.0 + far_side]))
	else:
		var single: PackedVector2Array = polygon(shape, segments)
		if single.size() >= 3:
			raw.append(single)
	var arena: PackedVector2Array = arena_polygon(segments)
	for piece in raw:
		for clipped in Geometry2D.intersect_polygons(piece, arena):
			if clipped.size() >= 3:
				# At an ellipse tangent Clipper can leave a subpixel triangle.
				# World-coordinate area products may cancel to zero in Godot's
				# winding test although its origin-relative area is positive.
				# Reversing that triangle fixes the winding without moving a
				# point or deleting any fill. Only these small edge triangles
				# need the extra triangulation; ordinary strips stay unchanged.
				if clipped.size() == 3 and Geometry2D.triangulate_polygon(clipped).is_empty():
					clipped.reverse()
				result.append(clipped)
	return result
