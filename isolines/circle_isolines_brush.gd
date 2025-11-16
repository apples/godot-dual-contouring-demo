extends IsolinesBrush
class_name CircleIsolinesBrush

var type: int
var radius: float

func get_bounds() -> Rect2:
	return Rect2(center, Vector2.ZERO).grow(radius)

func get_type(cell_pos: Vector2i) -> int:
	var pos := Vector2(cell_pos)
	var radius2 := radius * radius
	var distance2 := center.distance_squared_to(pos)
	
	if distance2 < radius2:
		return type
	
	return -1

func get_edge(cell_pos: Vector2i, next_cell_pos: Vector2i) -> PackedVector2Array:
	var crossing := Geometry2D.segment_intersects_circle(
		Vector2(cell_pos), Vector2(next_cell_pos),
		center, radius,
	)
	
	if crossing == -1.0:
		return []
	
	var crossing_position := Vector2(cell_pos).lerp(next_cell_pos, crossing)
	var normal := (crossing_position - center).normalized()
	
	return [crossing_position, normal]
