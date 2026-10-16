extends SceneTree
## Native render/physics sample, driven with the same gameplay input boundary.
## No engine headless performance claims and no physical-device claim.
const Main = preload("res://scenes/main.tscn")
const Policy = preload("res://tests/m3_playthrough.gd")
var main
var samples: Array[float] = []
var physics_samples: Array[float] = []
var process_samples: Array[float] = []
var seconds = 0.0
var warmup = 2.0
var duration = 8.0
var fps_cap = 60
var window_size = Vector2i(1280,720)
var output_path = "res://.tools/runtime-data/performance/native-60.json"
var snapshot_path = ""
var finished = false
var tick_start = 0
var last_sample_usec = 0
var selected_pattern = ""
var max_hazards = 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fps="):
			fps_cap = int(arg.trim_prefix("--fps="))
		elif arg.begins_with("--size="):
			var parts = arg.trim_prefix("--size=").split("x")
			window_size = Vector2i(int(parts[0]),int(parts[1]))
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--snapshot="):
			snapshot_path = arg.trim_prefix("--snapshot=")
		elif arg.begins_with("--seconds="):
			duration = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--pattern="):
			selected_pattern = arg.trim_prefix("--pattern=")
	Engine.max_fps = fps_cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(window_size)
	call_deferred("_setup")

func _setup() -> void:
	main = Main.instantiate()
	main.profile_enabled = false
	root.add_child(main)
	main.developer_practice = true
	main._start_run("practice",5)
	if not selected_pattern.is_empty():
		main.model.debug_start_pattern(selected_pattern)
	physics_frame.connect(_drive)
	process_frame.connect(_sample)

func _drive() -> void:
	if finished or main == null:
		return
	var command: Dictionary = Policy.decide(main.model)
	var movement: Vector2 = command.get("move",Vector2.ZERO)
	for entry in [["move_left",-movement.x],["move_right",movement.x],["move_up",-movement.y],["move_down",movement.y]]:
		if float(entry[1]) > 0:
			Input.action_press(entry[0],float(entry[1]))
		else:
			Input.action_release(entry[0])
	for action in ["attack","dodge"]:
		if command.get(action,false):
			var event = InputEventAction.new()
			event.action = action
			event.pressed = true
			main._unhandled_input(event)
			event = InputEventAction.new()
			event.action = action
			event.pressed = false
			main._unhandled_input(event)

func _sample() -> void:
	if finished or main == null:
		return
	var now_usec = Time.get_ticks_usec()
	if last_sample_usec == 0:
		last_sample_usec = now_usec
		return
	# Sample the real monotonic clock, not Godot's smoothed gameplay delta.
	var delta: float = float(now_usec - last_sample_usec) / 1000000.0
	last_sample_usec = now_usec
	seconds += delta
	if seconds <= warmup:
		tick_start = main.model.tick
		return
	if seconds < warmup + duration:
		max_hazards = maxi(max_hazards,main.model.hazards.size())
		samples.append(delta * 1000.0)
		process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	else:
		finished = true
		_finish.call_deferred()

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted = values.duplicate()
	sorted.sort()
	var sum = 0.0
	for value in values:
		sum += value
	return {"mean_ms":snappedf(sum / values.size(),0.001),"p95_ms":snappedf(sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],0.001),"p99_ms":snappedf(sorted[mini(sorted.size()-1,int(sorted.size()*0.99))],0.001),"max_ms":snappedf(sorted.back(),0.001)}

func _finish() -> void:
	if not snapshot_path.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(snapshot_path)
	var report = {"engine":Engine.get_version_info().string,"driver":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"window":str(window_size),"logical_viewport":str(main.get_viewport_rect().size),"fps_cap":fps_cap,"sample_seconds":duration,"frames":samples.size(),"combat_ticks":main.model.tick-tick_start,"hitstop":main.hitstop_remaining,"wall_seconds":main.wall_seconds,"requested_pattern":selected_pattern,"max_hazards":max_hazards,"frame":_stats(samples),"process":_stats(process_samples),"physics":_stats(physics_samples)}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	var file = FileAccess.open(output_path,FileAccess.WRITE)
	if file == null:
		push_error("Cannot write performance report")
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PRESENTATION_BENCHMARK ",JSON.stringify(report))
	var code = 0 if DisplayServer.get_name() != "headless" and not samples.is_empty() else 1
	await main.audio_director.shutdown()
	main.free()
	main = null
	# AudioServer and scene destruction both need live main-loop cleanup.
	await process_frame
	await process_frame
	quit(code)
