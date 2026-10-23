@icon("res://addons/hitstop/icon.svg")
class_name HitstopService
extends Node
## Hitstop (hit stop, hit pause): a freeze of a few frames on the frame a hit
## connects, so the blow feels like it bit into something.
##
## By default only the fighters you name freeze, and only their animation: the
## rest of the world keeps running, so it works in co-op and never pauses other
## players. Durations are in 60 Hz frames, so 4 means 67 ms at any frame rate.
## Overlapping freezes extend instead of stacking, everything is restored
## exactly, and freed nodes are handled. Freezes run on game time, so slow
## motion (Engine.time_scale) slows them too. Turn it off with `reduced_motion`.
##
##   Hitstop.freeze([attacker, target], 4)           # a sword hit
##   Hitstop.freeze([attacker, target], 5, Hitstop.Mode.FULL)
##
## Added as the autoload `Hitstop` by the plugin. From Mytheria
## (cobomakesgames.com/blog/how-to-make-combat-feel-good/).

signal freeze_started(node: Node, seconds: float)
signal freeze_ended(node: Node)

enum Mode {
	## Pause only animation (AnimationPlayer, AnimationTree, AnimatedSprite2D/3D,
	## GPU/CPU particles): the pose holds, movement and logic carry on.
	POSE,
	## Pause the node's whole subtree (its _process and _physics_process too), for
	## single-player games where the fighters themselves should stop.
	FULL,
}

## Players who turn on Reduced motion skip every freeze.
@export var reduced_motion: bool = false
## Multiplies every duration (a "hit pause" slider). 0 turns hitstop off.
@export_range(0.0, 3.0, 0.05) var duration_scale: float = 1.0
## The longest any freeze may last, in 60 Hz frames, however many hits extend it.
@export_range(1.0, 60.0, 1.0) var max_frames: float = 12.0
## Drive the clock yourself with advance() (replays, lockstep games, tests) instead of _process.
@export var drive_manually: bool = false

## node -> {until, mode, saved: {object_id: original value}}; `until` is on the game clock.
var _frozen: Dictionary = {}
## Game time in seconds: the sum of _process deltas, so it follows Engine.time_scale.
var _clock: float = 0.0
var _global_until: int = 0
var _global_saved_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000


## Freezes `nodes` for `frames` 60 Hz frames (4 = about 67 ms). Calling it again
## while a node is frozen extends that node's freeze to whichever ends later.
func freeze(nodes: Array, frames: float, mode: Mode = Mode.POSE) -> void:
	var seconds: float = seconds_for(frames)
	if seconds <= 0.0:
		return
	var until: float = _clock + seconds
	for node: Variant in nodes:
		if not node is Node or not is_instance_valid(node):
			continue
		var entry: Variant = _frozen.get(node)
		if entry is Dictionary:
			entry.until = maxf(float(entry.until), until)
			if mode == Mode.FULL and int(entry.mode) == Mode.POSE:
				_restore(node, entry)
				entry.saved = _hold(node, Mode.FULL)
				entry.mode = Mode.FULL
			continue
		_frozen[node] = {"until": until, "mode": mode, "saved": _hold(node, mode)}
		freeze_started.emit(node, seconds)
	set_process(not drive_manually)


## The classic whole-game freeze through Engine.time_scale. Only for single-player
## games: it stops everything, including other players' views in a shared world.
## Timed in real time, since game time stands still while it lasts.
func freeze_everything(frames: float) -> void:
	var seconds: float = seconds_for(frames)
	if seconds <= 0.0:
		return
	if _global_until == 0:
		_global_saved_scale = Engine.time_scale
	_global_until = maxi(_global_until, Time.get_ticks_usec() + int(seconds * 1000000.0))
	Engine.time_scale = 0.0
	set_process(true)


## Seconds a freeze of `frames` 60 Hz frames lasts after `duration_scale`, `max_frames` and reduced motion.
func seconds_for(frames: float) -> float:
	if reduced_motion or duration_scale <= 0.0 or frames <= 0.0:
		return 0.0
	return minf(frames * duration_scale, max_frames) / 60.0


## Whether `node` is frozen now. Safe to call with a node that has been freed.
func is_frozen(node: Variant) -> bool:
	return is_instance_valid(node) and _frozen.has(node)


## Ends every freeze now and restores everything.
func release_all() -> void:
	for node: Variant in _frozen.keys():
		_end(node)
	if _global_until != 0:
		Engine.time_scale = _global_saved_scale
		_global_until = 0


func _process(delta: float) -> void:
	advance(delta)


## Moves the freeze clock forward by `delta` seconds of game time and ends due freezes.
func advance(delta: float) -> void:
	_clock += maxf(0.0, delta)
	for node: Variant in _frozen.keys():
		if not is_instance_valid(node):
			_frozen.erase(node)
		elif _clock >= float(_frozen[node].until):
			_end(node)
	if _global_until != 0 and Time.get_ticks_usec() >= _global_until:
		Engine.time_scale = _global_saved_scale
		_global_until = 0
	if _frozen.is_empty() and _global_until == 0 and not drive_manually:
		set_process(false)


func _end(node: Variant) -> void:
	var entry: Dictionary = _frozen[node]
	_frozen.erase(node)
	if is_instance_valid(node):
		_restore(node, entry)
		freeze_ended.emit(node)


## Pauses the node and returns what it changed, so it can be put back exactly.
func _hold(node: Node, mode: Mode) -> Dictionary:
	var saved: Dictionary = {}
	if mode == Mode.FULL:
		saved[node.get_instance_id()] = {"process_mode": node.process_mode}
		node.process_mode = Node.PROCESS_MODE_DISABLED
		return saved
	for target: Node in [node] + node.find_children("*", "", true, false):
		if target is AnimationTree:
			saved[target.get_instance_id()] = {"active": target.active}
			target.active = false
		elif target is AnimationPlayer:
			# Paused, not slowed to zero: at speed 0 Godot re-fires method-track keys on the
			# frozen frame, so an animation that calls your hit code would freeze itself forever.
			var player: AnimationPlayer = target
			saved[target.get_instance_id()] = {"_resume": player.is_playing()}
			if player.is_playing():
				player.pause()
		elif target is AnimatedSprite2D or target is AnimatedSprite3D or target is GPUParticles2D or target is GPUParticles3D or target is CPUParticles2D or target is CPUParticles3D:
			saved[target.get_instance_id()] = {"speed_scale": target.get("speed_scale")}
			target.set("speed_scale", 0.0)
	return saved


func _restore(node: Node, entry: Dictionary) -> void:
	for id: int in entry.saved:
		var target: Object = instance_from_id(id)
		if target == null:
			continue
		for property: String in entry.saved[id]:
			if property == "_resume":
				if entry.saved[id][property] and target is AnimationPlayer:
					(target as AnimationPlayer).play()  # resumes from the paused position
			else:
				target.set(property, entry.saved[id][property])
