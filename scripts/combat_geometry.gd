extends RefCounted
## All telegraphs and collision tests share these ground-space definitions.

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
			var half_arc: float = shape.get("arc_radians", PI) * 0.5
			if relative.length() > reach + radius:
				return false
			if relative.length() <= radius:
				return true
			if absf(facing.angle_to(relative)) <= half_arc:
				return true
			# A target disk can intersect either radial edge outside the angular span.
			for edge_angle in [-half_arc, half_arc]:
				var edge = origin + facing.rotated(edge_angle) * reach
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, origin, edge)) <= radius:
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
		points.append(origin)
		for i in range(segments + 1):
			points.append(origin + facing.rotated(-arc * 0.5 + arc * float(i) / segments) * float(shape.get("radius", 0.0)))
	return points
