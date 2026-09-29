class_name TowerView
extends Node2D
## Shows the platforms of the current run. Uses a small pool of PlatformView nodes that are
## recycled as the camera climbs (nothing is instantiated or freed during play once the pool
## has warmed up), so new tower sections never cause hitches.

## How far below / above the visible area platforms are kept alive (px).
const KEEP_BELOW: float = 160.0
const KEEP_ABOVE: float = 260.0

var run: RunManager = null

var _pool: Array = []
var _active: Dictionary = {}
var _lo: int = 0
var _hi: int = -1


func bind_run(r: RunManager) -> void:
	for f in _active:
		_release(_active[f])
	_active.clear()
	run = r
	_lo = 0
	_hi = -1


## Called every frame with the (interpolated) altitude of the bottom of the view.
func update_view(cam_bottom: float, view_h: float) -> void:
	if run == null:
		return
	var tower: PlatformGenerator = run.tower
	var lo: int = tower.index_at_or_below(cam_bottom - KEEP_BELOW)
	var hi: int = mini(tower.index_at_or_below(cam_bottom + view_h + KEEP_ABOVE) + 1, tower.platform_count() - 1)
	# release platforms that left the kept range
	if _hi >= _lo:
		var f: int = _lo
		while f <= _hi:
			if f < lo or f > hi:
				_release_floor(f)
			f += 1
	# make sure every platform in range has a view
	for g in range(lo, hi + 1):
		_acquire(g)
	_lo = lo
	_hi = hi


func _acquire(floor_index: int) -> void:
	if _active.has(floor_index):
		return
	var pv: PlatformView = null
	if _pool.is_empty():
		pv = PlatformView.new()
		add_child(pv)
	else:
		pv = _pool.pop_back()
	pv.setup(run.tower.platforms[floor_index], ThemeManager.theme_for_floor(floor_index))
	_active[floor_index] = pv


func _release_floor(floor_index: int) -> void:
	if _active.has(floor_index):
		_release(_active[floor_index])
		_active.erase(floor_index)


func _release(pv: PlatformView) -> void:
	pv.release()
	_pool.append(pv)


## Redraws all platforms (theme / setting change).
func refresh_all() -> void:
	for f in _active:
		var pv: PlatformView = _active[f]
		pv.setup(run.tower.platforms[f], ThemeManager.theme_for_floor(f))
