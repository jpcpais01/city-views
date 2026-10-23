extends Node
## Entry point: shows the loader, then builds the 3D world and the interface behind it.
## Two worlds for now: the new tile-free island, where the game opens, and the classic tile town.

var _world: Node
var _hud: Node


func _ready() -> void:
	var loader := LoadingScreen.new()
	add_child(loader)
	# let the loader paint before the heavy world build blocks a frame
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.get_environment("CV_TOWN") != "":
		_open_town()
	else:
		_open_island()
	loader.set_progress(0.3)
	loader.track(_world)
	move_child(loader, -1)


func _clear() -> void:
	for n in [_hud, _world]:
		if n:
			remove_child(n)
			n.queue_free()


func _open_town() -> void:
	_clear()
	var world := World.new()
	add_child(world)
	var hud := Hud.new()
	hud.world = world
	add_child(hud)
	hud.open_island.connect(func(): _switch(_open_island))
	_world = world
	_hud = hud


func _open_island() -> void:
	_clear()
	var island := IslandWorld.new()
	add_child(island)
	var hud := IslandHud.new()
	hud.world = island
	hud.island = island
	add_child(hud)
	hud.back_to_town.connect(func(): _switch(_open_town))
	_world = island
	_hud = hud


## Swap worlds behind a quick fade so the rebuild frame doesn't show.
func _switch(open: Callable) -> void:
	var fade := ColorRect.new()
	fade.color = Color(0.93, 0.96, 1.0, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(fade)
	add_child(layer)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.25)
	await tw.finished
	await get_tree().process_frame
	open.call()
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.4)
	await tw2.finished
	layer.queue_free()
