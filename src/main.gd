extends Node
## Entry point: builds the 3D world and the interface.

func _ready() -> void:
	var world := World.new()
	add_child(world)
	var hud := Hud.new()
	hud.world = world
	add_child(hud)
