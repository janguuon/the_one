extends SceneTree
## PCM content and presentation timing only; never edits combat rules.
const Director = preload("res://scripts/audio_director.gd")
const Model = preload("res://scripts/combat_model.gd")
const Patterns = preload("res://scripts/boss_patterns.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)


func _run() -> void:
	_test_assets()
	var audio := Director.new()
	# Simulated timelines run hundreds of times faster than real playback.
	# Issue/inspect cues without filling the actual device's pending mixer queue.
	# PCM resources and real scene playback are checked separately.
	audio.playback_enabled = false
	root.add_child(audio)
	var model = Model.new()
	_test_settings(audio, model)
	await _test_weapon_timing(audio, model)
	await _test_real_pattern_timelines(audio, model)
	_test_events_and_freeze(audio, model)
	await _test_shutdown(audio)
	print("Audio assertions: %d checks, %d failures; releasing mixer" % [checks, failures.size()])
	audio.queue_free()
	await process_frame
	await process_frame
	# Dummy/headless frames can finish before the real audio mixer block drains.
	await create_timer(0.08).timeout
	print("Audio tests: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_assets() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	_check(manifest.assets.size() == 32, "All five music arrangements and 27 cues exist")
	var music_hashes: Array[String] = []
	var attack_hashes: Array[String] = []
	var hit_hashes: Array[String] = []
	var pickup_hashes: Array[String] = []
	for id in manifest.assets:
		var item: Dictionary = manifest.assets[id]
		var path := "res://assets/audio/" + str(item.file)
		var file := FileAccess.open(path, FileAccess.READ)
		_check(file != null, "%s file opens" % id)
		if file == null:
			continue
		var content := file.get_buffer(file.get_length())
		_check(content.slice(0, 4).get_string_from_ascii() == "RIFF" and content.slice(8, 12).get_string_from_ascii() == "WAVE", "%s real WAV" % id)
		_check(content.decode_u16(22) == 2 and content.decode_u16(34) == 16 and content.decode_u32(24) == 22050, "%s stereo PCM16 22050Hz" % id)
		_check(content.decode_u32(40) == int(item.frames) * 4, "%s frame count equals manifest" % id)
		_check(FileAccess.get_sha256(path) == str(item.sha256), "%s reproducible asset SHA256" % id)
		var peak := 0
		for offset in range(44, content.size(), 2):
			peak = maxi(peak, absi(content.decode_s16(offset)))
		_check(peak <= 13042 and peak > 64, "%s non-silent and below −8dBFS asset ceiling" % id)
		var stream := load(path) as AudioStreamWAV
		_check(stream != null and absf(stream.get_length() - float(item.seconds)) < 0.001, "%s Godot decodes exact duration" % id)
		if bool(item.loop):
			_check(absf(float(item.seconds) - 16.0) < 0.0001, "%s eight-bar loop duration" % id)
			_check(absi(content.decode_s16(44)) <= 1 and absi(content.decode_s16(content.size() - 2)) <= 20, "%s near-zero seam" % id)
			music_hashes.append(str(item.sha256))
		elif str(id).begins_with("attack_"):
			attack_hashes.append(str(item.sha256))
		elif str(id).begins_with("hit_"):
			hit_hashes.append(str(item.sha256))
		elif str(id).begins_with("pickup_"):
			pickup_hashes.append(str(item.sha256))
	for group in [music_hashes, attack_hashes, hit_hashes, pickup_hashes]:
		var unique: Dictionary = {}
		for hash_value in group:
			unique[hash_value] = true
		_check(unique.size() == group.size(), "Every phase/weapon/element cue is a distinct waveform")
	# Eight max-gain warnings and normalized crossfading music cannot clip even
	# at all three sliders = 1.0. This bound includes worst coincident samples.
	var peak_bound := 0.3981 * (8 * db_to_linear(Director.WARNING_DB) + db_to_linear(Director.MUSIC_DB))
	_check(peak_bound < 0.7, "Worst-case enabled mixer has >3dB peak headroom")


func _test_settings(audio, model) -> void:
	audio.configure({"master_volume": 5.0, "music_volume": -2.0, "sfx_volume": 1.0, "music_muted": true})
	_check(audio.settings.master_volume == 1.0 and audio.settings.music_volume == 0.0, "Audio sliders clamp malformed ranges")
	audio.start_run("official", 3)
	audio.update(model, "title", 0.016)
	for player in audio._music:
		_check(player.volume_db <= -80.0, "Music mute silences every phase without muting SFX")
	var previous: int = int(audio.played_counts.get("dodge", 0))
	audio.consume_events([{"type":"dodge"}], model)
	_check(int(audio.played_counts.get("dodge", 0)) == previous + 1, "Music mute retains gameplay sounds")
	audio.configure({"music_muted": false, "sfx_muted": true, "music_volume": 1.0})
	previous = int(audio.played_counts.get("dodge", 0))
	audio.consume_events([{"type":"dodge"}], model)
	_check(int(audio.played_counts.get("dodge", 0)) == previous, "Independent SFX mute suppresses cues")
	audio.configure({"sfx_muted": false, "reduced_effects": true})
	audio.consume_events([{"type":"boss_attack", "event_id":"test"}], model)
	_check(int(audio.played_counts.get("warning_execute", 0)) > 0, "Reduced effects retains essential warnings")
	for player in audio._music:
		_check(player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and player.stream.loop_end == 352800, "Music loop uses the full exported PCM cycle")
	model.phase_id = 5
	for index in range(120):
		audio.update(model, "playing", 1.0 / 60.0)
	var weight_sum := 0.0
	for value in audio._music_weights:
		weight_sum += value
	_check(absf(weight_sum - 1.0) < 0.0001 and audio._music_weights[4] > 0.99, "Phase music crossfade conserves total gain")


func _test_weapon_timing(audio, model) -> void:
	for weapon in ["W01", "W02", "W03", "W04", "W05"]:
		model.reset(1, "official", 1, weapon)
		model.boss_enabled = false
		audio.start_run("official", 1)
		audio.cue_log.clear()
		for age in range(65):
			model.step({"attack": age == 0})
			audio.consume_events(model.events, model)
			if model.player_state == "attack":
				for window in model.attack.definition.hit_windows:
					if model.state_age == int(window[0]):
						_check(audio.cue_log.any(func(cue): return cue.id == "attack_" + weapon and int(cue.tick) == model.tick), "%s active cue is captured before the scene can start hitstop" % weapon)
			audio.update(model, "playing", 1.0 / 60.0)
		var swings: Array = audio.cue_log.filter(func(cue): return cue.id == "attack_" + weapon)
		var windows: Array = model.data.weapons[weapon].hit_windows
		_check(swings.size() == windows.size(), "%s has one audible swing per actual strike window" % weapon)
		for index in range(mini(swings.size(), windows.size())):
			_check(int(swings[index].tick) == 1 + int(windows[index][0]), "%s swing starts at active tick" % weapon)
		var count: int = audio.cue_log.size()
		audio.update(model, "playing", 9.0)
		_check(audio.cue_log.size() == count, "%s same combat tick does not repeat a cue" % weapon)
		await process_frame


func _test_real_pattern_timelines(audio, model) -> void:
	var runner := Patterns.new()
	for pattern in runner.definitions:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		runner.start(pattern, Vector2(320, 170), Vector2(370, 220), rng)
		_check(runner.safety_error == "", "%s valid audio timeline fixture" % pattern)
		model.reset(7, "practice", int(runner.definitions[pattern].phase))
		model.pattern_runner = runner
		model.boss_pattern = runner.actual_id
		audio.start_run("practice", model.phase_id)
		audio.cue_log.clear()
		var expected_strike_ticks: Array[int] = []
		for age in range(runner.duration + 1):
			var snapshot := runner.update(age, Vector2(370, 220))
			model.tick = 1000 + age
			model.boss_age = age
			model.hazards.assign(snapshot.hazards)
			if not snapshot.events.is_empty() and not expected_strike_ticks.has(model.tick):
				expected_strike_ticks.append(model.tick)
			audio.consume_events(snapshot.events, model)
			audio.update(model, "playing", 1.0 / 60.0)
		var actual_strike_ticks: Array[int] = []
		for cue in audio.cue_log:
			if cue.id in ["warning_execute", "warning_echo"] and not actual_strike_ticks.has(int(cue.tick)):
				actual_strike_ticks.append(int(cue.tick))
		_check(actual_strike_ticks == expected_strike_ticks, "%s execution audio follows every real damage event exactly" % pattern)
		_check(audio.cue_log.any(func(cue): return cue.id == "warning_preview"), "%s supplies preview audio" % pattern)
		if pattern in ["claw", "rupture", "thrust", "heartbeat", "echo", "execution", "nameless_end"]:
			_check(audio.cue_log.any(func(cue): return cue.id == "warning_lock"), "%s supplies a tracking-lock audio cue" % pattern)
		if pattern in ["echo", "nameless_end"]:
			_check(audio.cue_log.any(func(cue): return cue.id == "warning_echo"), "%s echo is a distinct second sound" % pattern)
		await process_frame


func _test_events_and_freeze(audio, model) -> void:
	model.reset(1, "official", 1)
	# The short lifecycle section uses real AudioStreamPlayers, so pause/mute
	# assertions cover actual scheduled playback as well as issued commands.
	audio.playback_enabled = true
	audio.start_run("official", 1)
	for element in ["fire", "frost", "lightning", "void"]:
		audio.consume_events([{"type":"pickup", "element":element}], model)
		_check(int(audio.played_counts.get("pickup_" + element, 0)) > 0, "%s pickup selects its own sonic identity" % element)
	for event in [{"type":"player_hit"}, {"type":"phase_transition"}, {"type":"weapon_swap"}, {"type":"oath_selected"}, {"type":"result", "result":"dead"}, {"type":"result", "result":"victory"}]:
		audio.consume_events([event], model)
	for id in ["hurt", "transition", "weapon_swap", "oath", "death", "victory"]:
		_check(int(audio.played_counts.get(id, 0)) > 0, "%s event selects cue" % id)
	audio.set_suspended(true)
	for player in audio._music:
		_check(player.stream_paused, "Pause/hitstop suspends each music stream")
	for voice in audio._voices:
		if bool(voice.get_meta("combat_bound", true)):
			_check(voice.stream_paused, "Pause/hitstop suspends combat-bound SFX tails")
	var before: int = audio.cue_log.size()
	var before_tick: int = audio._last_tick
	model.tick += 1
	audio.update(model, "playing", 20.0)
	_check(audio.cue_log.size() == before and audio._last_tick == before_tick, "Suspended update cannot advance timeline observation")
	audio.menu_action(true)
	_check(audio.cue_log[-1].id == "menu_confirm", "Menu confirmation remains available while battle is suspended")
	_check(audio._voices.any(func(voice): return not bool(voice.get_meta("combat_bound", true)) and not voice.stream_paused), "UI voice is separate from frozen combat tails")
	audio.set_suspended(false)
	for player in audio._music:
		_check(not player.stream_paused, "Resume unpauses music streams")
	_check(audio._voices.size() == 8, "Mixer cannot create an unbounded number of simultaneous voices")


func _test_shutdown(audio) -> void:
	# Regression: freeing immediately after a paused/new cue leaves the
	# AudioServer's deferred playback reference alive without main-loop drain.
	var stream_weak: WeakRef = weakref(audio._streams.menu_confirm)
	audio.menu_action(true)
	var playback_weak: WeakRef
	for voice in audio._voices:
		if voice.stream == stream_weak.get_ref() and voice.has_stream_playback():
			playback_weak = weakref(voice.get_stream_playback())
			break
	_check(playback_weak != null and playback_weak.get_ref() != null, "Shutdown fixture has a live real menu playback")
	audio.set_suspended(true)
	await audio.shutdown()
	_check(audio._shutdown_complete and audio._streams.is_empty(), "Shutdown drains before releasing asset references")
	_check(audio._voices.all(func(voice): return not voice.playing and voice.stream == null), "Shutdown stops every effect and clears player references")
	_check(audio._music.all(func(voice): return not voice.playing and voice.stream == null), "Shutdown stops every phase loop and clears player references")
	_check(playback_weak == null or playback_weak.get_ref() == null, "Paused/new playback is released by AudioServer before quit")
	_check(stream_weak.get_ref() == null, "No deferred menu PCM reference survives drained shutdown")
	var previous: int = audio.cue_log.size()
	audio.menu_action(true)
	_check(audio.cue_log.size() == previous, "Closing cannot schedule a fresh playback after shutdown")
	await audio.shutdown()
	_check(audio._shutdown_complete, "Repeated shutdown is safe")
