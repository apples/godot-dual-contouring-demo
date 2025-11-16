extends CharacterBody2D

signal clicky(where: Vector2, type: int)

const SPEED = 200.0

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var foot_area_2d: Area2D = $FootArea2D
@onready var smoke_particles: GPUParticles2D = $SmokeParticles
@onready var ice_particles: GPUParticles2D = $IceParticles

var _foot_surface_types: Dictionary[int, int]

func _physics_process(_delta: float) -> void:
	var max_speed := SPEED / 2.0 if 3 in _foot_surface_types else SPEED
	
	var direction := Input.get_vector("left", "right", "up", "down")
	var desired_velocity := Vector2.ZERO
	if direction:
		desired_velocity = direction * max_speed
	
	var accel := 300.0 if 2 in _foot_surface_types else 5000.0
	
	velocity = velocity.move_toward(desired_velocity, _delta * accel)
	
	if velocity.x < 0.0:
		animated_sprite_2d.flip_h = true
	elif velocity.x > 0.0:
		animated_sprite_2d.flip_h = false
	
	move_and_slide()
	
	if velocity:
		animated_sprite_2d.play("walk")
	else:
		animated_sprite_2d.play("idle")
	
	smoke_particles.emitting = 1 in _foot_surface_types
	ice_particles.emitting = 2 in _foot_surface_types

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					clicky.emit(get_global_mouse_position(), 1)
				MOUSE_BUTTON_RIGHT:
					clicky.emit(get_global_mouse_position(), 2)

func _on_foot_area_2d_area_shape_entered(area_rid: RID, _area: Area2D, _area_shape_index: int, _local_shape_index: int) -> void:
	var type := IsolinesGrid.get_area_type(area_rid)
	if type != -1:
		var c: int = _foot_surface_types.get(type, 0)
		_foot_surface_types[type] = c + 1

func _on_foot_area_2d_area_shape_exited(area_rid: RID, _area: Area2D, _area_shape_index: int, _local_shape_index: int) -> void:
	var type := IsolinesGrid.get_area_type(area_rid)
	if type != -1:
		_foot_surface_types[type] -= 1
		if _foot_surface_types[type] == 0:
			_foot_surface_types.erase(type)
