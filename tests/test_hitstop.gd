extends SceneTree
## Headless checks: godot --headless --path . --script tests/test_hitstop.gd

var failures: int = 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _fighter(name: String) -> Node2D:
	var body: Node2D = Node2D.new()
	body.name = name
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "Anim"
	player.speed_scale = 1.25
	body.add_child(player)
	var library: AnimationLibrary = AnimationLibrary.new()
	var idle: Animation = Animation.new()
	idle.length = 1.0
	idle.loop_mode = Animation.LOOP_LINEAR
	library.add_animation("idle", idle)
	player.add_animation_library("", library)
	player.play("idle")
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.speed_scale = 0.8
	body.add_child(sprite)
	var tree: AnimationTree = AnimationTree.new()
	tree.name = "Tree"
	body.add_child(tree)
	tree.active = true
	root.add_child(body)
	return body


var _hitstop: HitstopService


## Steps the hitstop clock `seconds` forward in 60 Hz frames.
func _wait(seconds: float) -> void:
	for i: int in roundi(seconds * 60.0):
		_hitstop.advance(1.0 / 60.0)
	await process_frame


func _initialize() -> void:
	var hitstop: HitstopService = HitstopService.new()
	hitstop.drive_manually = true  # the test steps the clock 1/60 s at a time
	root.add_child(hitstop)
	hitstop.set_process(false)
	_hitstop = hitstop
	var a: Node2D = _fighter("Attacker")
	var b: Node2D = _fighter("Target")
	var bystander: Node2D = _fighter("Bystander")
	var started: Array[int] = [0]
	var ended: Array[int] = [0]
	hitstop.freeze_started.connect(func(_n: Node, _s: float) -> void: started[0] += 1)
	hitstop.freeze_ended.connect(func(_n: Node) -> void: ended[0] += 1)
	await process_frame

	check(is_equal_approx(hitstop.seconds_for(4), 4.0 / 60.0), "4 frames is 4/60 s (%.4f) at any frame rate" % hitstop.seconds_for(4))
	hitstop.freeze([a, b], 4)
	check(not a.get_node("Anim").is_playing() and a.get_node("Sprite").speed_scale == 0.0 and not a.get_node("Tree").active, "the fighters' animation holds (AnimationPlayer paused, AnimatedSprite2D, AnimationTree)")
	check(bystander.get_node("Anim").is_playing(), "everyone else keeps moving")
	check(a.process_mode == Node.PROCESS_MODE_INHERIT, "pose mode leaves the fighters' logic running")
	check(started[0] == 2, "freeze_started for each fighter")
	await _wait(2.0 / 60.0)
	hitstop.freeze([a], 1)
	check(hitstop.is_frozen(a), "a shorter second freeze doesn't cut the first short")
	await _wait(1.0 / 60.0)
	check(hitstop.is_frozen(a) and hitstop.is_frozen(b), "still frozen after 3 of 4 frames")
	await _wait(1.0 / 60.0)
	check(not hitstop.is_frozen(a) and not hitstop.is_frozen(b), "both thaw after exactly 4 frames")
	check(a.get_node("Anim").is_playing() and a.get_node("Anim").speed_scale == 1.25 and is_equal_approx(a.get_node("Sprite").speed_scale, 0.8) and a.get_node("Tree").active, "every original value is restored exactly (anim %s, sprite %s, tree active %s)" % [a.get_node("Anim").speed_scale, a.get_node("Sprite").speed_scale, a.get_node("Tree").active])
	check(ended[0] == 2, "freeze_ended for each fighter")

	hitstop.freeze([a], 4)
	await _wait(2.0 / 60.0)
	hitstop.freeze([a], 6)
	await _wait(5.0 / 60.0)
	check(hitstop.is_frozen(a), "a longer second freeze extends the first (6 frames from the second hit)")
	await _wait(0.06)
	check(not hitstop.is_frozen(a), "and then ends")

	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	hitstop.freeze([b], 4, HitstopService.Mode.FULL)
	check(b.process_mode == Node.PROCESS_MODE_DISABLED, "full mode pauses the fighter's whole subtree")
	await _wait(0.1)
	check(b.process_mode == Node.PROCESS_MODE_PAUSABLE, "and puts its own process mode back")

	hitstop.freeze([a], 4)
	hitstop.freeze([a], 4, HitstopService.Mode.FULL)
	check(a.process_mode == Node.PROCESS_MODE_DISABLED and a.get_node("Anim").is_playing(), "a pose freeze upgraded to full mode restores the pose values first")
	await _wait(0.1)
	check(a.process_mode == Node.PROCESS_MODE_INHERIT, "the upgraded freeze ends cleanly")

	# Regression: an animation that triggers the hit from a method track must not refreeze itself every frame.
	var hits: Array[int] = [0]
	var looper: Node2D = _fighter("Looper")
	var anim: AnimationPlayer = looper.get_node("Anim")
	var swing: Animation = Animation.new()
	swing.length = 0.5
	swing.loop_mode = Animation.LOOP_LINEAR
	var call: int = swing.add_track(Animation.TYPE_METHOD)
	swing.track_set_path(call, NodePath("."))
	swing.track_insert_key(call, 0.25, {"method": "set_meta", "args": ["hit", true]})
	anim.get_animation_library("").add_animation("swing", swing)
	anim.speed_scale = 1.0
	anim.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play("swing")
	anim.animation_started.connect(func(_n: StringName) -> void: pass)
	for frame: int in 60:
		anim.advance(1.0 / 60.0)
		if looper.has_meta("hit"):
			looper.remove_meta("hit")
			hits[0] += 1
			hitstop.freeze([looper], 4)
		hitstop.advance(1.0 / 60.0)
	check(hits[0] >= 1 and hits[0] <= 3, "a hit fired from the animation freezes once per swing, not forever (%d hits in 1 s of a 0.5 s swing)" % hits[0])

	var doomed: Node2D = _fighter("Doomed")
	hitstop.freeze([doomed], 4)
	doomed.queue_free()
	await _wait(0.1)
	check(not hitstop.is_frozen(doomed), "a fighter freed mid-freeze is dropped without errors")

	hitstop.reduced_motion = true
	hitstop.freeze([a], 4)
	check(not hitstop.is_frozen(a), "reduced motion skips the freeze")
	hitstop.reduced_motion = false
	hitstop.max_frames = 6.0
	check(is_equal_approx(hitstop.seconds_for(20), 0.1), "max_frames caps a long freeze (20 frames -> 6)")
	hitstop.duration_scale = 0.5
	check(is_equal_approx(hitstop.seconds_for(4), 2.0 / 60.0), "duration_scale scales it")
	hitstop.duration_scale = 1.0

	Engine.time_scale = 1.0
	hitstop.freeze_everything(4)
	check(Engine.time_scale == 0.0, "freeze_everything stops the whole game")
	hitstop.drive_manually = false
	hitstop.set_process(true)
	await create_timer(0.15, true, false, true).timeout
	check(Engine.time_scale == 1.0, "and gives the time scale back")

	for n: Node in [hitstop, a, b, bystander]:
		n.queue_free()
	await process_frame
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
