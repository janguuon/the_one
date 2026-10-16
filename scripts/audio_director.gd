extends Node
## Presentation-only audio. All attack cues read the real 60 Hz timeline.
## Music uses five original cyclic arrangements, with a sparse P5 finale.
const ROOT := "res://assets/audio/"
const MAX_VOICES := 8
const SFX_DB := -18.0
const WARNING_DB := -15.0
const MUSIC_DB := -14.0
const SILENCE_DB := -80.0
signal shutdown_finished

var settings: Dictionary = {"master_volume": 0.8, "music_volume": 0.65, "sfx_volume": 0.85, "music_muted": false, "sfx_muted": false}
var suspended := false
# A headless timing harness may inspect issued cues without scheduling several
# minutes of real audio playback in one CPU frame. Native play keeps this true.
var playback_enabled := true
var cue_log: Array[Dictionary] = []
var dropped_nonessential := 0
var played_counts: Dictionary = {}
var phase := 1
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_weights: Array[float] = [1.0, 0.0, 0.0, 0.0, 0.0]
var _seen: Dictionary = {}
var _last_tick := -1
var _voice_serial := 0
var _shutting_down := false
var _shutdown_complete := false


func _ready() -> void:
	_ensure_players()


func _exit_tree() -> void:
	# Release active playback before the scene/resources disappear, including
	# rapid menu tests and returning to the project launcher.
	for player in _voices + _music:
		if is_instance_valid(player):
			player.stream_paused = false
			player.stop()
			player.stream = null
	_streams.clear()


func shutdown() -> void:
	if _shutdown_complete:
		return
	if _shutting_down:
		await shutdown_finished
		return
	_shutting_down = true
	# stop() schedules a fade/deletion on the audio thread. The resulting
	# playback references are released by AudioServer.update on the MAIN loop.
	# Blocking OS.sleep followed by quit cannot perform that final cleanup.
	for player in _voices + _music:
		player.volume_db = SILENCE_DB
		player.stream_paused = false
		player.stop()
	if is_inside_tree():
		var tree := get_tree()
		var drain_seconds := clampf(AudioServer.get_output_latency() * 3.0 + 0.08, 0.1, 0.5)
		await tree.create_timer(drain_seconds, true, false, true).timeout
		await tree.process_frame
		await tree.process_frame
	for player in _voices + _music:
		player.stream = null
	_streams.clear()
	_shutdown_complete = true
	shutdown_finished.emit()


func _ensure_players() -> void:
	if not _voices.is_empty():
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	for id in manifest.assets:
		_streams[id] = load(ROOT + str(manifest.assets[id].file))
	for index in range(MAX_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.set_meta("essential", false)
		voice.set_meta("combat_bound", true)
		voice.set_meta("serial", 0)
		add_child(voice)
		_voices.append(voice)
	for index in range(5):
		var player := AudioStreamPlayer.new()
		var stream: AudioStreamWAV = _streams["phase_%d" % (index + 1)]
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		player.stream = stream
		player.volume_db = SILENCE_DB
		add_child(player)
		_music.append(player)


func configure(value: Dictionary) -> void:
	for key in ["master_volume", "music_volume", "sfx_volume"]:
		if value.get(key) is float or value.get(key) is int:
			settings[key] = clampf(float(value[key]), 0.0, 1.0)
	for key in ["music_muted", "sfx_muted"]:
		if value.get(key) is bool:
			settings[key] = value[key]
	_apply_volumes()


func start_run(_mode: String, start_phase: int) -> void:
	if _shutting_down:
		return
	_ensure_players()
	phase = clampi(start_phase, 1, 5)
	_seen.clear()
	_last_tick = -1
	for voice in _voices:
		voice.stop()
	for index in range(5):
		_music_weights[index] = 1.0 if index == phase - 1 else 0.0
		if playback_enabled:
			_music[index].play(0.0)
	_apply_volumes()


func set_suspended(value: bool) -> void:
	suspended = value
	for player in _music:
		player.stream_paused = value
	for voice in _voices:
		voice.stream_paused = value and bool(voice.get_meta("combat_bound", true))


func update(model, screen: String, delta: float) -> void:
	if _shutting_down:
		return
	_ensure_players()
	phase = clampi(int(model.phase_id), 1, 5)
	# Menus may keep a low drone, but all combat-bound playback freezes with
	# pause, oath selection and hitstop. Never advance cue age with wall time.
	if not suspended:
		var target := phase - 1 if screen in ["playing", "result", "oaths", "paused"] else 0
		var blend := 1.0 - exp(-maxf(0.0, delta) * 3.0)
		for index in range(5):
			_music_weights[index] = lerpf(_music_weights[index], 1.0 if index == target else 0.0, blend)
			if playback_enabled and not _music[index].playing:
				_music[index].play()
	_apply_volumes()
	if suspended or screen != "playing" or int(model.tick) == _last_tick:
		return
	_last_tick = int(model.tick)
	_prune_history(_last_tick)
	_observe_attack(model)
	_observe_hazards(model)


func _observe_attack(model) -> void:
	if str(model.player_state) != "attack" or model.attack.is_empty():
		return
	var attack: Dictionary = model.attack
	var windows: Array = attack.definition.hit_windows
	for index in range(windows.size()):
		if int(model.state_age) < int(windows[index][0]) or int(model.state_age) >= int(windows[index][1]):
			continue
		var key := "swing:%s:%d" % [str(attack.id), index]
		if not _seen.has(key):
			_seen[key] = int(model.tick)
			_play("attack_" + str(attack.weapon), false, int(model.tick))


func _observe_hazards(model) -> void:
	var definition: Dictionary = model.pattern_runner.get_definition(str(model.boss_pattern))
	var pattern_start := int(model.tick) - int(model.boss_age)
	for hazard in model.hazards:
		var key := "%d:%s" % [pattern_start, str(hazard.event_id)]
		var preview := key + ":preview"
		if not _seen.has(preview):
			_seen[preview] = int(model.tick)
			_play("warning_preview", true, int(model.tick), true)
		var lock_age := _lock_age(str(model.boss_pattern), definition, hazard)
		var lock_key := key + ":lock"
		# Static geometry is already fixed at preview; its one high preview
		# chime is sufficient. Tracking aim gets a distinct locking click.
		if lock_age > int(hazard.preview_tick) and int(model.boss_age) >= lock_age and int(model.boss_age) < int(hazard.start_tick) and not _seen.has(lock_key):
			_seen[lock_key] = int(model.tick)
			_play("warning_lock", true, int(model.tick), true)


func _lock_age(pattern: String, definition: Dictionary, hazard: Dictionary) -> int:
	var number := int(hazard.get("number", 1))
	if pattern in ["heartbeat", "execution"]:
		if number == 4:
			return int(definition.get("line_lock", 0))
		if number == 3:
			return int(definition.get("last_lock", 0))
	if pattern == "nameless_end" and number == 3:
		return int(definition.get("line_lock", 0))
	return int(definition.get("lock_tick", hazard.preview_tick))


func consume_events(events: Array, model) -> void:
	_ensure_players()
	# The scene consumes events immediately after the actual simulation step,
	# before it starts this hit's real-time hitstop. Observe that step here so
	# a hit on the first active frame cannot delay its swing/lock cue until
	# after hitstop. update() remains useful for callers without an event loop.
	if int(model.tick) != _last_tick:
		_last_tick = int(model.tick)
		_prune_history(_last_tick)
		_observe_attack(model)
		_observe_hazards(model)
	for event in events:
		var type := str(event.get("type", ""))
		var tick := int(model.tick)
		match type:
			"boss_hit": _play("hit_" + str(event.get("weapon", "W01")), false, tick)
			"dodge": _play("dodge", false, tick)
			"player_hit": _play("hurt", false, tick)
			"pickup": _play("pickup_" + str(event.get("element", "fire")), false, tick)
			"boss_attack":
				var echo := str(event.get("event_id", "")) in ["echo_2", "nameless_end_2"]
				_play("warning_echo" if echo else "warning_execute", true, tick, true)
			"phase_transition": _play("transition", false, tick)
			"weapon_swap": _play("weapon_swap", false, tick)
			"oath_selected": _play("oath", false, tick, false, false)
			"result":
				var result := str(event.get("result", ""))
				if result in ["victory", "practice_complete", "prototype_complete"]:
					_play("victory", false, tick)
				elif result == "dead":
					_play("death", false, tick)


func menu_action(confirm: bool = false) -> void:
	_ensure_players()
	_play("menu_confirm" if confirm else "menu_move", false, -1, false, false)


func _play(id: String, essential: bool, tick: int, coalesce: bool = false, combat_bound: bool = true) -> void:
	if _shutting_down:
		return
	if not _streams.has(id):
		return
	var key := "cue:%s:%d" % [id, tick]
	if coalesce and _seen.has(key):
		return
	if coalesce:
		_seen[key] = tick
	# Muting is a user choice; reduced visual effects never mutes warnings.
	if bool(settings.sfx_muted) or float(settings.sfx_volume) <= 0.0 or float(settings.master_volume) <= 0.0:
		return
	var selected: AudioStreamPlayer
	for voice in _voices:
		if not voice.playing:
			selected = voice
			break
	if selected == null:
		for voice in _voices:
			if not bool(voice.get_meta("essential")) and (selected == null or int(voice.get_meta("serial")) < int(selected.get_meta("serial"))):
				selected = voice
	if selected == null:
		if not essential:
			dropped_nonessential += 1
			return
		# Warning bursts coalesce per tick; this is only a pathological fallback.
		selected = _voices[0]
	selected.stop()
	_voice_serial += 1
	selected.set_meta("essential", essential)
	selected.set_meta("combat_bound", combat_bound)
	selected.set_meta("serial", _voice_serial)
	selected.stream = _streams[id]
	selected.volume_db = _gain_db(float(settings.master_volume) * float(settings.sfx_volume), WARNING_DB if essential else SFX_DB)
	if playback_enabled:
		selected.play()
	selected.stream_paused = suspended and combat_bound
	played_counts[id] = int(played_counts.get(id, 0)) + 1
	cue_log.append({"id": id, "tick": tick, "essential": essential})
	if cue_log.size() > 256:
		cue_log.pop_front()


func _apply_volumes() -> void:
	for index in range(_music.size()):
		var gain := float(settings.master_volume) * float(settings.music_volume) * _music_weights[index]
		_music[index].volume_db = SILENCE_DB if bool(settings.music_muted) else _gain_db(gain, MUSIC_DB)
	for voice in _voices:
		var base := WARNING_DB if bool(voice.get_meta("essential")) else SFX_DB
		voice.volume_db = SILENCE_DB if bool(settings.sfx_muted) else _gain_db(float(settings.master_volume) * float(settings.sfx_volume), base)


func _gain_db(gain: float, base: float) -> float:
	return maxf(SILENCE_DB, linear_to_db(clampf(gain, 0.000001, 1.0)) + base)


func _prune_history(tick: int) -> void:
	if _seen.size() <= 1200:
		return
	# Every pattern is shorter than ten combat seconds. Keep the full active
	# pattern's keys; dropping only old keys cannot replay its current preview.
	for key in _seen.keys():
		if int(_seen[key]) < tick - 600:
			_seen.erase(key)
