extends SceneTree
## Real-file persistence tests isolated from the player's local profile.
const Store = preload("res://scripts/profile_store.gd")
var checks: int = 0
var failures: Array[String] = []
var test_root: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = "user://m4_profile_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_root))
	_test_defaults_and_validation()
	_test_records_and_best()
	_test_save_roundtrip_and_backup()
	_test_corruption_and_backup_recovery()
	_test_write_failures()
	_test_legacy_migration()
	_cleanup(test_root)
	print("PROFILE TESTS: %d checks, %d failures" % [checks, failures.size()])
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures.append(message)


func _path(name: String) -> String:
	return test_root.path_join(name)


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _profile(phase: int = 1) -> Dictionary:
	var profile := Store.defaults()
	profile.highest_phase = phase
	return profile


func _record(result: String = "victory", seconds: float = 100.0, ticks: int = 5000, seed_value: int = 1) -> Dictionary:
	return {"result": result, "phase": 5, "seconds": seconds, "ticks": ticks, "seed": seed_value, "weapon_id": "W03", "oaths": ["O07", "O12"], "element_uses": {"fire": 2, "void": 1}}


func _test_defaults_and_validation() -> void:
	var missing := Store.load_profile(_path("missing.json"))
	_check(missing.profile == Store.defaults() and missing.error.is_empty(), "New profile starts with default progression without a warning")
	_check(missing.profile.discovered_weapons == ["W01"] and missing.profile.highest_phase == 1, "Only sword and P1 start unlocked")
	var first := Store.defaults()
	first.discovered_weapons.append("W05")
	first.settings.fullscreen = true
	_check(Store.defaults().discovered_weapons == ["W01"] and not Store.defaults().settings.fullscreen, "Defaults never share mutable arrays or settings")
	for bad in [null, [], true, "profile", 42]:
		var fixed := Store.sanitize_profile(bad)
		_check(not fixed.valid and fixed.profile == Store.defaults(), "Invalid root value restores safe defaults: %s" % str(bad))
	for version in [null, 0, 2, "1", true, 1.5, INF, NAN]:
		var profile := Store.defaults()
		profile.schema = version
		var fixed := Store.sanitize_profile(profile)
		_check(not fixed.valid and not fixed.error.is_empty(), "Unsupported schema is rejected: %s" % str(version))
	var profile := Store.defaults()
	profile.discovered_weapons = ["W03", "W03", "W99", 3]
	profile.seen_patterns = ["claw", "execution", "not_a_pattern", null, "claw"]
	var fixed := Store.sanitize_profile(profile)
	_check(fixed.profile.discovered_weapons == ["W01", "W03"], "Unknown and duplicate weapons are removed while sword remains available")
	_check(fixed.profile.seen_patterns == ["claw", "execution"] and not fixed.error.is_empty(), "Unknown and duplicate pattern IDs are repaired with a notice")
	profile.discovered_weapons = "W05"
	profile.seen_patterns = {}
	fixed = Store.sanitize_profile(profile)
	_check(fixed.profile.discovered_weapons == ["W01"] and fixed.profile.seen_patterns.is_empty(), "Wrong collection types cannot unlock content")
	for phase in [-50, 0, 6, 100]:
		profile = Store.defaults()
		profile.highest_phase = phase
		fixed = Store.sanitize_profile(profile)
		_check(fixed.profile.highest_phase == clampi(phase, 1, 5) and not fixed.error.is_empty(), "Out-of-range phase is safely clamped: %d" % phase)
	for phase in [true, "5", 2.5, INF, NAN]:
		profile = Store.defaults()
		profile.highest_phase = phase
		fixed = Store.sanitize_profile(profile)
		_check(fixed.profile.highest_phase == 1 and not fixed.error.is_empty(), "Invalid phase cannot grant a phase unlock: %s" % str(phase))
	profile = Store.defaults()
	profile.settings = {"show_particles": false, "debug_visible": "true", "fullscreen": 1, "future_setting": true}
	fixed = Store.sanitize_profile(profile)
	_check(not fixed.profile.settings.show_particles and not fixed.profile.settings.debug_visible and not fixed.profile.settings.fullscreen, "Settings require booleans and preserve valid preferences")
	_check(not fixed.profile.settings.has("future_setting"), "Unknown settings are not loaded into runtime behavior")
	profile.player_hp = 99
	profile.current_phase = 5
	profile.stack = 9
	profile.rng_state = 1234
	fixed = Store.sanitize_profile(profile)
	_check(not fixed.profile.has("player_hp") and not fixed.profile.has("current_phase") and not fixed.profile.has("stack") and not fixed.profile.has("rng_state"), "Profile never serializes a running battle or random state")


func _test_records_and_best() -> void:
	var profile := Store.defaults()
	profile.official_records = [_record("dead", 1.0), _record("abandoned", 2.0), _record("victory", 120.0, 6000), _record("victory", 100.0, 5900), _record("victory", 100.0, 5800)]
	var fixed := Store.sanitize_profile(profile)
	_check(fixed.profile.official_records.size() == 5, "Victory, death, and abandonment remain distinct official records")
	_check(fixed.profile.best_record.seconds == 100.0 and fixed.profile.best_record.ticks == 5800, "Best record uses winning wall time with combat ticks as a tie-breaker")
	_check(fixed.profile.best_record.element_uses == {"fire": 2, "frost": 0, "lightning": 0, "void": 1}, "Missing element counts use safe zero defaults")
	var invalid_records: Array = []
	for result in ["practice_complete", "prototype_complete", "safety_error", "playing", ""]:
		invalid_records.append(_record(result))
	var invalid_win := _record()
	invalid_win.phase = 4
	invalid_records.append(invalid_win)
	for key in ["seed", "ticks", "seconds"]:
		for value in [INF, NAN, "10", true]:
			var record := _record()
			record[key] = value
			invalid_records.append(record)
	var negative := _record()
	negative.ticks = -1
	invalid_records.append(negative)
	negative = _record()
	negative.seconds = -1
	invalid_records.append(negative)
	profile.official_records = invalid_records
	fixed = Store.sanitize_profile(profile)
	_check(fixed.profile.official_records.is_empty() and fixed.profile.best_record.is_empty() and not fixed.error.is_empty(), "Practice, prototype, invalid victory, negative and nonfinite records cannot become official records")
	profile.official_records = []
	for index in range(105):
		profile.official_records.append(_record("victory", 10.0 + index, 6000 + index, index))
	fixed = Store.sanitize_profile(profile)
	_check(fixed.profile.official_records.size() == Store.MAX_RECORDS and fixed.profile.official_records[0].seed == 5 and fixed.profile.official_records[-1].seed == 104, "Recent official history is bounded to the latest 100 runs")
	_check(fixed.profile.best_record.seed == 0, "All-time winning best survives pruning from recent history")
	var best_path := _path("best.json")
	_check(Store.save_profile(best_path, fixed.profile) == OK, "Bounded history and separate all-time best save successfully")
	var loaded := Store.load_profile(best_path)
	_check(loaded.profile.best_record.seed == 0 and loaded.profile.official_records.size() == 100, "All-time best survives a real file round trip")
	var raw := _record()
	raw.weapon_id = "W98"
	raw.oaths = ["O01", "O01", "O99", "O06", "O08", "O12"]
	raw.element_uses = {"fire": -1, "void": INF}
	profile.official_records = [raw]
	fixed = Store.sanitize_profile(profile)
	_check(fixed.profile.official_records[0].weapon_id == "W01" and fixed.profile.official_records[0].oaths == ["O01", "O06", "O08"], "Record weapon and oath IDs are validated and capped to three distinct oaths")
	_check(fixed.profile.official_records[0].element_uses.fire == 0 and fixed.profile.official_records[0].element_uses.void == 0, "Invalid element statistics cannot inject nonfinite values")
	profile.best_record = _record("dead")
	profile.official_records = []
	fixed = Store.sanitize_profile(profile)
	_check(fixed.profile.best_record.is_empty(), "A death cannot be restored as the best winning record")


func _test_save_roundtrip_and_backup() -> void:
	var path := _path("nested/profile.json")
	var first := _profile(2)
	first.discovered_weapons = ["W01", "W05"]
	first.seen_patterns = ["claw", "rings"]
	first.settings = {"show_particles": false, "debug_visible": true, "fullscreen": true}
	first.official_records = [_record("dead", 32.25, 1900)]
	_check(Store.save_profile(path, first) == OK, "Saving creates the dedicated profile directory and verified main file")
	var loaded := Store.load_profile(path)
	_check(loaded.profile == Store.sanitize_profile(first).profile and loaded.error.is_empty(), "Settings, discoveries, phase, seen patterns and official records round trip")
	_check(not FileAccess.file_exists(path + ".tmp"), "Successful save does not leave a pending temporary file")
	var second := first.duplicate(true)
	second.highest_phase = 4
	second.discovered_weapons.append("W02")
	_check(Store.save_profile(path, second) == OK, "Atomic replacement succeeds when main already exists")
	_check(Store.load_profile(path).profile.highest_phase == 4, "Replacement exposes the complete new profile")
	_check(Store.load_profile(path + ".bak").profile.highest_phase == 2, "Backup retains the previous complete normal profile")
	_check(Store.save_profile(path, _profile(5)) == OK and Store.load_profile(path + ".bak").profile.highest_phase == 4, "Repeated save atomically rotates the latest normal profile into backup")
	_write(path + ".tmp", "{truncated pending write")
	loaded = Store.load_profile(path)
	_check(loaded.profile.highest_phase == 5 and loaded.error.is_empty(), "An interrupted temporary write never supersedes the valid main profile")
	var malformed := _profile()
	malformed.discovered_weapons = ["W99", "W02"]
	_check(Store.save_profile(_path("canonical.json"), malformed) == OK and Store.load_profile(_path("canonical.json")).error.is_empty(), "Repaired save data is written canonically without repeated repair notices")
	var unsupported := _profile()
	unsupported.schema = 2
	var before := _text(path)
	_check(Store.save_profile(path, unsupported) == ERR_INVALID_DATA and _text(path) == before, "Unsupported save schema is refused without damaging the valid profile")


func _test_corruption_and_backup_recovery() -> void:
	var path := _path("recovery.json")
	Store.save_profile(path, _profile(3))
	Store.save_profile(path, _profile(4))
	var backup_before := _text(path + ".bak")
	_write(path, "{broken")
	var loaded := Store.load_profile(path)
	_check(loaded.profile.highest_phase == 3 and not loaded.error.is_empty(), "Corrupted main restores the last normal backup with a short notice")
	_check(Store.save_profile(path, loaded.profile) == OK, "Recovered profile can be saved as a new valid main")
	_check(_text(path + ".bak") == backup_before, "Saving after corrupt-main recovery never replaces the only valid backup with corrupt data")
	_check(Store.load_profile(path).profile.highest_phase == 3 and Store.load_profile(path).error.is_empty(), "Subsequent launch reads the recovered complete main")
	_write(path, JSON.stringify({"schema": 99, "highest_phase": 5}))
	loaded = Store.load_profile(path)
	_check(loaded.profile.highest_phase == 3 and not loaded.error.is_empty(), "Unsupported future main schema falls back to the known valid backup")
	_write(path + ".bak", "[]")
	loaded = Store.load_profile(path)
	_check(loaded.profile == Store.defaults() and not loaded.error.is_empty(), "Corrupted main and backup recover safely to defaults")
	_write(path, JSON.stringify(_profile(5)))
	_check(Store.save_profile(path, _profile(4)) == OK, "A valid main can replace a corrupted backup on the next save")
	_check(Store.load_profile(path + ".bak").profile.highest_phase == 5, "Rotated backup after corruption is independently valid")
	var repaired := _profile(2)
	repaired.discovered_weapons = ["W01", "bogus", "W04"]
	_write(path, JSON.stringify(repaired))
	loaded = Store.load_profile(path)
	_check(loaded.profile.highest_phase == 2 and loaded.profile.discovered_weapons == ["W01", "W04"] and not loaded.error.is_empty(), "Recoverable unknown IDs are repaired without discarding valid current progression")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	loaded = Store.load_profile(path)
	_check(loaded.profile.highest_phase == 5 and not loaded.error.is_empty(), "Missing main also recovers from a valid backup")


func _test_write_failures() -> void:
	var path := _path("failures.json")
	Store.save_profile(path, _profile(2))
	Store.save_profile(path, _profile(3))
	var main_before := _text(path)
	var backup_before := _text(path + ".bak")
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_absolute(absolute + ".tmp")
	_check(Store.save_profile(path, _profile(4)) != OK, "Temporary-file open failure is surfaced to the caller")
	_check(_text(path) == main_before and _text(path + ".bak") == backup_before, "Temporary-file failure preserves both valid saved copies")
	DirAccess.remove_absolute(absolute + ".tmp")
	DirAccess.make_dir_absolute(absolute + ".bak.tmp")
	_check(Store.save_profile(path, _profile(4)) != OK, "Backup temporary-file write failure is surfaced")
	_check(_text(path) == main_before and _text(path + ".bak") == backup_before, "Backup temporary-file failure preserves main and prior backup")
	_check(not FileAccess.file_exists(path + ".tmp"), "Backup failure cleans the verified but uncommitted temporary main")
	DirAccess.remove_absolute(absolute + ".bak.tmp")
	DirAccess.remove_absolute(absolute + ".bak")
	DirAccess.make_dir_absolute(absolute + ".bak")
	_check(Store.save_profile(path, _profile(4)) != OK, "Backup replacement failure is surfaced without deleting main")
	_check(_text(path) == main_before and Store.load_profile(path).profile.highest_phase == 3, "Failed backup replacement leaves last complete main readable")
	DirAccess.remove_absolute(absolute + ".bak")
	var directory_path := _path("directory_target")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory_path))
	_check(Store.save_profile(directory_path, _profile(5)) != OK, "A directory in place of the main file is a safe save error")
	var loaded := Store.load_profile(directory_path)
	_check(loaded.profile == Store.defaults() and not loaded.error.is_empty(), "An unreadable directory target does not masquerade as a fresh valid profile")
	_check(Store.save_profile(path, _profile(4)) == OK and Store.load_profile(path).profile.highest_phase == 4, "A later healthy save succeeds after the filesystem problem is removed")


func _test_legacy_migration() -> void:
	var legacy := _path("m3_practice.json")
	var path := _path("migrated.json")
	_write(legacy, JSON.stringify({"schema": 1, "max_phase": 4}))
	var loaded := Store.load_profile(path, legacy)
	_check(loaded.profile.highest_phase == 4 and loaded.profile.discovered_weapons == ["W01"] and loaded.error.is_empty(), "Legacy M3 migration preserves official phase reach without inventing weapon discoveries")
	_check(FileAccess.file_exists(path) and Store.load_profile(path).profile.highest_phase == 4, "Legacy migration writes the new schema immediately")
	_write(legacy, JSON.stringify({"schema": 1, "max_phase": 5}))
	loaded = Store.load_profile(path, legacy)
	_check(loaded.profile.highest_phase == 4, "Existing new profile never reimports later or stale legacy progression")
	_write(path, "{bad")
	loaded = Store.load_profile(path, legacy)
	_check(loaded.profile.highest_phase == 1 and not loaded.error.is_empty(), "A damaged existing new profile does not silently reload old M3 progression")
	for data in [{"schema": 2, "max_phase": 5}, {"schema": 1, "max_phase": true}, {"schema": 1, "max_phase": "5"}, {"schema": 1, "max_phase": 2.5}]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_write(legacy, JSON.stringify(data))
		loaded = Store.load_profile(path, legacy)
		_check(loaded.profile.highest_phase == 1 and not loaded.error.is_empty() and not FileAccess.file_exists(path), "Invalid legacy schema or numeric value cannot grant unlocks: %s" % str(data))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy))
	loaded = Store.load_profile(path, legacy)
	_check(loaded.profile == Store.defaults() and loaded.error.is_empty(), "Missing new and legacy files produce a normal first launch")


func _cleanup(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir():
			_cleanup(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
