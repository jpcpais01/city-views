class_name FrameBudget
extends RefCounted
## One time budget a frame shared by all the background work (the ground
## redrawing, the town laying lots and raising houses, woods, yards, streets,
## landmark searches), so however much is going on at once the frame stays
## smooth: each takes its own slice, but never more than what is left.

## microseconds of background work a frame, in all, while frames keep up
const TOTAL := 8000
## the least it shrinks to when frames run long (see cap)
const LEAST := 3000
## what each still gets when the frame's budget is spent, so nothing stalls
const FLOOR := 300

static var _frame := -1
static var _start := 0
# how long frames have been taking lately (microseconds), and this frame's budget
static var _ft := 16667.0
static var _total := TOTAL


## How long (microseconds, from now) work wanting `own` may run this frame.
static func cap(own: int) -> int:
	var now := Time.get_ticks_usec()
	var f := Engine.get_process_frames()
	if f != _frame:
		if _frame >= 0 and f == _frame + 1:
			_ft = lerpf(_ft, clampf(now - _start, 1000.0, 100000.0), 0.1)
		_frame = f
		_start = now
		# frames running long (a slower phone, a big town in view) leave less
		# for the background, so what the player is doing stays smooth
		_total = clampi(int(TOTAL * minf(1.0, 18000.0 / _ft)), LEAST, TOTAL)
	return mini(own, maxi(_total - (now - _start), FLOOR))
