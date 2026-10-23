extends Node
## Entry point: shows the loader, then builds the 3D world and the interface behind it.

func _ready() -> void:
	var loader := LoadingScreen.new()
	add_child(loader)
	# let the loader paint before the heavy world build blocks a frame
	await get_tree().process_frame
	await get_tree().process_frame
	var world := World.new()
	add_child(world)
	loader.set_progress(0.22)
	await get_tree().process_frame
	var hud := Hud.new()
	hud.world = world
	add_child(hud)
	loader.set_progress(0.3)
	loader.track(world)
	move_child(loader, -1)
