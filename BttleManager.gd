extends Node

class_name BattleHandler

const BATTLE_STAGE_PATH = "res://battlestage.tscn"

func start_battle(character_id: String, enemy_id: String) -> void:
	get_tree().change_scene_to_file("res://battlestage.tscn")
	#var battle_scene = load(BATTLE_STAGE_PATH)
	#if not battle_scene:
		#push_error("failed to load!")
		#return
		#
	#var battle_instance = battle_scene.instantiate()
	#
	#get_tree().root.add_child(battle_instance)
	#
	#if battle_ins tance.has_method("setup_battle"):
		#battle_instance.setup_battle(character_id, enemy_id)
	#scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	#tree.current_scene.visible = true
	#return
#scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	##tree.current_scene.visible = true
	#return
#
#scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	#tree.current_scene.visible = true
	#return
#scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	#tree.current_scene.visible = true
	return
