extends SceneTree
## Matched CPU microbenchmark of real last_horizon geometry. No GPU claims.
const Geo = preload("res://scripts/combat_geometry.gd")
const Patterns = preload("res://scripts/boss_patterns.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var runner := Patterns.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	runner.start("last_horizon", Vector2(320,135), Vector2(320,280), rng)
	var snapshots: Array[Dictionary] = []
	for age in [100,130,180,235,240,260,280,296,310]:
		snapshots.append(runner.update(age, Vector2(320,280)))
	var uncached := _measure(snapshots, false)
	Geo.clear_render_cache()
	var cached := _measure(snapshots, true)
	print("POLYGON_CPU_BENCH ",JSON.stringify({"calls":cached.calls,"pieces":cached.pieces,"uncached_ms":float(uncached.usec)/1000.0,"cached_ms":float(cached.usec)/1000.0,"speedup":float(uncached.usec)/maxf(1,cached.usec),"identical_counts":uncached.pieces==cached.pieces}))
	quit()

func _measure(snapshots: Array[Dictionary], cached: bool) -> Dictionary:
	var calls := 0
	var pieces := 0
	var started := Time.get_ticks_usec()
	for repetition in range(300):
		for snapshot in snapshots:
			for hazard in snapshot.hazards:
				pieces += Geo.polygons(hazard).size() if cached else Geo._render_polygons_uncached(hazard,64).size()
				calls += 1
	var elapsed := Time.get_ticks_usec() - started
	return {"calls":calls,"pieces":pieces,"usec":elapsed}
