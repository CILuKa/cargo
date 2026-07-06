extends Control
class_name SaveLoadWindow

## 存档/读档窗口：10 个槽位，覆盖确认，支持保存/读取/删除

signal save_requested(slot_index: int)
signal load_requested(slot_index: int)
signal delete_requested(slot_index: int)

@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var slots_container: VBoxContainer = $Panel/VBoxContainer/SaveSlots/SlotsContainer
@onready var close_x_button: Button = $Panel/CloseXButton
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var current_mode: String = "save"  # "save" 或 "load"
var _confirm_popup: Control = null
var _pending_slot: int = -1

func _ready():
	close_x_button.pressed.connect(_on_close_pressed)
	close_button.pressed.connect(_on_close_pressed)

func set_mode(mode: String):
	current_mode = mode
	if mode == "save":
		title_label.text = "保存游戏"
	else:
		title_label.text = "读取存档"
	_refresh_slots()

## 刷新所有槽位显示
func _refresh_slots():
	# 清空旧内容
	for child in slots_container.get_children():
		child.queue_free()

	for i in range(SaveManager.MAX_SLOTS):
		var info = SaveManager.get_slot_info(i)
		var slot = _create_slot_row(i, info)
		slots_container.add_child(slot)

## 创建单个槽位行
func _create_slot_row(index: int, info: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 44)

	# 槽位编号
	var num_label = Label.new()
	num_label.text = "[%02d]" % (index + 1)
	num_label.add_theme_font_size_override("font_size", 18)
	num_label.custom_minimum_size = Vector2(50, 0)
	num_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(num_label)

	# 预览信息
	var info_text = ""
	if info["isEmpty"]:
		info_text = "— 空存档 —"
	else:
		info_text = info["timestamp"] + "  " + info["preview"]
		if info_text.length() > 50:
			info_text = info_text.substr(0, 50) + "…"

	var info_label = Label.new()
	info_label.text = info_text
	info_label.add_theme_font_size_override("font_size", 15)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.clip_text = true
	if info["isEmpty"]:
		info_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(info_label)

	# 操作按钮
	if current_mode == "save":
		var save_btn = Button.new()
		save_btn.text = "保存"
		save_btn.add_theme_font_size_override("font_size", 16)
		save_btn.custom_minimum_size = Vector2(80, 0)
		save_btn.pressed.connect(_on_save_slot.bind(index))
		row.add_child(save_btn)

		# 删除按钮（仅非空槽位显示）
		if not info["isEmpty"]:
			var del_btn = Button.new()
			del_btn.text = "删除"
			del_btn.add_theme_font_size_override("font_size", 16)
			del_btn.custom_minimum_size = Vector2(80, 0)
			del_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			del_btn.pressed.connect(_on_delete_slot.bind(index))
			row.add_child(del_btn)

	else:  # load 模式
		if not info["isEmpty"]:
			var load_btn = Button.new()
			load_btn.text = "读取"
			load_btn.add_theme_font_size_override("font_size", 16)
			load_btn.custom_minimum_size = Vector2(80, 0)
			load_btn.pressed.connect(_on_load_slot.bind(index))
			row.add_child(load_btn)

			var del_btn = Button.new()
			del_btn.text = "删除"
			del_btn.add_theme_font_size_override("font_size", 16)
			del_btn.custom_minimum_size = Vector2(80, 0)
			del_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			del_btn.pressed.connect(_on_delete_slot.bind(index))
			row.add_child(del_btn)

	return row

# ---------- 操作 ----------

func _on_save_slot(index: int):
	if SaveManager.has_save(index):
		# 已有存档，弹出确认覆盖对话框
		_show_confirm_overwrite(index)
	else:
		save_requested.emit(index)

func _on_load_slot(index: int):
	load_requested.emit(index)

func _on_delete_slot(index: int):
	delete_requested.emit(index)
	_refresh_slots()

# ---------- 覆盖确认对话框 ----------

func _show_confirm_overwrite(index: int):
	_pending_slot = index

	_confirm_popup = Control.new()
	_confirm_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_popup.mouse_filter = Control.MOUSE_FILTER_STOP

	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.5)
	_confirm_popup.add_child(overlay)

	# 面板：手动居中定位
	var panel = Panel.new()
	panel.size = Vector2(400, 180)
	_confirm_popup.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var msg = Label.new()
	msg.text = "槽位 %d 已有存档，是否覆盖？" % (index + 1)
	msg.add_theme_font_size_override("font_size", 18)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var confirm_btn = Button.new()
	confirm_btn.text = "确认覆盖"
	confirm_btn.add_theme_font_size_override("font_size", 18)
	confirm_btn.custom_minimum_size = Vector2(140, 50)
	confirm_btn.pressed.connect(_on_confirm_overwrite)
	btn_row.add_child(confirm_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.custom_minimum_size = Vector2(100, 50)
	cancel_btn.pressed.connect(_on_cancel_overwrite)
	btn_row.add_child(cancel_btn)

	# 添加到场景根节点，手动居中
	get_tree().root.add_child(_confirm_popup)
	_center_confirm_panel(panel)
	# 窗口大小变化时重新居中（Window 用 size_changed 信号）
	get_tree().root.size_changed.connect(_center_confirm_panel.bind(panel))

func _center_confirm_panel(panel: Panel):
	if panel and is_instance_valid(panel):
		var viewport_size = get_viewport().get_visible_rect().size
		panel.position = (viewport_size - panel.size) / 2.0

func _on_confirm_overwrite():
	save_requested.emit(_pending_slot)
	_close_confirm()

func _on_cancel_overwrite():
	_close_confirm()

func _close_confirm():
	if _confirm_popup:
		_confirm_popup.queue_free()
		_confirm_popup = null
	_pending_slot = -1

# ---------- 关闭 ----------

func _on_close_pressed():
	visible = false
