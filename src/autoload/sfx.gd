extends Node
## All sounds are synthesised at startup: no audio files needed.
## Includes a gentle generative music-box soundtrack and ocean/bird ambience.

const RATE := 22050

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _music_player: Array[AudioStreamPlayer] = []
var _ambience: AudioStreamPlayer
var _beat := 0.0
var _step := 0
var _chord := 0
var _bird_timer := 4.0
var night := 0.0

const SCALE := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
const CHORDS := [[0, 4, 7], [-3, 0, 4], [-7, -3, 0], [-5, -1, 2]]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams["pop"] = _make(0.16, func(t: float) -> float:
		var f := 520.0 + 900.0 * t
		return sin(TAU * f * t) * exp(-t * 26.0) * 0.8)
	_streams["place"] = _make(0.22, func(t: float) -> float:
		return (sin(TAU * 196.0 * t) * 0.6 + sin(TAU * 392.0 * t) * 0.3 + sin(TAU * 784.0 * t) * 0.12) * exp(-t * 18.0))
	_streams["road"] = _make(0.12, func(t: float) -> float:
		return (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.35 + sin(TAU * 110.0 * t) * exp(-t * 30.0) * 0.5)
	_streams["coin"] = _make(0.4, func(t: float) -> float:
		var f := 1318.5 if t < 0.07 else 1975.5
		return (sin(TAU * f * t) + sin(TAU * f * 2.0 * t) * 0.25) * exp(-t * 9.0) * 0.45)
	_streams["unlock"] = _make(1.2, func(t: float) -> float:
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var s := 0.0
		for i in 4:
			var st := t - i * 0.11
			if st > 0.0:
				s += (sin(TAU * notes[i] * st) + sin(TAU * notes[i] * 2.0 * st) * 0.2) * exp(-st * 4.0)
		return s * 0.3)
	_streams["bulldoze"] = _make(0.4, func(t: float) -> float:
		return (randf() * 2.0 - 1.0) * exp(-t * 9.0) * 0.4 * (0.6 + 0.4 * sin(TAU * 30.0 * t)))
	_streams["click"] = _make(0.05, func(t: float) -> float:
		return sin(TAU * 1600.0 * t) * exp(-t * 120.0) * 0.5)
	_streams["grow"] = _make(0.5, func(t: float) -> float:
		var f := 660.0 + 300.0 * t
		return (sin(TAU * f * t) * 0.5 + sin(TAU * f * 1.5 * t) * 0.25) * exp(-t * 7.0) * 0.35)
	_streams["bell"] = _make(2.2, func(t: float) -> float:
		var f := 523.25
		return (sin(TAU * f * t) + sin(TAU * f * 2.0 * t) * 0.3 + sin(TAU * f * 3.01 * t) * 0.12) * exp(-t * 2.2) * 0.32)
	_streams["pad"] = _make(3.0, func(t: float) -> float:
		var f := 261.63
		var env: float = min(t * 2.0, 1.0) * exp(-t * 0.9)
		return (sin(TAU * f * t) + sin(TAU * f * 1.003 * t) * 0.8 + sin(TAU * f * 2.0 * t) * 0.15) * env * 0.12)
	_streams["bird"] = _make(0.35, func(t: float) -> float:
		var f := 2600.0 + 900.0 * sin(t * 60.0)
		var env := sin(PI * clampf(t / 0.35, 0.0, 1.0))
		return sin(TAU * f * t) * env * 0.12 * (0.5 + 0.5 * sin(t * 90.0)))
	# herring gull "kee-ow": a nasal, falling cry with a throaty wobble
	_streams["gull"] = _make(0.6, func(t: float) -> float:
		var ph := TAU * (1750.0 * t - 750.0 * t * t)
		var env := minf(t / 0.03, 1.0) * (1.0 - smoothstep(0.32, 0.58, t))
		var s := sin(ph) + 0.6 * sin(2.0 * ph) + 0.35 * sin(3.0 * ph) + 0.15 * sin(4.0 * ph)
		return s * env * (0.75 + 0.25 * sin(TAU * 28.0 * t)) * 0.11)
	_streams["ocean"] = _make_ocean()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 6:
		var m := AudioStreamPlayer.new()
		m.volume_db = -12.0
		add_child(m)
		_music_player.append(m)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _streams["ocean"]
	_ambience.volume_db = -16.0
	add_child(_ambience)
	_ambience.play()


func _make(length: float, f: Callable) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var fade: float = min(1.0, float(n - i) / 200.0)
		var v := clampf(f.call(t) * fade, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


func _make_ocean() -> AudioStreamWAV:
	var length := 6.0
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.06
		lp2 += (lp - lp2) * 0.08
		var swell := 0.55 + 0.45 * sin(TAU * t / length * 2.0) * sin(TAU * t / length)
		var v := lp2 * 2.2 * swell
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s


func play(sound: String, pitch := 1.0, vol_db := 0.0, vary := 0.08) -> void:
	if not Game.settings.get("sfx", true) or not _streams.has(sound):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[sound]
			p.pitch_scale = pitch * (1.0 + randf_range(-vary, vary))
			p.volume_db = vol_db
			p.play()
			return


func _process(delta: float) -> void:
	_ambience.stream_paused = not Game.settings.get("sfx", true)
	if not Game.settings.get("music", true):
		return
	var tempo := lerpf(0.42, 0.6, night)
	_beat += delta
	if _beat < tempo:
		_bird_logic(delta)
		return
	_beat = 0.0
	_step += 1
	if _step % 16 == 0:
		_chord = (_chord + 1) % CHORDS.size()
		for semi in CHORDS[_chord]:
			_music("pad", pow(2.0, (semi - 12) / 12.0), -14.0)
	var density := lerpf(0.42, 0.25, night)
	if randf() < density:
		var root: int = CHORDS[_chord][0]
		var semi: int = SCALE[randi() % SCALE.size()] + root
		if night > 0.5:
			semi -= 5
		_music("bell", pow(2.0, semi / 12.0), randf_range(-16.0, -10.0))


## A gull's cry, sometimes a laughing run of them; `near` 0..1 sets the loudness.
func gull(near: float) -> void:
	if night > 0.7:
		return
	var vol := lerpf(-24.0, -9.0, clampf(near, 0.0, 1.0))
	var pitch := randf_range(0.9, 1.15)
	var times := 1 if randf() < 0.6 else randi_range(2, 4)
	for i in times:
		var step := pitch * (1.0 - i * 0.04)
		get_tree().create_timer(i * 0.3).timeout.connect(func(): play("gull", step, vol - i * 1.5, 0.02))


func _bird_logic(delta: float) -> void:
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = randf_range(3.0, 9.0)
		if night < 0.4 and Game.settings.get("sfx", true):
			var times := randi_range(1, 3)
			for i in times:
				get_tree().create_timer(i * 0.18).timeout.connect(func(): play("bird", randf_range(0.85, 1.2), -14.0, 0.0))


func _music(sound: String, pitch: float, vol: float) -> void:
	for p in _music_player:
		if not p.playing:
			p.stream = _streams[sound]
			p.pitch_scale = pitch
			p.volume_db = vol
			p.play()
			return
