@tool
extends IsolinesGrid
class_name DualContourIsolinesGrid
## Implements dual contouring for an isolines grid.
##
## References:
## https://catlikecoding.com/unity/tutorials/marching-squares-series/
## https://www.mattkeeter.com/projects/contours/ (https://web.archive.org/web/20251116110255/https://www.mattkeeter.com/projects/contours/)
## https://www.boristhebrave.com/2018/04/15/dual-contouring-tutorial/ (https://web.archive.org/web/20251116110408/https://www.boristhebrave.com/2018/04/15/dual-contouring-tutorial/)

## The size of each chunk. Benchmarks required.
const CHUNK_SIZE = Vector2i(16, 16)

## If true, cell polygons will be merged together into larger convex polygons.
## Requires https://github.com/godotengine/godot/pull/104407.
@export var optimize_convex_polygons: bool = true:
	set(v):
		optimize_convex_polygons = v
		update_configuration_warnings()

var _chunks: Dictionary[Vector2i, Chunk]
var _first_empty_chunk: Chunk

func _get_configuration_warnings() -> PackedStringArray:
	if optimize_convex_polygons:
		return ["optimize_convex_polygons is only useful when building godot with https://github.com/godotengine/godot/pull/104407"]
	return []

func get_cell_type(pos: Vector2i) -> int:
	var chunk_i := Vector2i((Vector2(pos) / Vector2(CHUNK_SIZE)).floor())
	var chunk: Chunk = _chunks.get(chunk_i, null)
	
	if chunk == null:
		return 0
	
	var relative_pos := pos - chunk_i * CHUNK_SIZE
	assert(relative_pos.x >= 0 and relative_pos.x < CHUNK_SIZE.x)
	assert(relative_pos.y >= 0 and relative_pos.y < CHUNK_SIZE.y)
	
	return chunk.cell_types[relative_pos.y * CHUNK_SIZE.x + relative_pos.x]

func apply_brush(brush: IsolinesBrush) -> void:
	var bounds := brush.get_bounds().abs()
	
	# Brush region must be expanded one cell on negative sides, so edge data can be computed. 
	var cell_region := Rect2i()
	cell_region.position = Vector2i((bounds.position - Vector2.ONE).floor())
	cell_region.end = Vector2i(bounds.end.ceil()) + Vector2i.ONE
	
	var chunks_region := Rect2i()
	chunks_region.position = Vector2i((Vector2(cell_region.position) / Vector2(CHUNK_SIZE)).floor())
	chunks_region.end = Vector2i((Vector2(cell_region.end) / Vector2(CHUNK_SIZE)).floor()) + Vector2i.ONE
	
	var affected_cell_positions := PackedVector2Array()
	var affected_cell_previous_types := PackedInt32Array()
	var affected_cell_current_types := PackedInt32Array()
	
	# List of chunks affected by the brush.
	var brush_chunks: Array[Chunk]
	
	# Ensure chunks exist and gather brush_chunks.
	for chunk_y: int in chunks_region.size.y:
		for chunk_x: int in chunks_region.size.x:
			var chunk_i := chunks_region.position + Vector2i(chunk_x, chunk_y)
			var chunk: Chunk = _chunks.get(chunk_i, null)
			if chunk == null:
				if _first_empty_chunk != null:
					chunk = _first_empty_chunk
					_first_empty_chunk = chunk.next_empty_chunk
					chunk.clear()
				else:
					chunk = Chunk.new()
				chunk.chunk_i = chunk_i
				_chunks[chunk_i] = chunk
			brush_chunks.append(chunk)
	
	# Apply only types first (including mixer results).
	for chunk: Chunk in brush_chunks:
		var chunk_rect := Rect2i(chunk.chunk_i * CHUNK_SIZE, CHUNK_SIZE)
		var chunk_brush_rect := chunk_rect.intersection(cell_region)
		
		for y: int in chunk_brush_rect.size.y:
			for x: int in chunk_brush_rect.size.x:
				var absolute_pos := chunk_brush_rect.position + Vector2i(x, y)
				var relative_pos := absolute_pos - chunk_rect.position
				var i := relative_pos.y * CHUNK_SIZE.x + relative_pos.x
				
				var brush_type := brush.get_type(absolute_pos)
				if brush_type != -1:
					var surface_type := chunk.cell_types[i]
					chunk.cell_types[i] = (
						brush_type if not mixer
						else mixer.mix_types(chunk.cell_types[i], brush_type)
					)
					affected_cell_positions.append(Vector2(absolute_pos))
					affected_cell_previous_types.append(surface_type)
					affected_cell_current_types.append(chunk.cell_types[i])
	
	# Apply edges.
	for chunk: Chunk in brush_chunks:
		var chunk_rect := Rect2i(chunk.chunk_i * CHUNK_SIZE, CHUNK_SIZE)
		var chunk_brush_rect := chunk_rect.intersection(cell_region)
		
		var neighbor_y: Chunk = _chunks.get(chunk.chunk_i + Vector2i(0, 1), null)
		var neighbor_x: Chunk = _chunks.get(chunk.chunk_i + Vector2i(1, 0), null)
		
		for y: int in chunk_brush_rect.size.y:
			for x: int in chunk_brush_rect.size.x:
				var absolute_pos := chunk_brush_rect.position + Vector2i(x, y)
				var relative_pos := absolute_pos - chunk_rect.position
				var i := relative_pos.y * CHUNK_SIZE.x + relative_pos.x
				
				# Vertical edges.
				
				var next_y_pos := absolute_pos + Vector2i(0, 1)
				var next_y := \
					chunk.cell_types[i + CHUNK_SIZE.x] if relative_pos.y + 1 < CHUNK_SIZE.y \
					else neighbor_y.cell_types[relative_pos.x] if neighbor_y \
					else 0
				
				# If the edge is between two cells with the same type,
				# it's an internal edge and should not be processed.
				if chunk.cell_types[i] == next_y:
					chunk.cell_vertical_edge_offsets[i] = -1.0
				else:
					var edge := brush.get_edge(absolute_pos, next_y_pos)
					if edge:
						chunk.cell_vertical_edge_offsets[i] = edge[0].y - float(absolute_pos.y)
						chunk.cell_vertical_edge_normals[i] = edge[1]
				
				# Horizontal edges.
				
				var next_x_pos := absolute_pos + Vector2i(1, 0)
				var next_x := \
					chunk.cell_types[i + 1] if relative_pos.x + 1 < CHUNK_SIZE.x \
					else neighbor_x.cell_types[i - relative_pos.x] if neighbor_x \
					else 0
				
				# If the edge is between two cells with the same type,
				# it's an internal edge and should not be processed.
				if chunk.cell_types[i] == next_x:
					chunk.cell_horizontal_edge_offsets[i] = -1.0
				else:
					var edge := brush.get_edge(absolute_pos, next_x_pos)
					if edge:
						chunk.cell_horizontal_edge_offsets[i] = edge[0].x - float(absolute_pos.x)
						chunk.cell_horizontal_edge_normals[i] = edge[1]
	
	# Recompute chunk data.
	
	for chunk: Chunk in brush_chunks:
		chunk.recompute_independent_data(self)
	
	for chunk: Chunk in brush_chunks:
		chunk.recompute_dependent_data(self)
	
	var updated_chunks := PackedVector2Array()
	var removed_chunks := PackedVector2Array()
	
	for chunk: Chunk in brush_chunks:
		var chunk_i := chunk.chunk_i
		
		# Remove a chunk if it has no surfaces, but also only if the surrounding chunks
		# also have no surfaces. This ensures that useful cell vertex data is kept.
		# Only neighbors in positive directions need to be considered.
		if chunk.surface_types.is_empty():
			if (get_chunk_surface_count(Vector2i(chunk_i.x + 1, chunk_i.y)) == 0
				and get_chunk_surface_count(Vector2i(chunk_i.x, chunk_i.y + 1)) == 0
				and get_chunk_surface_count(Vector2i(chunk_i.x + 1, chunk_i.y + 1)) == 0
			):
				chunk.next_empty_chunk = _first_empty_chunk
				_first_empty_chunk = chunk
				_chunks.erase(chunk_i)
				removed_chunks.append(chunk_i)
			else:
				updated_chunks.append(chunk_i)
		else:
			updated_chunks.append(chunk_i)
	
	# Signals.
	
	# Emit chunk_removed before chunk_updated so callees can implement more efficient pooling.
	for chunk_i: Vector2i in removed_chunks:
		chunk_removed.emit(Vector2(chunk_i))
	
	for chunk_i: Vector2i in updated_chunks:
		chunk_updated.emit(Vector2(chunk_i))
	
	# Emit brush_applied last, so the callee can access completely up-to-date data.
	brush_applied.emit(affected_cell_positions, affected_cell_previous_types, affected_cell_current_types)

func get_chunk_size() -> Vector2i:
	return CHUNK_SIZE

func get_chunks() -> PackedVector2Array:
	return PackedVector2Array(_chunks.keys())

func get_chunk_surface_count(chunk_i: Vector2i) -> int:
	var chunk: Chunk = _chunks.get(chunk_i, null)
	if chunk == null:
		return 0
	return chunk.surface_types.size()

func get_chunk_surface_type(chunk_i: Vector2i, surface_i: int) -> int:
	var chunk: Chunk = _chunks.get(chunk_i, null)
	return chunk.surface_types[surface_i]

func get_chunk_surface_polygons(chunk_i: Vector2i, surface_i: int) -> Array[PackedVector2Array]:
	var chunk: Chunk = _chunks.get(chunk_i, null)
	return chunk.surface_polygons[surface_i]

func get_chunk_edge_crossings(chunk_i: Vector2i) -> PackedVector2Array:
	var chunk: Chunk = _chunks.get(chunk_i, null)
	var crossings := PackedVector2Array()
	
	for i in chunk.cell_types.size():
		@warning_ignore("integer_division")
		var pos := Vector2(i % CHUNK_SIZE.x, i / CHUNK_SIZE.x)
	
		if chunk.cell_vertical_edge_offsets[i] != -1.0:
			crossings.append(pos + Vector2(0, chunk.cell_vertical_edge_offsets[i]))
			crossings.append(chunk.cell_vertical_edge_normals[i])
	
		if chunk.cell_horizontal_edge_offsets[i] != -1.0:
			crossings.append(pos + Vector2(chunk.cell_horizontal_edge_offsets[i], 0))
			crossings.append(chunk.cell_horizontal_edge_normals[i])
	
	return crossings

## Internal chunk data.
class Chunk extends RefCounted:
	var chunk_i: Vector2i
	
	var cell_types: PackedInt32Array
	var cell_vertices: PackedVector2Array
	var cell_vertical_edge_offsets: PackedFloat32Array
	var cell_vertical_edge_normals: PackedVector2Array
	var cell_horizontal_edge_offsets: PackedFloat32Array
	var cell_horizontal_edge_normals: PackedVector2Array
	
	var surface_types: PackedInt32Array
	var surface_polygons: Array # Array[Array[PackedVector2Array]]
	
	## Used when this chunk is in the free list.
	var next_empty_chunk: Chunk
	
	func _init() -> void:
		cell_types.resize(CHUNK_SIZE.x * CHUNK_SIZE.y)
		cell_vertices.resize(CHUNK_SIZE.x * CHUNK_SIZE.y)
		cell_vertical_edge_offsets.resize(CHUNK_SIZE.x * CHUNK_SIZE.y)
		cell_vertical_edge_normals.resize(CHUNK_SIZE.x * CHUNK_SIZE.y)
		cell_horizontal_edge_offsets.resize(CHUNK_SIZE.x * CHUNK_SIZE.y)
		cell_horizontal_edge_normals.resize(CHUNK_SIZE.x * CHUNK_SIZE.y)
		clear()
	
	func clear() -> void:
		chunk_i = Vector2i.MIN
		cell_types.fill(0)
		cell_vertices.fill(Vector2(0.5, 0.5))
		cell_vertical_edge_offsets.fill(-1.0)
		cell_vertical_edge_normals.fill(Vector2(0.0, 1.0))
		cell_horizontal_edge_offsets.fill(-1.0)
		cell_horizontal_edge_normals.fill(Vector2(1.0, 0.0))
		surface_types.clear()
		surface_polygons.clear()
	
	func recompute_independent_data(grid: DualContourIsolinesGrid) -> void:
		var neighbor_y: Chunk = grid._chunks.get(chunk_i + Vector2i(0, 1), null)
		var neighbor_x: Chunk = grid._chunks.get(chunk_i + Vector2i(1, 0), null)
		
		# Compute best vertices
		for i: int in cell_types.size():
			@warning_ignore("integer_division")
			var relative_pos := Vector2i(i % CHUNK_SIZE.x, i / CHUNK_SIZE.x)
			
			var left_edge_position: float = cell_vertical_edge_offsets[i]
			var left_edge_normal: Vector2 = cell_vertical_edge_normals[i]
			var bottom_edge_position: float = cell_horizontal_edge_offsets[i]
			var bottom_edge_normal: Vector2 = cell_horizontal_edge_normals[i]
			var right_edge_position: float = -1.0
			var right_edge_normal: Vector2
			if relative_pos.x + 1 < CHUNK_SIZE.x:
				right_edge_position = cell_vertical_edge_offsets[i + 1]
				right_edge_normal = cell_vertical_edge_normals[i + 1]
			elif neighbor_x:
				right_edge_position = neighbor_x.cell_vertical_edge_offsets[i + 1 - CHUNK_SIZE.x]
				right_edge_normal = neighbor_x.cell_vertical_edge_normals[i + 1 - CHUNK_SIZE.x]
			var top_edge_position: float = -1.0
			var top_edge_normal: Vector2
			if relative_pos.y + 1 < CHUNK_SIZE.y:
				top_edge_position = cell_horizontal_edge_offsets[i + CHUNK_SIZE.x]
				top_edge_normal = cell_horizontal_edge_normals[i + CHUNK_SIZE.x]
			elif neighbor_y:
				top_edge_position = neighbor_y.cell_horizontal_edge_offsets[relative_pos.x]
				top_edge_normal = neighbor_y.cell_horizontal_edge_normals[relative_pos.x]
			
			cell_vertices[i] = Vector2(relative_pos) + QEFSolver.best_fit(
				left_edge_position, left_edge_normal,
				bottom_edge_position, bottom_edge_normal,
				right_edge_position, right_edge_normal,
				top_edge_position, top_edge_normal,
			)
	
	func recompute_dependent_data(grid: DualContourIsolinesGrid) -> void:
		surface_types.clear()
		surface_polygons.clear()
		
		var neighbor_ny: Chunk = grid._chunks.get(chunk_i + Vector2i(0, -1), null)
		var neighbor_nx: Chunk = grid._chunks.get(chunk_i + Vector2i(-1, 0), null)
		var neighbor_nxny: Chunk = grid._chunks.get(chunk_i + Vector2i(-1, -1), null)
		
		var type_polygons: Dictionary[int, Variant] # Dictionary[int, Array[PackedVector2Array]]
		
		for i: int in cell_types.size():
			var type := cell_types[i]
			
			if type == 0:
				continue
			
			@warning_ignore("integer_division")
			var pos := Vector2i(i % CHUNK_SIZE.x, i / CHUNK_SIZE.x)
			
			# +------------>
			# |  e2 --- e3
			# |  |   p   |
			# |  e1 --- e0
			# V
			var e0 = cell_vertices[i]
			var e1 = \
				cell_vertices[i - 1] if pos.x > 0 \
				else neighbor_nx.cell_vertices[i + CHUNK_SIZE.x - 1] - Vector2(CHUNK_SIZE.x, 0.0) if neighbor_nx \
				else Vector2(pos) + Vector2(-0.5, 0.5)
			var e2 = \
				cell_vertices[i - CHUNK_SIZE.x - 1] if pos.x > 0 and pos.y > 0 \
				else neighbor_nx.cell_vertices[i - 1] - Vector2(CHUNK_SIZE.x, 0.0) if pos.y > 0 and neighbor_nx \
				else neighbor_ny.cell_vertices[(CHUNK_SIZE.y - 1) * CHUNK_SIZE.x + i - 1] - Vector2(0.0, CHUNK_SIZE.y) if pos.x > 0 and neighbor_ny \
				else neighbor_nxny.cell_vertices[CHUNK_SIZE.y * CHUNK_SIZE.x - 1] - Vector2(CHUNK_SIZE) if neighbor_nxny \
				else Vector2(pos) + Vector2(-0.5, -0.5)
			var e3 = \
				cell_vertices[i - CHUNK_SIZE.x] if pos.y > 0 \
				else neighbor_ny.cell_vertices[(CHUNK_SIZE.y - 1) * CHUNK_SIZE.x + i] - Vector2(0.0, CHUNK_SIZE.y) if neighbor_ny \
				else Vector2(pos) + Vector2(0.5, -0.5)
			
			if type not in type_polygons:
				var polygons: Array[PackedVector2Array]
				type_polygons[type] = polygons
			
			# Must be this winding order, counter-clockwise per Geometry2D.is_polygon_clockwise().
			type_polygons[type].append(PackedVector2Array([e0, e1, e2, e3]))
		
		for type: int in type_polygons:
			var polygons: Array[PackedVector2Array] = type_polygons[type]
			
			# https://github.com/godotengine/godot/pull/104407
			#if grid.optimize_convex_polygons:
				#polygons = Geometry2D.decompose_many_polygons_in_convex(Geometry2D.merge_many_polygons(polygons))
			
			surface_types.append(type)
			surface_polygons.append(polygons)
