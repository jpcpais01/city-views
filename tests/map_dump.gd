extends Node
func _ready():
	for s in [1234, 7, 555]:
		Game.new_world(s)
		var hist := [0,0,0,0,0,0,0]
		for i in Game.level.size(): hist[Game.level[i]] += 1
		print(s, " ", hist)
		if s == 1234:
			for z in range(0, Game.N, 2):
				var line := ""
				for x in Game.N:
					var k := Game.knd(x, z)
					line += "T" if k == Game.K.TREE else str(Game.lvl(x, z)).replace("0", ".")
				print(line)
	get_tree().quit()
