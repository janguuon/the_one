extends SceneTree
const Main=preload("res://scenes/main.tscn")
const Store=preload("res://scripts/profile_store.gd")
var count=0
var failed=0
func _initialize():
	call_deferred("run")
func check(value,message):
	count+=1
	if not value:
		failed+=1
	print(("PASS " if value else "FAIL ")+message)
func key(main,code):
	var e=InputEventKey.new()
	e.keycode=code
	e.physical_keycode=code
	e.pressed=true
	main._unhandled_input(e)
func scene():
	var main=Main.instantiate()
	main.profile_enabled=false
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	return main
func run():
	var main=scene()
	main.screen="seed"
	key(main,KEY_ESCAPE)
	check(main.screen=="title","Escape seed returns title")
	main._open_settings("paused")
	key(main,KEY_ESCAPE)
	check(main.screen=="paused","Escape settings returns paused")
	main.model.selection_pending=true
	main.screen="oaths"
	key(main,KEY_ESCAPE)
	check(main.screen=="oaths" and main.model.selection_pending,"Escape cannot bypass oath choice")
	main.starting_weapon="W03"
	main._start_run("practice",3)
	var old_seed=main.seed_value
	main._retry_run(true)
	check(main.model.weapon_id=="W03" and main.seed_value!=old_seed,"New seed keeps selected starting weapon")
	check(main.model.phase_id==3,"New seed practice keeps selected phase")
	main._start_run("official",1)
	main.developer_practice=true
	main.model.highest_phase_reached=5
	main._physics_process(1.0/60)
	check(main.unlocked_practice==1,"DEV official simulation never grants phase unlock")
	main._record_result("victory")
	check(main.official_records.is_empty(),"DEV simulation never creates official result")
	main.model.events.assign([{"type":"phase_reached","phase":5},{"type":"weapon_swap","weapon":"W04"},{"type":"telegraph","pattern":"execution"}])
	main._read_events()
	check(main.unlocked_practice==1 and not main.discovered_weapons.has("W04") and main.profile.seen_patterns.is_empty(),"DEV events never grant discoveries or seen patterns")
	main.free()
	main=scene()
	main.starting_weapon="W05"
	key(main,KEY_ENTER)
	check(main.model.weapon_id=="W01","Normal menu refuses undiscovered developer starting weapon")
	main.free()
	main=scene()
	main._start_run("official",1)
	main.profile_enabled=true
	main.profile_path="user://m4-ui-boundary/profile.json"
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var saved=Store.load_profile(main.profile_path).profile
	check(saved.official_records.size()==1 and saved.official_records[0].result=="abandoned","Window quit saves one official abandoned record")
	# Saving is synchronous; the native mixer drain is intentionally asynchronous.
	# Let the close coroutine finish before disposing its owning scene.
	await main.audio_director.shutdown_finished
	print("M4 UI BOUNDARY: ",count," checks, ",failed," failures")
	main.queue_free()
	quit(0 if failed==0 else 1)
