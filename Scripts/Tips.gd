extends CanvasLayer

# 引用场景中的节点
@onready var check_box: CheckBox = $Panel/VBoxContainer/CheckBox
@onready var button: Button = $Panel/VBoxContainer/Button

# ----------------- 核心逻辑 -----------------
# 我们需要一个变量来追踪 CheckBox 是否“曾经”被按下过。
# 初始值为 false，因为游戏一开始它肯定没被按过。
var has_been_checked_before: bool = false
# ---------------------------------------------


func _ready() -> void:
	# 游戏开始时，按钮必须是禁用的，因为 CheckBox 还没被按过。
	button.disabled = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true


# 这是连接 toggled 信号后自动生成的函数
# 每当 CheckBox 的状态改变时，这个函数就会被调用
func _on_check_box_toggled(button_pressed: bool) -> void:
	# "button_pressed" 是 CheckBox 的新状态 (true=选中, false=未选中)
	
	# 首先，检查 CheckBox 是否被选中了。
	# 如果是，那么我们就达到了“曾经被按下过”的条件。
	if button_pressed:
		# 将我们的追踪变量设为 true，并且永远不再改回 false。
		# 这样系统就“记住”了它被按过了。
		has_been_checked_before = true
	
	# 现在，根据整蛊逻辑来更新按钮的状态
	update_button_state()


# 我们可以把更新按钮状态的逻辑单独写成一个函数，让代码更清晰
func update_button_state() -> void:
	# 整蛊条件：
	# 1. 必须曾经被按下过 (has_been_checked_before == true)
	# 2. 并且，当前必须是未选中状态 (check_box.button_pressed == false)
	
	# 同时满足这两个条件时，按钮才可用。
	if has_been_checked_before and not check_box.button_pressed:
		# 条件满足，启用按钮
		button.disabled = false
		print("按钮已解锁！") # 调试信息
	else:
		# 其他任何情况（从未按过、或者当前是选中状态），都禁用按钮
		button.disabled = true
		print("按钮被锁定。") # 调试信息


func _on_button_pressed() -> void:
	self.visible = false
	get_tree().paused = false
