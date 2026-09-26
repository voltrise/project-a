extends Node

var BM = BattleManagerClass.new()
var CMC = CharacterManagerClass.new()
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#get_tree().change_scene_to_file("res://battlestage.tscn")
	var bocchi = CMC.get_character_by_id("bocchi")
	#BM.start_battle(self, bocchi, BattleManagerClass.ENEMY_PRESETS.skeleton_knight, "res://Overworld.tscn")
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
