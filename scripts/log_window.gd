extends Control
class_name LogWindow

## 对话日志窗口脚本：查看历史对话记录

@onready var close_x_button: Button = $Panel/CloseXButton
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton
@onready var log_text: RichTextLabel = $Panel/VBoxContainer/LogText

func _ready():
	close_x_button.pressed.connect(_on_close_pressed)
	close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed():
	visible = false
