extends SceneTree
## Contrasts readable-pattern policy with non-reactive input, not human skill.
const Combat = preload("res://scripts/combat_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rows: Array[Dictionary] = []
	var failures = 0
	for weapon in ["W01","W02","W03","W04","W05"]:
		for seed_value in [1,7]:
			for policy in ["idle","greedy_early_dodge"]:
				var game = Combat.new()
				game.reset(seed_value,"official",1,weapon)
				var hits: Array[Dictionary] = []
				for index in range(9000):
					if game.result != "":
						break
					var command: Dictionary = {}
					if policy != "idle":
						var difference: Vector2 = game.boss_pos - game.player_pos
						var distance: float = difference.length()
						var desired = 40.0 if weapon != "W05" else 50.0
						var movement = difference.normalized() if distance > desired else Vector2.ZERO
						command = {"move":movement,"attack":distance <= float(game.weapon_definition().reach) + 20.0 and game.player_state in ["idle","move"],"dodge":game.boss_state == "telegraph" and game.boss_age == 5}
					game.step(command)
					for event in game.events:
						if event.type == "player_hit":
							hits.append({"tick":game.tick,"pattern":game.boss_pattern,"cause":event.cause,"damage":event.damage})
				var row = {"weapon":weapon,"seed":seed_value,"policy":policy,"result":game.result,"phase":game.phase_id,"ticks":game.tick,"hp":game.player_hp,"damage":game.damage_dealt,"hits":hits}
				rows.append(row)
				print("DIFFICULTY ",JSON.stringify(row))
				if game.result != "dead" or hits.size() < 3 or hits.size() > 5:
					failures += 1
	var path = "res://.tools/runtime-data/balance/difficulty.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"interpretation":"Non-reactive policies must fail; this does not measure human learning or fun."},"\t"))
	file.close()
	print("DIFFICULTY METRICS: ",rows.size()," runs, ",failures," failures")
	quit(0 if failures == 0 else 1)
