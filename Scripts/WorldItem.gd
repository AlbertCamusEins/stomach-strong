# scripts/WorldItem.gd
class_name WorldItem extends Area2D

@export var item: Item
@onready var prompt_label: Label = $Label
@onready var sprite = $Sprite2D

func _ready():
	prompt_label.hide()
	prompt_label.text = item.item_name
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	sprite.texture = item.icon
	sprite.scale = Vector2(1, 1)

func _on_body_entered(body):
	# 检查进入的是否是玩家角色
	if body is CharacterBody2D:
		prompt_label.show()

func _on_body_exited(body):
	if body is CharacterBody2D:
		prompt_label.hide()

func _unhandled_input(event: InputEvent):
	# 检查玩家是否按下了交互键，并且有角色在区域内
	if prompt_label.visible and event.is_action_pressed("ui_accepted"):
		if item:
			print("捡起地上物品：" + item.item_name)
			InventoryManager.add_item(item,1)
			self.queue_free()
