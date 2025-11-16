@abstract
extends RefCounted
class_name IsolinesBrush
## Abstract class representing a brush to be used with an IsolinesGrid.

## The center point in grid coordinates of the brush.
var center: Vector2

## Computes the boudning rect for this brush around its center.
@abstract func get_bounds() -> Rect2

## Gets the type the brush will apply at cell_pos. Returns -1 if outside the brush shape.
## When a brush is applied, will be called exactly once for each cell determined by [method get_bounds].
@abstract func get_type(cell_pos: Vector2i) -> int

## Gets the edge position of the brush shape between two adjacent cells.
## Returns a tuple array, the first element is the edge's position, the second element is the normal.
## If an empty array is returned, the edge data will not be modified.
@abstract func get_edge(cell_pos: Vector2i, next_cell_pos: Vector2i) -> PackedVector2Array
