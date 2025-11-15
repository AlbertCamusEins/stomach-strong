@tool

class_name HarvestableItem extends Resource

@export var harvestable_name: String
@export var texture: Texture2D
@export var item_to_harvest: Item
@export var max_harvests: int = 3
@export var amount_per_harvest: int = 1
