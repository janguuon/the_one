extends SceneTree
## Fixed-policy comparison across weapons, seeds, and pickup choices.
## This models 60 FPS hitstop in wall_seconds; it is not a human playtest.
const Combat = preload("res://scripts/combat_model.gd")
const Policy = preload("res://tests/m3_playthrough.gd")
var output_path = "res://.tools/runtime-data/balance/final.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var seeds = [1,2,7]
	var weapons = ["W01","W02","W03","W04","W05"]
	var ignore_pickups = false
	var limit_seconds = 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = []
			for value in arg.trim_prefix("--seeds=").split(","):
				seeds.append(int(value))
		elif arg.begins_with("--weapon="):
			weapons = [arg.trim_prefix("--weapon=")]
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
		elif arg == "--no-pickups":
			ignore_pickups = true
		elif arg.begins_with("--max-seconds="):
			limit_seconds = float(arg.trim_prefix("--max-seconds="))
	var rows: Array[Dictionary] = []
	var failed = false
	for weapon_id in weapons:
		for seed_value in seeds:
			var game = Combat.new()
			game.reset(seed_value,"official",1,weapon_id)
			var wall_seconds = 0.0
			var hitstop_seconds = 0.0
			var guard_seconds = 0.0
			var hit_actions: Dictionary = {}
			var hits = 0
			var opportunities = 0
			var element_uses: Dictionary = {}
			var by_pattern: Dictionary = {}
			for iteration in range(200000):
				if game.result != "":
					break
				# Disable seeking without removing floor drops or changing resources.
				# The no-pickup run must finish without incidental collection too.
				if game.selection_pending:
					game.choose_oath("")
					continue
				var command: Dictionary = Policy.decide(game, not ignore_pickups)
				game.step(command)
				wall_seconds += 1.0 / 60.0
				guard_seconds = maxf(0.0, guard_seconds - 1.0 / 60.0)
				for event in game.events:
					if event.type == "boss_hit":
						hit_actions[event.action_id] = true
						by_pattern[game.boss_pattern] = float(by_pattern.get(game.boss_pattern,0)) + float(event.damage)
					elif event.type == "player_hit":
						hits += 1
					elif event.type == "opening":
						opportunities += 1
					elif event.type == "attack" and str(event.element) != "":
						element_uses[event.element] = int(element_uses.get(event.element,0)) + 1
				if game.result == "" and game.hitstop_ms > 0 and guard_seconds <= 0.0:
					var frozen = maxf(0.0,float(ceili((game.hitstop_ms - 0.5) * 0.06)) / 60.0)
					wall_seconds += frozen
					hitstop_seconds += frozen
					guard_seconds = maxf(0.0, 0.1 - frozen)
			var row = {"weapon":weapon_id,"seed":seed_value,"pickups":not ignore_pickups,"result":game.result,"ticks":game.tick,"seconds":snappedf(wall_seconds,0.001),"hitstop_seconds":snappedf(hitstop_seconds,0.001),"hp":game.player_hp,"damage":snappedf(game.damage_dealt,0.001),"damage_received":game.damage_received,"hits":hits,"attacks":game.total_attacks,"landed_actions":hit_actions.size(),"openings":opportunities,"element_uses":element_uses,"collected":game.collected_elements,"pattern_count":game.pattern_history.size(),"damage_by_pattern":by_pattern}
			rows.append(row)
			print("BALANCE ",JSON.stringify(row))
			if game.result != "victory" or absf(game.damage_dealt - 6000.0) > 0.002 or (limit_seconds > 0.0 and wall_seconds > limit_seconds) or (ignore_pickups and not game.collected_elements.is_empty()):
				failed = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	var file = FileAccess.open(output_path,FileAccess.WRITE)
	if file == null:
		push_error("Could not write balance report")
		quit(1)
		return
	file.store_string(JSON.stringify({"version":Combat.new().data.version,"clock":"60 FPS modeled wall time including hitstop; menu time excluded","rows":rows},"\t"))
	file.close()
	print("BALANCE_REPORT ",output_path," runs=",rows.size()," failures=",failed)
	quit(1 if failed else 0)
