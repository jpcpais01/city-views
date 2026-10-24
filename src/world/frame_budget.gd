class_name FrameBudget
extends RefCounted
## One time budget a frame shared by all the background work (the ground
## redrawing, the town laying lots and raising houses, woods, yards, streets,
## landmark searches), so however much is going on at once the frame stays
## smooth: each takes its own slice, but never more than what is left.

## microseconds of background work a frame, in all
const TOTAL := 8000
## what each still gets when the frame's budget is spent, so nothing stalls
const FLOOR := 300

static var _frame := -1
static var _start := 0


## How long (microseconds, from now) work wanting `own` may run this frame.
static func cap(own: int) -> int:
	var now := Time.get_ticks_usec()
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_start = now
	return mini(own, maxi(TOTAL - (now - _start), FLOOR))
