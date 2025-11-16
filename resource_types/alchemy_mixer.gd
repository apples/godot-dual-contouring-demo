extends IsolinesMixer
class_name AlchemyMixer

@export var recipes: Array[AlchemyRecipe] = []

func mix_types(surface_type: int, added_type: int) -> int:
	var recipe_i := recipes.find_custom(func (recipe: AlchemyRecipe):
		return (
			recipe.surface_type == surface_type and recipe.added_type == added_type
			or recipe.symmetrical and recipe.surface_type == added_type and recipe.added_type == surface_type
		)
	)
	
	if recipe_i == -1:
		return added_type
	
	return recipes[recipe_i].result_type
