extends Node
## Entry point: shows the loader, then builds the island and the interface over it.


func _ready() -> void:
	var loader := LoadingScreen.new()
	add_child(loader)
	# let the loader paint before the heavy world build blocks a frame
	await get_tree().process_frame
	await get_tree().process_frame
	var island := IslandWorld.new()
	add_child(island)
	var hud := Hud.new()
	hud.island = island
	add_child(hud)
	AdvisorBot.attach(hud, island)
	CityCharts.attach(hud, island)
	loader.set_progress(0.3)
	loader.track(island)
	move_child(loader, -1)
