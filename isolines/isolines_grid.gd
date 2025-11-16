@abstract
@tool
extends Node2D
class_name IsolinesGrid
## Implements a simple terrain grid designed for contouring.
## Each grid cell has a single terrain type assigned to it.
## Cells are modified by applying brushes.
##
## The terrain type 0 is special, it use used to indicate empty cells and brushes that erase.
##
## Grid data is broken up into chunks, determined by the implementation's chunk size.
##
## When handling area RIDs for collision detection,
## use [method Isolines.get_area_grid] and [method IsolinesGrid.get_area_type] to detect area types.

## Emitted when the chunk at chunk_i is updated and contains data (but may not contain surfaces).
## Will be deferred after the call to apply_brush.
signal chunk_updated(chunk_i: Vector2)

## Emitted when the chunk at chunk_i is removed because it contains no data.
## Will be deferred after the call to apply_brush.
signal chunk_removed(chunk_i: Vector2)

## Emitted when a brush is applied.
## Will be deferred after the call to apply_brush.
@warning_ignore("unused_signal")
signal brush_applied(
	cell_positions: PackedVector2Array,
	previous_types: PackedInt32Array,
	current_types: PackedInt32Array
)

static var _area_rid_to_chunk: Dictionary[RID, ChunkInstance]

## The type mixer to use when applying brushes. If null, brushes will simply overwrite cells.
@export var mixer: IsolinesMixer
## The material to use when a type has no specific material.
@export var default_material: Material
## Maps types to materials.
@export var materials: Dictionary[int, Material]
## If true, generated meshes will have a UV channel that matches cell coordinates.
@export var generate_uvs: bool = true
## Scale applied to generated UVs.
@export var uv_scale: Vector2 = Vector2.ONE / 16.0
## If true, generates collision areas.
@export var collision_enabled: bool = true
## Collision layer to use for all areas.
@export_flags_2d_physics var collision_layer: int = 1
## Collision mask to use for all areas.
@export_flags_2d_physics var collision_mask: int = 1
## If true, draws a wireframe of the grid and surface polygons.
@export var debug_draw: bool = false
## If true and debug_draw is true, draws surface edge normals.
@export var debug_draw_normals: bool = false

var _chunk_instances: Dictionary[Vector2i, ChunkInstance]

## Gets the IsolinesGrid responsible for the area.
## If the area is not owned by an IsolinesGrid, returns null.
static func get_area_grid(area_rid: RID) -> IsolinesGrid:
	if area_rid in _area_rid_to_chunk:
		return _area_rid_to_chunk[area_rid].get_parent()
	return null

## Gets the surface type of an IsolinesGrid area.
## If the area is not owned by an IsolinesGrid, returns -1.
static func get_area_type(area_rid: RID) -> int:
	if area_rid in _area_rid_to_chunk:
		return _area_rid_to_chunk[area_rid].area_types.get(area_rid, -1)
	return -1

## Gets the type of a specific cell. Returns 0 if a cell's chunk does not exist.
@abstract func get_cell_type(pos: Vector2i) -> int
## Applies the brush to the grid. Ensure the brush's [member IsolinesBrush.center] is set.
@abstract func apply_brush(brush: IsolinesBrush) -> void
## Gets the size of a chunk.
@abstract func get_chunk_size() -> Vector2i
## Gets a list of the identifiers of all loaded chunks. Elements should be interpreted as Vector2i.
@abstract func get_chunks() -> PackedVector2Array
## Gets the number of surfaces of all types in a chunk.
@abstract func get_chunk_surface_count(chunk_i: Vector2i) -> int
## Gets the type of a chunk surface.
@abstract func get_chunk_surface_type(chunk_i: Vector2i, surface_i: int) -> int
## Gets the polygons of a chunk surface. May not always be convex.
@abstract func get_chunk_surface_polygons(chunk_i: Vector2i, surface_i: int) -> Array # Array[PackedVector2Array]

func _init() -> void:
	# Connect to this grid's own chunk signals to handle rendering and physics.
	chunk_updated.connect(_on_chunk_updated)
	chunk_removed.connect(_on_chunk_removed)

func _enter_tree() -> void:
	# Regenerate chunk nodes, because chunk data may already exist.
	for chunk_i in get_chunks():
		_on_chunk_updated(chunk_i)

func _exit_tree() -> void:
	for chunk in _chunk_instances.values():
		chunk.queue_free()
	_chunk_instances.clear()

func _on_chunk_updated(chunk_i: Vector2i) -> void:
	# If not in the tree, no chunk nodes will be instantiated.
	# Will be called again next time this grid is added to the tree.
	if not is_inside_tree():
		return
	
	var chunk_info: ChunkInstance = _chunk_instances.get(chunk_i, null)
	
	if not chunk_info:
		chunk_info = ChunkInstance.new()
		chunk_info.position = Vector2(get_chunk_size() * chunk_i)
		chunk_info.chunk_i = chunk_i
		_chunk_instances[chunk_i] = chunk_info
		add_child(chunk_info, false, Node.INTERNAL_MODE_BACK)
	else:
		chunk_info.rebuild()

func _on_chunk_removed(chunk_i: Vector2i) -> void:
	if chunk_i in _chunk_instances:
		_chunk_instances[chunk_i].queue_free()
		_chunk_instances.erase(chunk_i)

## Implements per-chunk rendering and physics.
## Not intended to be used directly. Relies on being a child of an IsolinesGrid.
class ChunkInstance extends Node2D:
	## This chunk's identifier.
	var chunk_i: Vector2i
	
	## Maps types to canvas item RIDs. Each type has only one canvas item for all surfaces in this chunk.
	var type_canvas_items: Dictionary[int, RID]
	
	## Maps types to meshes. Each type has only one mesh for all surfaces in this chunk.
	## Each canvas item should have a mesh.
	var type_meshes: Dictionary[int, ArrayMesh]
	
	## Maps types to physics areas. Each type has only one area for all surfaces in this chunk.
	var type_areas: Dictionary[int, RID]
	
	## Maps area RIDs to surface types.
	var area_types: Dictionary[RID, int]
	
	## Maps types to debug canvas item RIDs.
	var type_debug_canvas_items: Dictionary[int, RID]
	
	func _enter_tree() -> void:
		rebuild()
	
	func _exit_tree() -> void:
		for rid in type_canvas_items.values():
			RenderingServer.free_rid(rid)
		type_canvas_items.clear()
		
		for rid in type_debug_canvas_items.values():
			RenderingServer.free_rid(rid)
		type_debug_canvas_items.clear()
		
		for area_rid: RID in type_areas.values():
			for i in range(PhysicsServer2D.area_get_shape_count(area_rid) - 1, -1, -1):
				var shape_rid := PhysicsServer2D.area_get_shape(area_rid, i)
				PhysicsServer2D.area_remove_shape(area_rid, i)
				PhysicsServer2D.free_rid(shape_rid)
			IsolinesGrid._area_rid_to_chunk.erase(area_rid)
			PhysicsServer2D.free_rid(area_rid)
		type_areas.clear()
		area_types.clear()
	
	func rebuild() -> void:
		var grid: IsolinesGrid = get_parent()
		
		var chunk_size := Vector2(grid.get_chunk_size())
		
		# Keep track of unused types so we can hide their canvas items later.
		var unused_types := type_canvas_items.keys()
		
		# Process surfaces, adding their meshes to the matching canvas item.
		for surface_i in grid.get_chunk_surface_count(chunk_i):
			var type := grid.get_chunk_surface_type(chunk_i, surface_i)
			var polygons := grid.get_chunk_surface_polygons(chunk_i, surface_i)
			
			unused_types.erase(type)
			
			var canvas_item: RID = type_canvas_items.get(type, RID())
			var mesh: ArrayMesh = type_meshes.get(type, null)
			
			if not canvas_item:
				canvas_item = RenderingServer.canvas_item_create()
				type_canvas_items[type] = canvas_item
				RenderingServer.canvas_item_set_parent(canvas_item, get_canvas_item())
				
				var type_material: Material = grid.materials.get(type, grid.default_material)
				if type_material:
					RenderingServer.canvas_item_set_material(canvas_item, type_material)
				else:
					push_error("IsolinesGrid: No material found! (Please set default_material.)")
				
				# Ensure that we have a mesh for the canvas item.
				if not mesh:
					mesh = ArrayMesh.new()
					type_meshes[type] = mesh
			
			RenderingServer.canvas_item_clear(canvas_item)
			
			assert(mesh)
			
			# Generate visual mesh.
			
			var vertex_array: PackedVector2Array
			var index_array: PackedInt32Array
			
			for polygon in polygons:
				var indices := Geometry2D.triangulate_polygon(polygon)
				var index_array_start := index_array.size()
				var index_offset := vertex_array.size()
				vertex_array.append_array(polygon)
				index_array.append_array(indices)
				for i in range(index_array_start, index_array.size()):
					index_array[i] += index_offset
			
			var mesh_arrays: Array
			mesh_arrays.resize(Mesh.ARRAY_MAX)
			mesh_arrays[Mesh.ARRAY_VERTEX] = vertex_array
			mesh_arrays[Mesh.ARRAY_INDEX] = index_array
			
			if grid.generate_uvs:
				var uv_array: PackedVector2Array
				uv_array.resize(vertex_array.size())
				for i: int in uv_array.size():
					uv_array[i] = grid.uv_scale * (chunk_size * Vector2(chunk_i) + vertex_array[i])
				mesh_arrays[Mesh.ARRAY_TEX_UV] = uv_array
			
			mesh.clear_surfaces()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
			
			RenderingServer.canvas_item_add_mesh(canvas_item, mesh.get_rid())
			
			# Debug drawing.
			
			if grid.debug_draw and OS.is_debug_build():
				var dbg_canvas_item: RID = type_debug_canvas_items.get(type, RID())
				if not dbg_canvas_item:
					dbg_canvas_item = RenderingServer.canvas_item_create()
					type_debug_canvas_items[type] = dbg_canvas_item
					RenderingServer.canvas_item_set_parent(dbg_canvas_item, canvas_item)
					RenderingServer.canvas_item_set_use_parent_material(dbg_canvas_item, false)
					RenderingServer.canvas_item_set_z_index(dbg_canvas_item, 50)
				RenderingServer.canvas_item_clear(dbg_canvas_item)
				for y in grid.get_chunk_size().y:
					for x in grid.get_chunk_size().x:
						var c: Color = [Color.WHITE, Color.DARK_CYAN, Color.RED, Color.MAGENTA][grid.get_cell_type(Vector2(chunk_i * grid.get_chunk_size()) + Vector2(x, y))]
						RenderingServer.canvas_item_add_circle(dbg_canvas_item, Vector2(x, y), 0.05, c)
				for polygon in polygons:
					var points = PackedVector2Array()
					for i in polygon.size():
						points.append(polygon[i])
						points.append(polygon[(i+1) % polygon.size()])
					var colors = PackedColorArray()
					@warning_ignore("integer_division")
					colors.resize(points.size() / 2)
					colors.fill(Color.WHITE)
					RenderingServer.canvas_item_add_multiline(dbg_canvas_item, points, colors)
				if grid.debug_draw_normals:
					var ggrid := grid as DualContourIsolinesGrid
					var crossings := ggrid.get_chunk_edge_crossings(chunk_i)
					for i in range(0, crossings.size(), 2):
						RenderingServer.canvas_item_add_line(
							dbg_canvas_item,
							crossings[i], crossings[i] + crossings[i + 1],
							Color.MAGENTA
						)
			
			# Canvas item might have previously been unused and hidden.
			RenderingServer.canvas_item_set_visible(canvas_item, true)
		
		# Hide unused canvas items and clear their meshes.
		for type in unused_types:
			var canvas_item: RID = type_canvas_items[type]
			RenderingServer.canvas_item_set_visible(canvas_item, false)
			
			var mesh: ArrayMesh = type_meshes.get(type, null)
			if mesh:
				mesh.clear_surfaces()
		
		# Skip physics generation.
		
		if not grid.collision_enabled:
			return
		
		# Physics.
		
		var global_xform := grid.global_transform.translated_local(chunk_size * Vector2(chunk_i))
		
		var shape_pool: Array[RID]
		
		# Clear all areas, but save shapes in a temporary pool for reuse.
		for type in type_areas:
			var area_rid := type_areas[type]
			for i in PhysicsServer2D.area_get_shape_count(area_rid):
				shape_pool.append(PhysicsServer2D.area_get_shape(area_rid, i))
			PhysicsServer2D.area_clear_shapes(area_rid)
		
		# Process surfaces, adding their polygons to the matching area.
		for surface_i in grid.get_chunk_surface_count(chunk_i):
			var type := grid.get_chunk_surface_type(chunk_i, surface_i)
			var polygons := grid.get_chunk_surface_polygons(chunk_i, surface_i)
			
			var area_rid: RID = type_areas.get(type, RID())
			if not area_rid:
				area_rid = PhysicsServer2D.area_create()
				type_areas[type] = area_rid
				area_types[area_rid] = type
				IsolinesGrid._area_rid_to_chunk[area_rid] = self
				
				PhysicsServer2D.area_set_space(area_rid, grid.get_viewport().world_2d.space)
				PhysicsServer2D.area_set_transform(area_rid, global_xform)
				PhysicsServer2D.area_set_collision_layer(area_rid, grid.collision_layer)
				PhysicsServer2D.area_set_collision_mask(area_rid, grid.collision_mask)
				PhysicsServer2D.area_set_monitorable(area_rid, true)
				
				# This is where an Area2D would implement entered/exited signals.
				#PhysicsServer2D.area_set_monitor_callback(area_rid, func (status: int, body_rid: RID, instance_id: int, body_shape_idx: int, self_shape_idx: int):
					#print("area_monitor_callback(%s, %s, %s, %s, %s)" % [status, body_rid, instance_id, body_shape_idx, self_shape_idx])
				#)
			
			for i in polygons.size():
				var polygon: PackedVector2Array = polygons[i]
				var shape_rid: RID
				if not shape_pool.is_empty():
					shape_rid = shape_pool.pop_back()
				else:
					shape_rid = PhysicsServer2D.convex_polygon_shape_create()
				PhysicsServer2D.shape_set_data(shape_rid, polygon)
				PhysicsServer2D.area_add_shape(area_rid, shape_rid)
		
		# Must free unused shapes, as otherwise they will be leaked.
		for rid in shape_pool:
			PhysicsServer2D.free_rid(rid)
