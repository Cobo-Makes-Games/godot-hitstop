extends Node2D
## Hitstop demo: the attacker swings at the dummy on a loop. Each contact freezes
## both fighters for a few 60 Hz frames while the walker in the back keeps moving,
## which is why it's safe in co-op. Slow motion makes the freeze easy to see.

var attacker: Node2D
var dummy: Node2D
var walker: Node2D
var frames: float = 4.0
var mode: HitstopService.Mode = HitstopService.Mode.POSE
var flash: float = 0.0
var status: Label
var slow: CheckBox
var swing_phase: float = 0.0


func _ready() -> void:
	attacker = _fighter(Vector2(390, 300), Color("e9d6a8"), true)
	dummy = _fighter(Vector2(560, 300), Color("c9705b"), false)
	walker = _fighter(Vector2(200, 420), Color("8fb7d9"), false)
	_build_ui()
	if OS.get_cmdline_user_args().has("--autoplay"):
		slow.button_pressed = true
		get_tree().create_timer(5.0, true, false, true).timeout.connect(func() -> void: get_tree().quit())


## A body with a looping "breathing" animation on an AnimationPlayer, so the freeze is visible.
func _fighter(at: Vector2, color: Color, swings: bool) -> Node2D:
	var body: Node2D = Node2D.new()
	body.position = at
	add_child(body)
	var shape: Polygon2D = Polygon2D.new()
	var points: PackedVector2Array = []
	for i: int in 24:
		points.append(Vector2.RIGHT.rotated(TAU * i / 24.0) * 30.0)
	shape.polygon = points
	shape.color = color
	shape.name = "Shape"
	body.add_child(shape)
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "Anim"
	body.add_child(player)
	var library: AnimationLibrary = AnimationLibrary.new()
	var bob: Animation = Animation.new()
	bob.length = 0.8
	bob.loop_mode = Animation.LOOP_LINEAR
	var track: int = bob.add_track(Animation.TYPE_VALUE)
	bob.track_set_path(track, "Shape:scale")
	bob.track_insert_key(track, 0.0, Vector2(1.0, 1.0))
	bob.track_insert_key(track, 0.4, Vector2(1.06, 0.94))
	bob.track_insert_key(track, 0.8, Vector2(1.0, 1.0))
	library.add_animation("bob", bob)
	if swings:
		var blade: Line2D = Line2D.new()
		blade.name = "Blade"
		blade.points = PackedVector2Array([Vector2(28, 0), Vector2(86, 0)])
		blade.width = 7.0
		blade.default_color = Color("cfd8e6")
		body.add_child(blade)
		var swing: Animation = Animation.new()
		swing.length = 0.9
		swing.loop_mode = Animation.LOOP_LINEAR
		var rot: int = swing.add_track(Animation.TYPE_VALUE)
		swing.track_set_path(rot, "Blade:rotation")
		swing.track_insert_key(rot, 0.0, -1.2)
		swing.track_insert_key(rot, 0.35, 0.0)
		swing.track_insert_key(rot, 0.9, -1.2)
		var call: int = swing.add_track(Animation.TYPE_METHOD)
		swing.track_set_path(call, NodePath(".."))
		swing.track_insert_key(call, 0.35, {"method": "_contact", "args": []})
		library.add_animation("swing", swing)
	player.add_animation_library("", library)
	player.play("swing" if swings else "bob")
	return body


func _contact() -> void:
	flash = 1.0
	Hitstop.freeze([attacker, dummy], frames, mode)
	status.text = "Contact: %d frames (%d ms) of hitstop on the attacker and the dummy. The walker never stops." % [int(frames), roundi(Hitstop.seconds_for(frames) * 1000.0)]


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(16, 14)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.065, 0.085, 0.92)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = "Hitstop: each contact freezes both fighters. The walker keeps going."
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var label: Label = Label.new()
	label.text = "Frames"
	row.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 12
	slider.step = 1
	slider.value = frames
	slider.custom_minimum_size.x = 160
	var value: Label = Label.new()
	value.text = "4 (sword)"
	slider.value_changed.connect(func(v: float) -> void:
		frames = v
		value.text = "%d%s" % [int(v), {0.0: " (off)", 1.0: " (ranged)", 3.0: " (thrust)", 4.0: " (sword)", 5.0: " (heavy)"}.get(v, "")])
	row.add_child(slider)
	row.add_child(value)
	var full: CheckBox = CheckBox.new()
	full.text = "Full mode (pause their scripts too)"
	full.toggled.connect(func(on: bool) -> void: mode = HitstopService.Mode.FULL if on else HitstopService.Mode.POSE)
	row.add_child(full)
	var options: HBoxContainer = HBoxContainer.new()
	box.add_child(options)
	slow = CheckBox.new()
	slow.text = "Slow motion (x0.25) to see the freeze"
	slow.toggled.connect(func(on: bool) -> void: Engine.time_scale = 0.25 if on else 1.0)
	options.add_child(slow)
	var reduced: CheckBox = CheckBox.new()
	reduced.text = "Reduced motion (no hitstop)"
	reduced.toggled.connect(func(on: bool) -> void: Hitstop.reduced_motion = on)
	options.add_child(reduced)
	status = Label.new()
	status.modulate = Color(1, 1, 1, 0.75)
	status.text = "The attacker swings on a loop."
	box.add_child(status)


func _process(delta: float) -> void:
	walker.position.x = 200.0 + 560.0 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * Engine.time_scale * 1.6))
	flash = maxf(0.0, flash - delta * 6.0)
	(dummy.get_node("Shape") as Polygon2D).color = Color("c9705b").lerp(Color("fff3d6"), flash if Hitstop.is_frozen(dummy) or flash > 0.5 else 0.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("1d1b22"))
	for x: int in range(0, 960, 40):
		draw_line(Vector2(x, 0), Vector2(x, 540), Color(1, 1, 1, 0.05))
	for y: int in range(0, 540, 40):
		draw_line(Vector2(0, y), Vector2(960, y), Color(1, 1, 1, 0.05))
	var frozen: bool = Hitstop.is_frozen(attacker)
	draw_string(ThemeDB.fallback_font, Vector2(400, 380), "FROZEN" if frozen else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.6, 0.9))
