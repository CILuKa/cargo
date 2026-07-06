extends Control
class_name SettingsWindow

## 设置窗口脚本：显示设置面板（内容留空）

@onready var close_x_button: Button = $Panel/CloseXButton
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton
@onready var return_to_menu_button: Button = $Panel/VBoxContainer/ReturnToMenuButton

func _ready():
	close_x_button.pressed.connect(_on_close_pressed)
	close_button.pressed.connect(_on_close_pressed)
	return_to_menu_button.pressed.connect(_on_return_to_menu_pressed)

func _on_close_pressed():
	visible = false

func _on_return_to_menu_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
