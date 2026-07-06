extends Control
class_name MainMenu

## 主菜单脚本：处理新游戏、继续游戏、设置按钮

@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var continue_button: Button = $VBoxContainer/ContinueButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var settings_window: Control = $SettingsWindow
@onready var save_load_window: SaveLoadWindow = $SaveLoadWindow

func _ready():
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	# 存档/读档窗口信号
	save_load_window.load_requested.connect(_on_load_game)
	save_load_window.delete_requested.connect(_on_delete_slot)

	# 初始隐藏所有弹窗
	settings_window.visible = false
	save_load_window.visible = false

func _on_new_game_pressed():
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/game_screen.tscn")

func _on_continue_pressed():
	save_load_window.set_mode("load")
	save_load_window.visible = true

func _on_load_game(slot_index: int):
	var data = SaveManager.load_from_slot(slot_index)
	if data.is_empty():
		return

	# 存储到 GameState 以便 GameScreen 读取
	GameState.set_flag("__pending_load_data", data)
	get_tree().change_scene_to_file("res://scenes/game_screen.tscn")

func _on_delete_slot(slot_index: int):
	SaveManager.delete_slot(slot_index)
	save_load_window.set_mode("load")  # 刷新显示

func _on_settings_pressed():
	settings_window.visible = true
