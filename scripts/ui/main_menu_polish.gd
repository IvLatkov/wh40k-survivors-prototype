class_name MainMenuPolish
extends Node

const TRANSITION_SECONDS := 0.18
const SLIDE_PIXELS := 10.0
const HOVER_SECONDS := 0.12

# Inspector switch also allows a static comparison without changing menu behavior.
@export var enabled: bool = true

var _generation: int = 0
var _transition_target: Control
var _rest_position: Vector2
var _sliding: bool = false
var _transition: Tween
var _button_tweens: Dictionary[Button, Tween] = {}


func setup(menu: Control) -> void:
	if not enabled:
		return
	var background := menu.get_node("Background") as ColorRect
	var pulse := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(background, "color", Color(0.021, 0.032, 0.043), 3.0)
	pulse.tween_property(background, "color", background.color, 3.0)
	for node in menu.find_children("*", "Button", true, false):
		_prepare_button(node as Button, node == menu.get_node("%Deploy"))
	var deploy_style := (menu.get_node("%Deploy") as Button).get_theme_stylebox("normal") as StyleBoxFlat
	var deploy_focus := (menu.get_node("%Deploy") as Button).get_theme_stylebox("focus") as StyleBoxFlat
	var emphasis := create_tween().set_loops().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	emphasis.tween_property(deploy_style, "border_color", Color(0.58, 0.72, 0.8), 2.4)
	emphasis.tween_property(deploy_focus, "border_color", Color(0.63, 0.76, 0.84), 2.4)
	emphasis.chain().tween_property(deploy_style, "border_color", deploy_style.border_color, 2.4)
	emphasis.parallel().tween_property(deploy_focus, "border_color", deploy_focus.border_color, 2.4)
	for portrait: TextureRect in [menu.get_node("%Portrait"), menu.get_node("%UltramarineCard").get_node("%Portrait")]:
		var breath := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		breath.tween_method(_move_portrait.bind(portrait), 0.0, -2.0, 1.6)
		breath.tween_method(_move_portrait.bind(portrait), -2.0, 0.0, 1.6)


func _move_portrait(offset: float, portrait: TextureRect) -> void:
	# Move only the image inside a fixed layout slot, in whole pixels; never scale it.
	portrait.position.y = roundf(offset)


func _prepare_button(button: Button, primary: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var source := button.get_theme_stylebox(state) as StyleBoxFlat
		if source == null:
			continue
		var style := source.duplicate() as StyleBoxFlat
		style.shadow_size = 6 if primary else 3
		style.shadow_color = Color(0.42, 0.64, 0.77, 0.0)
		button.add_theme_stylebox_override(state, style)
	for event: StringName in [&"mouse_entered", &"mouse_exited", &"focus_entered", &"focus_exited"]:
		button.connect(event, _update_glow.bind(button, primary))


func _update_glow(button: Button, primary: bool) -> void:
	if _button_tweens.has(button) and _button_tweens[button].is_valid():
		_button_tweens[button].kill()
	var active := not button.disabled and (button.is_hovered() or button.has_focus())
	var alpha := (0.22 if primary else 0.12) if active else 0.0
	var tween := create_tween().set_parallel()
	_button_tweens[button] = tween
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		if style != null:
			tween.tween_property(style, "shadow_color", Color(0.42, 0.64, 0.77, alpha), HOVER_SECONDS)


func reveal(target: Control) -> void:
	finish_transition()
	if not enabled:
		return
	_transition_target = target
	target.modulate.a = 0.72
	_start_slide(target, _generation)


func _start_slide(target: Control, generation: int) -> void:
	# Let the existing containers settle before recording their authoritative position.
	var tree := get_tree()
	await tree.process_frame
	if generation != _generation or not is_inside_tree():
		return
	await tree.process_frame
	if generation != _generation or not is_inside_tree():
		return
	_rest_position = target.position
	_sliding = true
	target.position = _rest_position + Vector2(0, SLIDE_PIXELS)
	_transition = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(target, "position", _rest_position, TRANSITION_SECONDS)
	_transition.tween_property(target, "modulate:a", 1.0, TRANSITION_SECONDS)
	_transition.finished.connect(_reveal_finished.bind(generation))


func _reveal_finished(generation: int) -> void:
	if generation == _generation:
		_transition_target.position = _rest_position
		_transition_target.modulate.a = 1.0
		_transition_target = null
		_sliding = false


func finish_transition() -> void:
	_generation += 1
	if _transition != null and _transition.is_valid():
		_transition.kill()
	if is_instance_valid(_transition_target):
		_transition_target.modulate.a = 1.0
		if _sliding:
			_transition_target.position = _rest_position
		if _transition_target.get_parent() is Container:
			(_transition_target.get_parent() as Container).queue_sort()
	_transition_target = null
	_sliding = false


func is_transitioning() -> bool:
	return _transition_target != null


func _exit_tree() -> void:
	# DEPLOY may unload the scene between the two layout waits.
	_generation += 1
