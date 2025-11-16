extends Node2D

const STEAM_PARTICLES = preload("uid://rm26oxjkpqt4")

var _steam_particles_pool: Array[GPUParticles2D]

@onready var grid: IsolinesGrid = $DualContourIsolinesGrid

func _ready() -> void:
	pass

func _on_player_clicky(where: Vector2, type: int) -> void:
	var brush := CircleIsolinesBrush.new()
	brush.center = grid.to_local(where)
	brush.type = type
	brush.radius = 4.0
	grid.apply_brush(brush)

func _on_dual_contour_isolines_grid_brush_applied(
	cell_positions: PackedVector2Array,
	_previous_types: PackedInt32Array,
	current_types: PackedInt32Array,
) -> void:
	for i in cell_positions.size():
		if current_types[i] != 3:
			continue
		
		var particles: GPUParticles2D
		if _steam_particles_pool.is_empty():
			particles = STEAM_PARTICLES.instantiate()
		else:
			particles = _steam_particles_pool.pop_back()
		
		particles.restart()
		particles.position = to_local(grid.to_global(cell_positions[i]))
		add_child(particles)
		particles.emitting = true
		
		(func ():
			await particles.finished
			remove_child(particles)
			_steam_particles_pool.append(particles)
		).call()
