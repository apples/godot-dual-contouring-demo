extends Node
class_name QEFSolver

static var positions: PackedVector2Array
static var normals: PackedVector2Array

static func best_fit(
	left_edge_position: float, left_edge_normal: Vector2,
	bottom_edge_position: float, bottom_edge_normal: Vector2, 
	right_edge_position: float, right_edge_normal: Vector2,
	top_edge_position: float, top_edge_normal: Vector2,
) -> Vector2:
	positions.clear()
	normals.clear()
	
	if left_edge_position != -1.0:
		positions.append(Vector2(0.0, left_edge_position))
		normals.append(left_edge_normal)
	if bottom_edge_position != -1.0:
		positions.append(Vector2(bottom_edge_position, 0.0))
		normals.append(bottom_edge_normal)
	if right_edge_position != -1.0:
		positions.append(Vector2(1.0, right_edge_position))
		normals.append(right_edge_normal)
	if top_edge_position != -1.0:
		positions.append(Vector2(top_edge_position, 1.0))
		normals.append(top_edge_normal)
	
	if positions.size() == 0:
		return Vector2(0.5, 0.5)
	
	if positions.size() == 1:
		var closest := Geometry2D.get_closest_point_to_segment_uncapped(
			Vector2(0.5, 0.5),
			positions[0],
			positions[0] + Vector2(normals[0].y, normals[0].x),
		)
		return closest.clampf(0.0, 1.0)
	
	if positions.size() == 2:
		var intersects = Geometry2D.line_intersects_line(positions[0], normals[0].orthogonal(), positions[1], normals[1].orthogonal())
		if intersects == null or not Rect2(Vector2.ZERO, Vector2.ONE).has_point(intersects):
			return (positions[0] + positions[1]) / 2.0
		return intersects
	
	if positions.size() == 3:
		return (positions[0] + positions[1] + positions[2]) / 3.0
	
	if positions.size() == 4:
		return (positions[0] + positions[1] + positions[2] + positions[3]) / 4.0
	
	return Vector2(0.5, 0.5)
