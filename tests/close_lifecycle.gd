extends SceneTree
## Window close with real audio on native runs; headless uses Main's cue-only
## policy. Neither path suppresses engine warnings or resource errors.
const Main = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/profile_store.gd")
const PATH = "user://m5-close/profile.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS: " if value else "FAIL: ") + message)

func _run() -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	var main = Main.instantiate()
	main.profile_path = PATH
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main._start_run("official", 1)
	main.audio_director.menu_action(true)
	await create_timer(0.03).timeout
	main.screen = "paused"
	main._update_audio(1.0 / 60)
	var tick: int = main.model.tick
	var attacks: int = main.model.total_attacks
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(main.closing, "Window close enters one guarded shutdown")
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var saved: Dictionary = Store.load_profile(PATH).profile
	_check(saved.official_records.size() == 1 and saved.official_records[0].result == "abandoned", "Paused window close persists one abandonment before draining audio")
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.physical_keycode = KEY_R
	event.pressed = true
	main._unhandled_input(event)
	main._physics_process(1.0 / 60)
	_check(main.model.tick == tick and main.model.total_attacks == attacks and main.closing, "Shutdown rejects retry/input and freezes combat")
	await main.audio_director.shutdown_finished
	_check(main.audio_director._shutdown_complete and main.audio_director._streams.is_empty(), "Close drains and releases live audio resources before quitting")
	print("CLOSE LIFECYCLE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
