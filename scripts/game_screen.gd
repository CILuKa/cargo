extends Control
class_name GameScreen

## 游戏界面脚本：管理对话显示、背景/角色/选项/剧情树

# ---------- 背景与角色 ----------
@onready var background: TextureRect = $Background
@onready var character_layer: Control = $CharacterLayer
@onready var char_left: TextureRect = $CharacterLayer/CharLeft
@onready var char_center: TextureRect = $CharacterLayer/CharCenter
@onready var char_right: TextureRect = $CharacterLayer/CharRight

# ---------- 对话 ----------
@onready var dialogue_box: Panel = $DialogueBox
@onready var speaker_label: Label = $DialogueBox/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $DialogueBox/DialogueText
@onready var choice_container: VBoxContainer = $ChoiceContainer

# ---------- 点击推进 ----------
@onready var click_catcher: Control = $ClickCatcher

# ---------- 剧情树 ----------
@onready var story_tree_panel: Panel = $StoryTreePanel
@onready var tree_close_button: Button = $StoryTreePanel/TopBar/TreeCloseButton
@onready var tree_hbox: HBoxContainer = $StoryTreePanel/ScrollContainer/TreeHBox

# ---------- 底部工具栏 ----------
@onready var log_button: Button = $BottomBar/LogButton
@onready var save_button: Button = $BottomBar/SaveButton
@onready var load_button: Button = $BottomBar/LoadButton
@onready var story_tree_button: Button = $BottomBar/StoryTreeButton
@onready var auto_button: Button = $BottomBar/AutoButton
@onready var settings_button: Button = $BottomBar/SettingsButton
@onready var skip_button: Button = $BottomBar/SkipButton
@onready var tactics_button: Button = $BottomBar/TacticsButton

# ---------- 弹窗 ----------
@onready var save_load_window: Control = $SaveLoadWindow
@onready var log_window: Control = $LogWindow
@onready var settings_window: Control = $SettingsWindow
@onready var tactics_board: Control = $TacticsBoard

# ---------- 状态 ----------
var _dialogue_manager: DialogueManager
var _is_typing: bool = false
var _typewriter_tween: Tween
var _full_text: String = ""
var _is_auto_mode: bool = false
var _is_skip_mode: bool = false
var _auto_timer: Timer
var _choice_buttons: Array = []
var _is_restoring: bool = false

# 角色位置映射（TextureRect 静态立绘）
var _char_nodes: Dictionary = {}
# 角色动画节点映射（AnimatedSprite2D 动态立绘，与 _char_nodes 互斥使用）
var _char_anim_nodes: Dictionary = {}
# 角色位置类型追踪："texture" 或 "animated"
var _char_type: Dictionary = {}
# 角色立绘缓存（表情 -> 纹理路径）
var _char_expressions: Dictionary = {}
# 对话历史记录 [{speaker, text, node_id}]
var _dialogue_history: Array = []
# 剧情节点记录（包含选项节点和战斗节点，按时间顺序）
var _story_events: Array = []

# ---------- 手机 UI ----------
var _phone_button: Button
var _phone_overlay: Control          # 点击外部关闭的遮罩
var _phone_container: Panel          # 手机外壳
var _phone_tween: Tween
var _is_phone_open: bool = false
var _phone_screen_content: Control   # 手机屏幕内容区域（可替换为不同页面）
var _skill_card_nodes: Dictionary = {}  # 技能卡片引用 {skill_id: Button}，用于原地更新选中状态

# ---------- 生命周期 ----------
func _ready():
	_char_nodes = {
		"left": char_left,
		"center": char_center,
		"right": char_right
	}

	# 创建 DialogueManager
	_dialogue_manager = DialogueManager.new()
	add_child(_dialogue_manager)

	# 连接信号
	_dialogue_manager.dialogue_updated.connect(_on_dialogue_updated)
	_dialogue_manager.choices_shown.connect(_on_choices_shown)
	_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)
	_dialogue_manager.node_changed.connect(_on_node_changed)
	_dialogue_manager.battle_started.connect(_on_battle_started)

	# 连接战棋棋盘的战斗结果信号
	tactics_board.battle_result.connect(_on_battle_result)

	click_catcher.gui_input.connect(_on_click_catcher_gui_input)

	# 底部按钮
	log_button.pressed.connect(_on_log_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	story_tree_button.pressed.connect(_on_story_tree_pressed)
	auto_button.pressed.connect(_on_auto_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	tactics_button.pressed.connect(_on_tactics_pressed)

	# 初始化角色类型：默认全部为静态 TextureRect
	_char_type = {
		"left": "texture",
		"center": "texture",
		"right": "texture"
	}

	# 存档/读档窗口信号
	save_load_window.save_requested.connect(_on_save_to_slot)
	save_load_window.load_requested.connect(_on_load_from_slot)
	save_load_window.delete_requested.connect(_on_delete_slot)

	# 剧情树关闭按钮
	tree_close_button.pressed.connect(_on_tree_close_pressed)

	# 自动模式定时器
	_auto_timer = Timer.new()
	_auto_timer.wait_time = 2.0
	_auto_timer.one_shot = true
	_auto_timer.timeout.connect(_on_auto_timer_timeout)
	add_child(_auto_timer)

	# 隐藏弹窗
	save_load_window.visible = false
	log_window.visible = false
	settings_window.visible = false
	tactics_board.visible = false
	story_tree_panel.visible = false

	# 创建手机 UI
	_create_phone_ui()

	_update_auto_button_style()
	_update_skip_button_style()

	# 检查是否有待加载的存档数据（从主菜单"继续游戏"进入）
	var pending_data = GameState.get_flag("__pending_load_data", null)
	if pending_data != null:
		GameState.set_flag("__pending_load_data", null)  # 清除标记
		_load_story_and_restore(pending_data)
	else:
		start_story()


# =============================================================================
# 角色立绘系统 — 支持静态 TextureRect 和动态 AnimatedSprite2D
# =============================================================================

## 将指定位置的角色设置为 AnimatedSprite2D（动态立绘）
## 调用后该位置将使用动画精灵替代静态 TextureRect
## @param pos: 位置 "left" / "center" / "right"
## @param sprite_frames: SpriteFrames 资源（含 idle、talk 等动画）
## @param default_anim: 默认播放的动画名（如 "idle"）
func setup_animated_character(pos: String, sprite_frames: SpriteFrames, default_anim: String = "idle") -> AnimatedSprite2D:
	# 隐藏原有的 TextureRect
	var tex_rect: TextureRect = _char_nodes.get(pos)
	if tex_rect:
		tex_rect.visible = false

	# 移除旧的 AnimatedSprite2D（如果存在）
	var old_anim: AnimatedSprite2D = _char_anim_nodes.get(pos)
	if old_anim:
		old_anim.queue_free()

	# 创建新的 AnimatedSprite2D 并复用 TextureRect 的布局
	var anim := AnimatedSprite2D.new()
	anim.name = "CharAnim_" + pos
	anim.sprite_frames = sprite_frames
	anim.visible = false                      # 初始隐藏，等待 show 指令

	# 复制 TextureRect 的位置和尺寸作为初始参考
	if tex_rect:
		anim.position = tex_rect.position
		anim.scale = tex_rect.scale
		# 根据 TextureRect 尺寸计算合适的缩放
		if sprite_frames.get_frame_count(default_anim) > 0:
			var frame_tex: Texture2D = sprite_frames.get_frame_texture(default_anim, 0)
			if frame_tex:
				var target_size: Vector2 = tex_rect.size
				var tex_size: Vector2 = frame_tex.get_size()
				if tex_size.x > 0 and tex_size.y > 0:
					anim.scale = target_size / tex_size

	character_layer.add_child(anim)

	# 记录
	_char_anim_nodes[pos] = anim
	_char_type[pos] = "animated"

	# 播放默认动画
	if sprite_frames.has_animation(default_anim):
		anim.animation = default_anim
		anim.play()

	return anim


## 获取指定位置的当前角色节点（自动判断类型）
func _get_char_node(pos: String) -> Node2D:
	if _char_type.get(pos) == "animated":
		return _char_anim_nodes.get(pos)
	return _char_nodes.get(pos)


## 判断指定位置是否使用动画立绘
func _is_char_animated(pos: String) -> bool:
	return _char_type.get(pos) == "animated"


## 加载剧本并恢复存档状态
func _load_story_and_restore(data: Dictionary):
	if not _dialogue_manager.load_story("res://data/story_chapter1.json"):
		dialogue_text.text = "[center]剧本加载失败，请检查 data/story_chapter1.json[/center]"
		return

	_restore_from_save(data)

## 开始剧本
func start_story():
	GameState.reset()
	if _dialogue_manager.load_story("res://data/story_chapter1.json"):
		_dialogue_manager.start_story()
	else:
		dialogue_text.text = "[center]剧本加载失败，请检查 data/story_chapter1.json[/center]"

# ---------- 点击推进 ----------
func _on_click_catcher_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_dialogue()

func _advance_dialogue():
	if _is_typing:
		# 打字中 → 立即显示全部文字
		_skip_typing()
		return

	if choice_container.visible:
		# 有选项时不允许点击推进
		return

	_dialogue_manager.advance()

func _skip_typing():
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	dialogue_text.visible_characters = -1
	_is_typing = false
	_try_auto_advance()

# ---------- 对话更新 ----------
func _on_dialogue_updated(data: Dictionary):
	# 隐藏选项
	_clear_choices()

	# 更新说话人
	var speaker = data.get("speaker", "")
	speaker_label.text = speaker

	# 更新对话文本
	_full_text = data.get("text", "")
	dialogue_text.text = _full_text

	# 记录对话历史（选项节点的提示文本不记录，避免回溯时重复；恢复存档时不记录，避免重复）
	if not data.has("choices") or data["choices"].size() == 0:
		if not _is_restoring:
			_dialogue_history.append({
				"speaker": speaker,
				"text": _full_text,
				"node_id": _dialogue_manager.get_current_node_id()
			})

	# 执行效果
	_execute_node_effects(data.get("effects", []))

	# 打字机效果
	_start_typewriter()

func _start_typewriter():
	_is_typing = true
	dialogue_text.visible_characters = 0

	var duration = _full_text.length() * 0.03
	if _is_skip_mode:
		duration = _full_text.length() * 0.005

	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()

	_typewriter_tween = create_tween()
	_typewriter_tween.tween_property(
		dialogue_text, "visible_characters",
		_full_text.length(), duration
	)
	_typewriter_tween.finished.connect(_on_typewriter_finished)

func _on_typewriter_finished():
	_is_typing = false
	_try_auto_advance()

func _try_auto_advance():
	if _is_auto_mode and not choice_container.visible:
		_auto_timer.start()

func _on_auto_timer_timeout():
	if _is_auto_mode and not _is_typing and not choice_container.visible:
		_advance_dialogue()

# ---------- 选项 ----------
func _on_choices_shown(choices: Array):
	_clear_choices()
	_choice_buttons.clear()

	# 禁用 ClickCatcher，让选项按钮可点击
	click_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 记录当前选项节点到剧情节点日志（含快照）
	var current_id = _dialogue_manager.get_current_node_id()
	var node_data = _dialogue_manager.get_current_node()
	_story_events.append({
		"type": "choice",
		"node_id": current_id,
		"story_file": _dialogue_manager.get_story_file_path(),
		"text": node_data.get("text", ""),
		"choices": choices,
		"selected_index": -1,
		"snapshot": {
			"flags": GameState.flags.duplicate(true),
			"history_length": _dialogue_history.size(),
			"story_events_length": _story_events.size(),  # 当前项之前的长度
			"story_file": _dialogue_manager.get_story_file_path()
		}
	})

	for i in range(choices.size()):
		var choice = choices[i]
		var btn = Button.new()
		btn.text = choice["text"]
		btn.add_theme_font_size_override("font_size", 22)
		btn.custom_minimum_size = Vector2(400, 50)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		choice_container.add_child(btn)
		_choice_buttons.append(btn)

	choice_container.visible = true

func _on_choice_pressed(index: int):
	# 记录用户的选择（找到最后一个 choice 类型的事件）
	for i in range(_story_events.size() - 1, -1, -1):
		if _story_events[i]["type"] == "choice":
			_story_events[i]["selected_index"] = index
			break

	_clear_choices()
	_dialogue_manager.select_choice(index)

func _clear_choices():
	for child in choice_container.get_children():
		child.queue_free()
	_choice_buttons.clear()
	choice_container.visible = false
	# 恢复 ClickCatcher
	click_catcher.mouse_filter = Control.MOUSE_FILTER_STOP

# ---------- 效果执行 ----------
func _execute_node_effects(effects: Array):
	for effect in effects:
		_execute_single_effect(effect)

func _execute_single_effect(effect: Dictionary):
	var type = effect.get("type", "")

	match type:
		"bg":
			_change_background(effect.get("file", ""), effect.get("transition", "fade"))
		"char":
			_update_character(effect)
		"battle":
			# 战斗效果由 DialogueManager 通过 battle_started 信号处理
			pass
		"set_flag":
			# 已在 DialogueManager 中处理
			pass
		"bgm":
			# 音频系统占位
			print("[BGM] " + effect.get("file", ""))
		"sfx":
			# 音频系统占位
			print("[SFX] " + effect.get("file", ""))

func _change_background(file_path: String, transition: String):
	if file_path.is_empty():
		return

	var tex = _load_texture(file_path)
	if tex == null:
		return

	match transition:
		"fade":
			# 简易淡入：先设置纹理再 Tween modulate
			background.texture = tex
			background.modulate.a = 0.0
			var t = create_tween()
			t.tween_property(background, "modulate:a", 1.0, 0.5)
		_:
			background.texture = tex

func _update_character(effect: Dictionary):
	var char_id = effect.get("id", "")
	var action = effect.get("action", "")
	var pos = effect.get("pos", "center")
	var expression = effect.get("expression", "normal")

	var is_anim := _is_char_animated(pos)

	# --- 静态 TextureRect 分支 ---
	if not is_anim:
		var node: TextureRect = _char_nodes.get(pos, char_center)

		match action:
			"show":
				var tex = _load_texture("res://assets/characters/" + char_id + "_" + expression + ".png")
				if tex:
					node.texture = tex
				node.visible = true
				node.modulate = Color.WHITE
				# 入场动画
				node.modulate.a = 0.0
				var t = create_tween()
				t.tween_property(node, "modulate:a", 1.0, 0.3)

			"hide":
				node.visible = false

			"highlight":
				for key in _char_nodes:
					var n = _char_nodes[key]
					if n.visible and _char_type.get(key) != "animated":
						n.modulate = Color(1, 1, 1, 1)
				node.modulate = Color(1, 1, 1, 1)

			"dim":
				node.modulate = Color(0.5, 0.5, 0.5, 1)

			"expression":
				var tex = _load_texture("res://assets/characters/" + char_id + "_" + expression + ".png")
				if tex:
					node.texture = tex

			_:
				# 默认：显示角色
				var tex = _load_texture("res://assets/characters/" + char_id + "_" + expression + ".png")
				if tex:
					node.texture = tex
				node.visible = true
		return

	# --- 动画 AnimatedSprite2D 分支 ---
	var anim_node: AnimatedSprite2D = _char_anim_nodes.get(pos)
	if anim_node == null:
		return

	match action:
		"show":
			# 切换到指定表情动画（如 "idle_normal", "idle_happy"）
			_switch_char_animation(anim_node, expression)
			anim_node.visible = true
			anim_node.modulate = Color.WHITE
			# 入场动画
			anim_node.modulate.a = 0.0
			var t = create_tween()
			t.tween_property(anim_node, "modulate:a", 1.0, 0.3)

		"hide":
			anim_node.visible = false
			anim_node.stop()

		"highlight":
			# 高亮：恢复所有动画角色为正常颜色，再高亮当前
			for key in _char_anim_nodes:
				var n = _char_anim_nodes[key]
				if n.visible:
					n.modulate = Color(1, 1, 1, 1)
			anim_node.modulate = Color(1, 1, 1, 1)

		"dim":
			anim_node.modulate = Color(0.5, 0.5, 0.5, 1)

		"expression", "anim":
			# 切换到指定表情/动画
			_switch_char_animation(anim_node, expression)

		_:
			# 默认行为：显示角色
			_switch_char_animation(anim_node, expression)
			anim_node.visible = true


## 切换 AnimatedSprite2D 角色动画
## 根据 expression 名查找对应的动画（如 "normal" → "idle_normal"，"happy" → "idle_happy"）
func _switch_char_animation(anim_node: AnimatedSprite2D, expression: String) -> void:
	var sf: SpriteFrames = anim_node.sprite_frames
	if sf == null:
		return

	# 尝试精确匹配 expression 名
	if sf.has_animation(expression):
		anim_node.animation = expression
		anim_node.play()
		return

	# 尝试 "idle_<expression>" 格式
	var idle_name := "idle_" + expression
	if sf.has_animation(idle_name):
		anim_node.animation = idle_name
		anim_node.play()
		return

	# 尝试 "talk_<expression>" 格式
	var talk_name := "talk_" + expression
	if sf.has_animation(talk_name):
		anim_node.animation = talk_name
		anim_node.play()
		return

	# 回退到 "idle" 动画
	if sf.has_animation("idle"):
		anim_node.animation = "idle"
		anim_node.play()

func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		# 资源不存在时静默失败（开发阶段没有图片是正常的）
		return null
	var res = load(path)
	if res is Texture2D:
		return res
	return null

# ---------- 剧情树 ----------
func _on_story_tree_pressed():
	story_tree_panel.visible = true
	_refresh_tree()

func _on_tree_close_pressed():
	story_tree_panel.visible = false

func _on_node_changed(_node_id: String):
	if story_tree_panel.visible:
		_refresh_tree()

	# 检查当前节点是否有战斗效果，记录到剧情事件
	var node_data = _dialogue_manager.get_current_node()
	if not node_data.is_empty():
		for effect in node_data.get("effects", []):
			if effect.get("type") == "battle":
				_story_events.append({
					"type": "battle",
					"node_id": _node_id,
					"story_file": _dialogue_manager.get_story_file_path(),
					"battle_name": effect.get("name", "战斗"),
					"win_next": effect.get("win_next", ""),
					"lose_next": effect.get("lose_next", ""),
					"result": null,  # null = 未结算, "win" / "lose"
					"snapshot": {
						"flags": GameState.flags.duplicate(true),
						"history_length": _dialogue_history.size(),
						"story_events_length": _story_events.size(),
						"story_file": _dialogue_manager.get_story_file_path()
					}
				})
				break

func _refresh_tree():
	# 清空旧内容
	for child in tree_hbox.get_children():
		child.queue_free()

	# 只显示选项节点和战斗节点
	if _story_events.is_empty():
		var hint = Label.new()
		hint.text = "尚未遇到剧情分支节点"
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		tree_hbox.add_child(hint)
		return

	# 横向展示每个事件节点（选项 / 战斗）
	for i in range(_story_events.size()):
		var event = _story_events[i]

		# 节点之间的箭头
		if i > 0:
			var arrow = Label.new()
			arrow.text = "  →  "
			arrow.add_theme_font_size_override("font_size", 20)
			arrow.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tree_hbox.add_child(arrow)

		# 创建卡片
		var card: Panel
		if event["type"] == "choice":
			card = _create_choice_tree_card(event, i)
		else:
			card = _create_battle_tree_card(event, i)
		card.gui_input.connect(_on_tree_card_clicked.bind(i))
		tree_hbox.add_child(card)

# ---------- 剧情树回溯 ----------
func _on_tree_card_clicked(event: InputEvent, index: int):
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if index < 0 or index >= _story_events.size():
		return

	var entry = _story_events[index]
	if entry["type"] == "choice":
		_jump_to_choice(index)
	elif entry["type"] == "battle":
		_jump_to_battle(index)

func _jump_to_choice(index: int):
	if index < 0 or index >= _story_events.size():
		return

	var log_entry = _story_events[index]
	if log_entry.get("type") != "choice":
		return

	var snapshot = log_entry.get("snapshot", {})
	if snapshot.is_empty():
		return

	# 1. 恢复 GameState
	GameState.flags = snapshot["flags"].duplicate(true)

	# 2. 截断对话历史
	var hist_len = snapshot["history_length"]
	_dialogue_history = _dialogue_history.slice(0, hist_len)

	# 3. 截断剧情事件日志
	var log_len = snapshot["story_events_length"]
	_story_events = _story_events.slice(0, log_len)

	# 4. 清除当前选项
	_clear_choices()

	# 5. 跳转到目标节点
	_dialogue_manager.jump_to_node(log_entry["node_id"], snapshot.get("story_file", ""))

	# 6. 关闭剧情树
	story_tree_panel.visible = false


## 点击战斗节点：跳回到发生战斗之前的剧情节点，可重新体验战斗
func _jump_to_battle(index: int):
	if index < 0 or index >= _story_events.size():
		return

	var entry = _story_events[index]
	if entry.get("type") != "battle":
		return

	# 恢复战斗发生前的快照状态
	var snapshot = entry.get("snapshot", {})
	if snapshot.is_empty():
		return

	# 如果当前正在战斗中，先关闭战棋棋盘、恢复对话 UI
	if entry.get("result") == null:
		tactics_board.visible = false
		_restore_dialogue_ui()

	GameState.flags = snapshot["flags"].duplicate(true)
	_dialogue_history = _dialogue_history.slice(0, snapshot["history_length"])
	_story_events = _story_events.slice(0, snapshot["story_events_length"])
	_clear_choices()

	# 跳转到触发战斗的节点，让玩家重新体验战斗
	_dialogue_manager.jump_to_node(entry["node_id"], snapshot.get("story_file", ""))
	story_tree_panel.visible = false


func _create_choice_tree_card(log_entry: Dictionary, index: int) -> Panel:
	var card = Panel.new()
	card.custom_minimum_size = Vector2(220, 100)
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # 可接收点击

	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# 节点 ID
	var id_label = Label.new()
	id_label.text = "#" + str(log_entry["node_id"])
	id_label.add_theme_font_size_override("font_size", 11)
	id_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(id_label)

	# 问题文本
	var text = log_entry["text"]
	if text.length() > 18:
		text = text.substr(0, 18) + "…"
	var text_label = Label.new()
	text_label.text = text
	text_label.add_theme_font_size_override("font_size", 13)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(text_label)

	# 选项列表
	var choices = log_entry["choices"]
	var selected = log_entry["selected_index"]
	for j in range(choices.size()):
		var choice_text = choices[j]["text"]
		if choice_text.length() > 15:
			choice_text = choice_text.substr(0, 15) + "…"

		var choice_label = Label.new()
		var prefix = "○ "
		if j == selected:
			prefix = "● "
			choice_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		elif selected >= 0:
			choice_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		choice_label.text = prefix + choice_text
		choice_label.add_theme_font_size_override("font_size", 11)
		choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(choice_label)

	# 颜色标记：最后一个事件 = 当前节点
	var is_current = (index == _story_events.size() - 1)
	if is_current:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.6, 0.2, 0.8)
		style.set_corner_radius_all(8)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.3, 1.0, 0.3)
		card.add_theme_stylebox_override("panel", style)
	else:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25, 0.8)
		style.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", style)

	return card


## 创建战斗节点卡片
func _create_battle_tree_card(event: Dictionary, index: int) -> Panel:
	var card = Panel.new()
	card.custom_minimum_size = Vector2(180, 90)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# 战斗图标
	var icon_label = Label.new()
	icon_label.text = "⚔"
	icon_label.add_theme_font_size_override("font_size", 22)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(icon_label)

	# 战斗名称
	var name_label = Label.new()
	name_label.text = event["battle_name"]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# 战斗结果
	var result = event.get("result")
	if result == "win":
		var result_label = Label.new()
		result_label.text = "✓ 胜利"
		result_label.add_theme_font_size_override("font_size", 11)
		result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(result_label)
	elif result == "lose":
		var result_label = Label.new()
		result_label.text = "✗ 失败"
		result_label.add_theme_font_size_override("font_size", 11)
		result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(result_label)
	else:
		var result_label = Label.new()
		result_label.text = "进行中…"
		result_label.add_theme_font_size_override("font_size", 11)
		result_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
		result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(result_label)

	# 颜色标记
	var is_current = (index == _story_events.size() - 1)
	if is_current:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.6, 0.4, 0.1, 0.8)
		style.set_corner_radius_all(8)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(1.0, 0.7, 0.3)
		card.add_theme_stylebox_override("panel", style)
	else:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25, 0.8)
		style.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", style)

	return card


# ---------- 对话结束 ----------
func _on_dialogue_ended():
	dialogue_text.text = "[center]— 本章结束 —[/center]"
	speaker_label.text = ""
	_clear_choices()

# ---------- 底部工具栏 ----------
func _on_log_pressed():
	log_window.visible = true
	_populate_log_window()

func _populate_log_window():
	var log_text_widget: RichTextLabel = log_window.get_node("Panel/VBoxContainer/LogText")
	var bbcode = ""
	for entry in _dialogue_history:
		var speaker = entry["speaker"]
		var text = entry["text"]
		if not speaker.is_empty():
			bbcode += "[color=yellow]" + speaker + "[/color]\n"
		bbcode += text + "\n\n"
	if bbcode.is_empty():
		bbcode = "暂无对话记录"
	log_text_widget.text = bbcode

func _on_save_pressed():
	save_load_window.set_mode("save")
	save_load_window.visible = true

func _on_load_pressed():
	save_load_window.set_mode("load")
	save_load_window.visible = true

# ---------- 存档/读档逻辑 ----------

func _get_save_data() -> Dictionary:
	var preview = ""
	if _dialogue_history.size() > 0:
		var last = _dialogue_history[-1]
		preview = last.get("speaker", "") + ": " + last.get("text", "")
		if preview.length() > 30:
			preview = preview.substr(0, 30) + "…"

	var time_dict = Time.get_datetime_dict_from_system()
	var timestamp = "%04d-%02d-%02d %02d:%02d:%02d" % [
		time_dict["year"], time_dict["month"], time_dict["day"],
		time_dict["hour"], time_dict["minute"], time_dict["second"]
	]

	return {
		"timestamp": timestamp,
		"preview": preview,
		"current_node_id": _dialogue_manager.get_current_node_id(),
		"story_file_path": _dialogue_manager.get_story_file_path(),
		"flags": GameState.flags.duplicate(true),
		"dialogue_history": _dialogue_history.duplicate(true),
		"story_events": _story_events.duplicate(true),
		"character_roster": CharacterRoster.get_save_data()
	}

func _on_save_to_slot(slot_index: int):
	var data = _get_save_data()
	SaveManager.save_to_slot(slot_index, data)
	save_load_window.set_mode("save")  # 刷新显示
	print("[存档] 已保存到槽位 %d" % (slot_index + 1))

func _on_load_from_slot(slot_index: int):
	var data = SaveManager.load_from_slot(slot_index)
	if data.is_empty():
		return

	_restore_from_save(data)
	save_load_window.visible = false
	print("[读档] 从槽位 %d 读取" % (slot_index + 1))

func _restore_from_save(data: Dictionary):
	# 1. 恢复 GameState
	GameState.flags = data["flags"].duplicate(true)

	# 2. 恢复角色技能配置
	CharacterRoster.restore_from_save(data.get("character_roster", {}))

	# 3. 恢复对话历史
	_dialogue_history = data["dialogue_history"].duplicate(true)
	_story_events = data["story_events"].duplicate(true)

	# 4. 清除当前选项
	_clear_choices()

	# 5. 跳转到存档节点（标记恢复中，避免重复记录历史）
	_is_restoring = true
	_dialogue_manager.jump_to_node(data["current_node_id"], data.get("story_file_path", ""))
	_is_restoring = false

func _on_delete_slot(slot_index: int):
	SaveManager.delete_slot(slot_index)

func _on_settings_pressed():
	settings_window.visible = true

func _on_tactics_pressed():
	tactics_board.visible = true


# =============================================================================
# 战斗系统 — 剧情触发战斗 → 战斗结果 → 剧情分支
# =============================================================================

## 剧情触发 battle 效果后，DialogueManager 发出 battle_started 信号
## 此方法加载战斗配置并显示战棋棋盘
func _on_battle_started(config_path: String):
	# 加载战斗配置（背景、单位、格子颜色等）
	tactics_board.load_battle_config(config_path)
	# 启动回合制战斗
	tactics_board.start_battle()
	# 隐藏对话 UI，全屏进入战斗
	_hide_dialogue_ui()
	# 显示战棋棋盘弹窗
	tactics_board.visible = true


## 战斗结束，用户点击结果按钮后，TacticsBoard 发出 battle_result 信号
## 此方法将结果反馈给 DialogueManager 以跳转到对应剧情分支
## @param result: 结构化结果字典 {"type": "win"|"lose", "branch": "分支ID", "next": "目标节点"}
func _on_battle_result(result: Dictionary):
	# 更新战斗事件的结果
	var result_str: String = result.get("type", "") + ":" + result.get("branch", "")
	for i in range(_story_events.size() - 1, -1, -1):
		if _story_events[i]["type"] == "battle" and _story_events[i]["result"] == null:
			_story_events[i]["result"] = result_str
			break

	# 隐藏战棋棋盘
	tactics_board.visible = false
	# 恢复对话 UI
	_restore_dialogue_ui()
	# 将结构化结果传递给 DialogueManager
	_dialogue_manager.resolve_battle_result(result)

## 隐藏对话 UI（进入战斗时）
func _hide_dialogue_ui():
	dialogue_box.visible = false
	character_layer.visible = false
	choice_container.visible = false
	click_catcher.visible = false
	$BottomBar.visible = false
	background.visible = false
	_phone_button.visible = false

## 恢复对话 UI（战斗结束后）
func _restore_dialogue_ui():
	dialogue_box.visible = true
	character_layer.visible = true
	click_catcher.visible = true
	_phone_button.visible = true
	$BottomBar.visible = true
	background.visible = true

func _on_auto_pressed():
	_is_auto_mode = not _is_auto_mode
	if _is_auto_mode:
		_is_skip_mode = false
		_update_skip_button_style()
		_try_auto_advance()
	_update_auto_button_style()

func _on_skip_pressed():
	_is_skip_mode = not _is_skip_mode
	if _is_skip_mode:
		_is_auto_mode = false
		_update_auto_button_style()
	_update_skip_button_style()

func _update_auto_button_style():
	if _is_auto_mode:
		auto_button.text = "自动: ON"
		auto_button.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		auto_button.text = "自动"
		auto_button.remove_theme_color_override("font_color")

func _update_skip_button_style():
	if _is_skip_mode:
		skip_button.text = "快进: ON"
		skip_button.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		skip_button.text = "快进"
		skip_button.remove_theme_color_override("font_color")


# =============================================================================
# 手机 UI
# =============================================================================

func _create_phone_ui() -> void:
	# --- 手机按钮（右侧中上位置） ---
	_phone_button = Button.new()
	_phone_button.text = "📱"
	_phone_button.add_theme_font_size_override("font_size", 28)
	_phone_button.custom_minimum_size = Vector2(50, 50)
	_phone_button.flat = true
	_phone_button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_phone_button.pressed.connect(_on_phone_button_pressed)
	_phone_button.anchor_left = 1.0
	_phone_button.anchor_top = 0.3
	_phone_button.anchor_right = 1.0
	_phone_button.anchor_bottom = 0.3
	_phone_button.offset_left = -65.0
	_phone_button.offset_top = -25.0
	_phone_button.offset_right = -15.0
	_phone_button.offset_bottom = 25.0
	add_child(_phone_button)

	# --- 遮罩（点击外部关闭） ---
	_phone_overlay = Control.new()
	_phone_overlay.visible = false
	_phone_overlay.anchor_right = 1.0
	_phone_overlay.anchor_bottom = 1.0
	_phone_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_phone_overlay.gui_input.connect(_on_phone_overlay_gui_input)
	add_child(_phone_overlay)

	# --- 手机外壳 ---
	_phone_container = Panel.new()
	_phone_container.visible = false
	_phone_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_phone_container.custom_minimum_size = Vector2(300, 560)

	# 手机外壳样式
	var phone_style := StyleBoxFlat.new()
	phone_style.bg_color = Color(0.08, 0.08, 0.1, 1.0)
	phone_style.set_corner_radius_all(24)
	phone_style.border_width_left = 3
	phone_style.border_width_right = 3
	phone_style.border_width_top = 3
	phone_style.border_width_bottom = 3
	phone_style.border_color = Color(0.3, 0.3, 0.35)
	_phone_container.add_theme_stylebox_override("panel", phone_style)

	_phone_overlay.add_child(_phone_container)

	# --- 手机屏幕区域 ---
	var screen_margin := MarginContainer.new()
	screen_margin.add_theme_constant_override("margin_left", 15)
	screen_margin.add_theme_constant_override("margin_top", 35)
	screen_margin.add_theme_constant_override("margin_right", 15)
	screen_margin.add_theme_constant_override("margin_bottom", 15)
	screen_margin.anchor_right = 1.0
	screen_margin.anchor_bottom = 1.0
	_phone_container.add_child(screen_margin)

	var screen_vbox := VBoxContainer.new()
	screen_vbox.add_theme_constant_override("separation", 12)
	screen_margin.add_child(screen_vbox)

	# --- 状态栏 ---
	var status_bar := HBoxContainer.new()
	status_bar.add_theme_constant_override("separation", 8)
	var time_label := Label.new()
	time_label.text = "9:41"
	time_label.add_theme_font_size_override("font_size", 13)
	time_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	status_bar.add_child(time_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(spacer)
	var battery := Label.new()
	battery.text = "🔋"
	battery.add_theme_font_size_override("font_size", 12)
	status_bar.add_child(battery)
	screen_vbox.add_child(status_bar)

	# --- 屏幕内容区域（可替换） ---
	_phone_screen_content = Control.new()
	_phone_screen_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_screen_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_vbox.add_child(_phone_screen_content)

	# --- 底部占位 ---
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_vbox.add_child(bottom_spacer)

	# --- 底部 Home 指示条 ---
	var home_bar := Panel.new()
	home_bar.custom_minimum_size = Vector2(0, 5)
	var home_style := StyleBoxFlat.new()
	home_style.bg_color = Color(0.7, 0.7, 0.7, 0.6)
	home_style.set_corner_radius_all(3)
	home_bar.add_theme_stylebox_override("panel", home_style)
	home_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen_vbox.add_child(home_bar)

	# 默认显示主页
	_show_phone_home()


## 显示手机主页（正常 App 网格布局）
func _show_phone_home() -> void:
	_clear_phone_content()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	_phone_screen_content.add_child(vbox)

	# 顶部留白
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(top_spacer)

	# App 网格
	var app_grid := GridContainer.new()
	app_grid.columns = 4
	app_grid.add_theme_constant_override("h_separation", 14)
	app_grid.add_theme_constant_override("v_separation", 18)
	vbox.add_child(app_grid)

	# 技能管理 App（唯一 App）
	var app_item := _create_app_item("⚔️", "技能管理")
	app_item.pressed.connect(_show_skill_select)
	app_grid.add_child(app_item)


## 创建一个 App 项（图标 + 标签，模拟手机桌面图标）
func _create_app_item(icon_text: String, app_name: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(58, 58)
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	# 图标背景
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.28, 0.28, 0.38, 0.85)
	icon_style.set_corner_radius_all(13)
	btn.add_theme_stylebox_override("normal", icon_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.35, 0.35, 0.45, 0.85)
	hover_style.set_corner_radius_all(13)
	btn.add_theme_stylebox_override("hover", hover_style)

	# 图标内部布局：图标 + 名称
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	inner.anchor_right = 1.0
	inner.anchor_bottom = 1.0
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(inner)

	var icon_label := Label.new()
	icon_label.text = icon_text
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(icon_label)

	var name_label := Label.new()
	name_label.text = app_name
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_label)

	return btn


## 显示技能选择页面
func _show_skill_select() -> void:
	_clear_phone_content()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	_phone_screen_content.add_child(vbox)

	# 顶部导航栏
	var nav_bar := HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 8)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.flat = true
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	back_btn.pressed.connect(_show_phone_home)
	nav_bar.add_child(back_btn)

	var nav_spacer := Control.new()
	nav_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(nav_spacer)

	var title := Label.new()
	title.text = "技能管理"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	nav_bar.add_child(title)

	vbox.add_child(nav_bar)

	# 分隔线
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 提示文字
	var hint := Label.new()
	hint.text = "选择战斗中使用的技能\n（每回合只能使用一个技能）"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	# 从 CharacterRoster 获取角色可用技能
	var character_id := "knight"  # 当前固定为骑士，后续可扩展
	var available_skills: Array = CharacterRoster.get_available_skills(character_id)
	var equipped_skill: String = CharacterRoster.get_equipped_skill(character_id)

	# 加载技能信息
	var skill_info := _load_skill_info()

	# 技能列表
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var skill_list := VBoxContainer.new()
	skill_list.add_theme_constant_override("separation", 8)
	skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(skill_list)

	for skill_id in available_skills:
		var info: Dictionary = skill_info.get(skill_id, {"name": skill_id, "desc": ""})
		var is_selected: bool = (skill_id == equipped_skill)

		var card := _create_skill_card(info["name"], info["desc"], is_selected)
		card.pressed.connect(_on_skill_selected.bind(skill_id))
		skill_list.add_child(card)
		_skill_card_nodes[skill_id] = card


## 创建技能卡片
func _create_skill_card(skill_name: String, skill_desc: String, is_selected: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	_apply_skill_card_style(btn, is_selected)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	btn.add_child(hbox)

	# 选中标记
	var check_mark := Label.new()
	check_mark.name = "CheckMark"
	check_mark.text = "●" if is_selected else "○"
	check_mark.add_theme_font_size_override("font_size", 14)
	check_mark.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0) if is_selected else Color(0.5, 0.5, 0.5))
	hbox.add_child(check_mark)

	# 技能名称和描述
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = skill_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	info_vbox.add_child(name_label)

	if not skill_desc.is_empty():
		var desc_label := Label.new()
		desc_label.text = skill_desc
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(0, 0)
		info_vbox.add_child(desc_label)

	return btn


## 更新技能卡片的选中样式（不重建页面，保留滚动位置）
func _apply_skill_card_style(btn: Button, is_selected: bool) -> void:
	var style := StyleBoxFlat.new()
	if is_selected:
		style.bg_color = Color(0.2, 0.5, 0.8, 0.6)
		style.border_color = Color(0.4, 0.7, 1.0)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
	else:
		style.bg_color = Color(0.2, 0.2, 0.3, 0.5)
		style.border_color = Color(0.3, 0.3, 0.4)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
	style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.3, 0.3, 0.4, 0.6)
	hover_style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover_style)


## 加载所有技能的名称和描述（自动扫描 skills 文件夹）
func _load_skill_info() -> Dictionary:
	var result: Dictionary = {}
	var skill_dir := "res://data/skills/"

	var dir := DirAccess.open(skill_dir)
	if dir == null:
		push_error("GameScreen: 无法打开技能目录: " + skill_dir)
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path: String = skill_dir + file_name
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				file_name = dir.get_next()
				continue
			var json := JSON.new()
			var err := json.parse(file.get_as_text())
			if err == OK:
				var data: Dictionary = json.data
				result[data.get("id", "")] = {
					"name": data.get("name", ""),
					"desc": data.get("description", "")
				}
		file_name = dir.get_next()
	dir.list_dir_end()

	return result


## 点击技能卡片时选择技能（原地更新卡片样式，不重建页面）
func _on_skill_selected(skill_id: String) -> void:
	CharacterRoster.set_equipped_skill("knight", skill_id)

	# 遍历所有卡片，原地更新样式
	for sid in _skill_card_nodes:
		var card: Button = _skill_card_nodes[sid]
		var is_selected: bool = (sid == skill_id)
		_apply_skill_card_style(card, is_selected)

		# 更新选中标记
		var hbox := card.get_child(0) as HBoxContainer
		if hbox:
			var check_mark := hbox.get_node_or_null("CheckMark") as Label
			if check_mark:
				check_mark.text = "●" if is_selected else "○"
				check_mark.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0) if is_selected else Color(0.5, 0.5, 0.5))


## 清空手机屏幕内容
func _clear_phone_content() -> void:
	_skill_card_nodes.clear()
	for child in _phone_screen_content.get_children():
		child.queue_free()


func _on_phone_button_pressed() -> void:
	if _is_phone_open:
		return
	_is_phone_open = true

	# 每次打开默认显示主页
	_show_phone_home()

	# 设置手机初始位置（屏幕右侧外）
	_phone_container.anchor_left = 0.5
	_phone_container.anchor_top = 0.5
	_phone_container.anchor_right = 0.5
	_phone_container.anchor_bottom = 0.5
	_phone_container.offset_left = self.size.x - 150.0
	_phone_container.offset_top = -280.0
	_phone_container.offset_right = self.size.x + 150.0
	_phone_container.offset_bottom = 280.0

	_phone_overlay.visible = true
	_phone_container.visible = true

	# 淡入遮罩
	_phone_overlay.modulate.a = 0.0

	# 动画滑入
	if _phone_tween and _phone_tween.is_valid():
		_phone_tween.kill()
	_phone_tween = create_tween()
	_phone_tween.set_parallel(true)
	_phone_tween.set_ease(Tween.EASE_OUT)
	_phone_tween.set_trans(Tween.TRANS_CUBIC)
	_phone_tween.tween_property(_phone_container, "offset_left", -150.0, 0.4)
	_phone_tween.tween_property(_phone_container, "offset_right", 150.0, 0.4)
	_phone_tween.tween_property(_phone_overlay, "modulate:a", 0.5, 0.4)


func _on_phone_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_phone()


func _close_phone() -> void:
	if not _is_phone_open:
		return
	_is_phone_open = false

	if _phone_tween and _phone_tween.is_valid():
		_phone_tween.kill()
	_phone_tween = create_tween()
	_phone_tween.set_parallel(true)
	_phone_tween.set_ease(Tween.EASE_IN)
	_phone_tween.set_trans(Tween.TRANS_CUBIC)
	_phone_tween.tween_property(_phone_container, "offset_top", self.size.y + 280.0, 0.35)
	_phone_tween.tween_property(_phone_container, "offset_bottom", self.size.y + 840.0, 0.35)
	_phone_tween.tween_property(_phone_overlay, "modulate:a", 0.0, 0.35)
	_phone_tween.finished.connect(_on_phone_closed)


func _on_phone_closed() -> void:
	_phone_overlay.visible = false
	_phone_container.visible = false
