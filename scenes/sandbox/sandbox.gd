extends Node2D

var brush := CircleIsolinesBrush.new()

var type: int = 1

@onready var grid: IsolinesGrid = $DualContourIsolinesGrid
@onready var type_label: Label = $CanvasLayer/TypeLabel

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			brush.center = grid.to_local(get_viewport_transform().affine_inverse() * event.position)
			brush.type = 0 if event.button_index == MOUSE_BUTTON_RIGHT else type
			brush.radius = 4.0
			grid.apply_brush(brush)
			queue_redraw()
	
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var c = grid.to_local(get_viewport_transform().affine_inverse() * event.position)
			if brush.center != c:
				brush.center = c
				brush.type = type
				brush.radius = 4.0
				grid.apply_brush(brush)
				queue_redraw()
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			var c = grid.to_local(get_viewport_transform().affine_inverse() * event.position)
			if brush.center != c:
				brush.center = c
				brush.type = 0
				brush.radius = 2.0
				grid.apply_brush(brush)
				queue_redraw()
	
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_1:
			type = 1
			type_label.text = "Type 1"
		if event.pressed and event.keycode == KEY_2:
			type = 2
			type_label.text = "Type 2"
		if event.pressed and event.keycode == KEY_3:
			type = 3
			type_label.text = "Type 3"

func _draw() -> void:
	draw_circle(grid.to_global(brush.center), brush.radius * 16.0, Color.RED, false)
