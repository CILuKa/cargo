@tool
extends Control
class_name MainMenu

## =============================================================================
## 主菜单 — 沉浸式超能力战斗 × 美少女文字冒险
## =============================================================================
##
## 设计风格：
##   - 星际深紫背景 + 浮动能量粒子
##   - 毛玻璃按钮（Glass-morphism）+ 青/洋红发光边框
##   - 标题呼吸动画 + 发光脉冲
##   - 按钮交错入场 + 悬停缩放/发光 + 按压涟漪
##   - iOS/Android 风格平滑过渡
##
## 配色：
##   - 背景深紫:   #0d0221
##   - 主色电光青:  #00e5ff
##   - 辅色心灵洋红: #ff2d95
##   - 文字柔白:    #e8e0f0
##   - 玻璃面板:    rgba(255,255,255,0.06)
## =============================================================================


# =============================================================================
# 导出变量（编辑器中可调）
# =============================================================================

## 游戏标题
@export var game_title: String = "星 痕 共 鸣"
## 游戏副标题
@export var game_subtitle: String = "Stellar Resonance"
## 标题字体大小
@export var title_font_size: int = 64
## 副标题字体大小
@export var subtitle_font_size: int = 22
## 按钮字体大小
@export var button_font_size: int = 20
## 背景图片路径（用户自行设计替换）
@export var background_texture_path: String = ""
## 是否显示版本号
@export var show_version: bool = true


# =============================================================================
# 颜色常量
# =============================================================================

const COLOR_BG := Color(0.051, 0.008, 0.129)     # #0d0221 深紫背景
const COLOR_CYAN := Color(0.0, 0.898, 1.0)        # #00e5ff 电光青
const COLOR_MAGENTA := Color(1.0, 0.176, 0.584)   # #ff2d95 心灵洋红
const COLOR_TEXT := Color(0.91, 0.878, 0.941)     # #e8e0f0 柔白文字
const COLOR_GLASS_BG := Color(1.0, 1.0, 1.0, 0.05)
const COLOR_GLASS_BORDER := Color(1.0, 1.0, 1.0, 0.10)
const COLOR_GLASS_HOVER := Color(1.0, 1.0, 1.0, 0.12)
const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.85)


# =============================================================================
# 节点引用
# =============================================================================

var _background: ColorRect
var _particle_canvas: Control
var _title_label: Label
var _subtitle_label: Label
var _button_container: VBoxContainer
var _version_label: Label
var _overlay: ColorRect

var _btn_new_game: Button
var _btn_continue: Button
var _btn_settings: Button
var _btn_quit: Button

@onready var settings_window: Control = $SettingsWindow
@onready var save_load_window: SaveLoadWindow = $SaveLoadWindow


# =============================================================================
# 粒子系统状态
# =============================================================================

var _particles: Array = []    # {pos: Vector2, size: float, speed: float, alpha: float, color: Color}
const PARTICLE_COUNT := 40


# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		# 编辑器预览
		_build_ui()
		return

	# 运行时初始化
	_build_ui()
	_setup_signals()
	_animate_entrance()


## 构建全部 UI 元素
func _build_ui() -> void:
	_clear_ui()
	_create_background()
	_create_particle_system()
	_create_overlay()
	_create_title()
	_create_buttons()
	_create_footer()


## 清除旧的 UI 节点（编辑器热重载用）
func _clear_ui() -> void:
	for child in get_children():
		if child is ColorRect or child is Label or child is VBoxContainer:
			if child != settings_window and child != save_load_window:
				child.queue_free()
	_background = null
	_particle_canvas = null
	_title_label = null
	_subtitle_label = null
	_button_container = null
	_version_label = null
	_overlay = null


# =============================================================================
# 背景层
# =============================================================================

func _create_background() -> void:
	_background = ColorRect.new()
	_background.name = "Background"
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.color = COLOR_BG
	add_child(_background)
	move_child(_background, 0)

	# 用户自定义背景图（如果路径非空且文件存在）
	if not background_texture_path.is_empty() and ResourceLoader.exists(background_texture_path):
		var tex_rect := TextureRect.new()
		tex_rect.name = "BackgroundTexture"
		tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex_rect.texture = load(background_texture_path)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.modulate = Color(1.0, 1.0, 1.0, 0.5)
		_background.add_child(tex_rect)

	# 顶部渐变暗角
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vignette_mat := ShaderMaterial.new()
	vignette_mat.shader = _create_vignette_shader()
	vignette.material = vignette_mat
	_background.add_child(vignette)


# =============================================================================
# 粒子系统（浮动能量光点）
# =============================================================================

func _create_particle_system() -> void:
	_particle_canvas = Control.new()
	_particle_canvas.name = "ParticleCanvas"
	_particle_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_particle_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_particle_canvas)

	# 初始化粒子
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_particles.clear()

	for i in range(PARTICLE_COUNT):
		var p := {
			"pos": Vector2(
				rng.randf_range(0.0, 1920.0),
				rng.randf_range(0.0, 1080.0)
			),
			"size": rng.randf_range(2.0, 6.0),
			"speed": rng.randf_range(8.0, 25.0),
			"alpha": rng.randf_range(0.15, 0.5),
			"color": COLOR_CYAN if rng.randf() > 0.4 else COLOR_MAGENTA,
			"phase": rng.randf_range(0.0, TAU),
			"wobble": rng.randf_range(0.3, 1.5),
		}
		_particles.append(p)

	if not Engine.is_editor_hint():
		_particle_canvas.draw.connect(_draw_particles)


func _draw_particles() -> void:
	for p in _particles:
		var c := p["color"] as Color
		c.a = p["alpha"]
		_particle_canvas.draw_circle(p["pos"], p["size"], c)
		# 外发光光晕
		var glow := c
		glow.a *= 0.3
		_particle_canvas.draw_circle(p["pos"], p["size"] * 2.5, glow)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _particle_canvas == null:
		return

	var changed := false
	for p in _particles:
		p["pos"].y -= p["speed"] * _delta
		p["pos"].x += sin(Time.get_ticks_msec() * 0.001 * p["wobble"] + p["phase"]) * 15.0 * _delta

		# 超出屏幕时重置到底部
		if p["pos"].y < -10.0:
			p["pos"].y = 1090.0
			p["pos"].x = randf_range(0.0, 1920.0)

		changed = true

	if changed:
		_particle_canvas.queue_redraw()


# =============================================================================
# 暗色遮罩（用于场景过渡）
# =============================================================================

func _create_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "TransitionOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


# =============================================================================
# 标题区
# =============================================================================

func _create_title() -> void:
	# 标题容器
	var title_container := VBoxContainer.new()
	title_container.name = "TitleContainer"
	title_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_container.anchor_left = 0.5
	title_container.anchor_right = 0.5
	title_container.anchor_top = 0.0
	title_container.offset_top = 120
	title_container.offset_left = -300
	title_container.offset_right = 300
	title_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(title_container)

	# 主标题
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = game_title
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", title_font_size)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	# 发光效果：复制一个稍大的 Label 在后面做光晕
	var glow_label := Label.new()
	glow_label.name = "TitleGlow"
	glow_label.text = game_title
	glow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow_label.add_theme_font_size_override("font_size", title_font_size)
	glow_label.add_theme_color_override("font_color", COLOR_CYAN)
	glow_label.modulate.a = 0.35
	glow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 标题容器：先加光晕再加文字（光晕在后方产生发光效果）
	title_container.add_child(glow_label)
	title_container.move_child(glow_label, 0)
	# 把主 Label 放在 glow 下面（后渲染=在上层）
	# 用 CanvasLayer 或 z_index 不行，直接用 Control 的层级顺序
	title_container.add_child(_title_label)

	# 副标题
	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = game_subtitle
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", subtitle_font_size)
	_subtitle_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.7))
	_subtitle_label.modulate.a = 0.7
	subtitle_font_size = subtitle_font_size

	# 标题下方装饰线
	var line := ColorRect.new()
	line.name = "TitleDecorLine"
	line.custom_minimum_size = Vector2(200, 2)
	line.color = COLOR_CYAN
	line.modulate.a = 0.5
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	title_container.add_child(_subtitle_label)
	title_container.add_child(line)


# =============================================================================
# 按钮区（毛玻璃风格）
# =============================================================================

func _create_buttons() -> void:
	_button_container = VBoxContainer.new()
	_button_container.name = "ButtonContainer"
	_button_container.set_anchors_preset(Control.PRESET_CENTER)
	_button_container.anchor_left = 0.5
	_button_container.anchor_right = 0.5
	_button_container.anchor_top = 0.5
	_button_container.anchor_bottom = 0.5
	_button_container.offset_left = -160
	_button_container.offset_top = -60
	_button_container.offset_right = 160
	_button_container.offset_bottom = 60
	_button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_container.add_theme_constant_override("separation", 14)
	add_child(_button_container)

	_btn_new_game = _create_glass_button("新 游 戏", COLOR_CYAN)
	_btn_continue = _create_glass_button("继 续 游 戏", COLOR_MAGENTA)
	_btn_settings = _create_glass_button("设    置", Color(0.7, 0.7, 0.8))
	_btn_quit    = _create_glass_button("离 开 游 戏", Color(0.55, 0.5, 0.6))

	_button_container.add_child(_btn_new_game)
	_button_container.add_child(_btn_continue)
	_button_container.add_child(_btn_settings)
	_button_container.add_child(_btn_quit)


## 创建毛玻璃风格按钮
func _create_glass_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 52)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", button_font_size)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", accent)
	btn.flat = true

	# 按钮元数据：存储主题色供动画使用
	btn.set_meta("accent_color", accent)
	btn.set_meta("entrance_delay", 0.0)

	# --- 正常态：毛玻璃 ---
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = COLOR_GLASS_BG
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = COLOR_GLASS_BORDER
	style_normal.corner_radius_top_left = 12
	style_normal.corner_radius_top_right = 12
	style_normal.corner_radius_bottom_left = 12
	style_normal.corner_radius_bottom_right = 12
	style_normal.content_margin_left = 24
	style_normal.content_margin_right = 24
	style_normal.content_margin_top = 10
	style_normal.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", style_normal)

	# --- 悬停态：微亮 + 主题色边框 ---
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = COLOR_GLASS_HOVER
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(accent.r, accent.g, accent.b, 0.5)
	style_hover.corner_radius_top_left = 12
	style_hover.corner_radius_top_right = 12
	style_hover.corner_radius_bottom_left = 12
	style_hover.corner_radius_bottom_right = 12
	style_hover.content_margin_left = 24
	style_hover.content_margin_right = 24
	style_hover.content_margin_top = 10
	style_hover.content_margin_bottom = 10
	# 悬停发光阴影
	style_hover.shadow_size = 8
	style_hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	style_hover.shadow_offset = Vector2(0, 0)
	btn.add_theme_stylebox_override("hover", style_hover)

	# --- 按压态：暗色 + 缩小 ---
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.15)
	style_pressed.border_width_left = 1
	style_pressed.border_width_right = 1
	style_pressed.border_width_top = 1
	style_pressed.border_width_bottom = 1
	style_pressed.border_color = Color(accent.r, accent.g, accent.b, 0.6)
	style_pressed.corner_radius_top_left = 12
	style_pressed.corner_radius_top_right = 12
	style_pressed.corner_radius_bottom_left = 12
	style_pressed.corner_radius_bottom_right = 12
	style_pressed.content_margin_left = 24
	style_pressed.content_margin_right = 24
	style_pressed.content_margin_top = 10
	style_pressed.content_margin_bottom = 10
	btn.add_theme_stylebox_override("pressed", style_pressed)

	# 悬停/按压动效信号（运行时）
	if not Engine.is_editor_hint():
		btn.mouse_entered.connect(Callable(self, "_on_button_hover").bind(btn))
		btn.mouse_exited.connect(Callable(self, "_on_button_unhover").bind(btn))
		btn.button_down.connect(Callable(self, "_on_button_press").bind(btn))
		btn.button_up.connect(Callable(self, "_on_button_release").bind(btn))

	return btn


# =============================================================================
# 页脚
# =============================================================================

func _create_footer() -> void:
	if not show_version:
		return
	_version_label = Label.new()
	_version_label.name = "VersionLabel"
	_version_label.text = "v0.1.0  ·  StarScript Studio"
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_label.add_theme_font_size_override("font_size", 13)
	_version_label.add_theme_color_override("font_color", Color(0.4, 0.38, 0.45))
	_version_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_version_label.anchor_left = 0.5
	_version_label.anchor_right = 0.5
	_version_label.anchor_bottom = 1.0
	_version_label.offset_bottom = -24
	_version_label.offset_left = -100
	_version_label.offset_right = 100
	add_child(_version_label)


# =============================================================================
# 信号连接
# =============================================================================

func _setup_signals() -> void:
	_btn_new_game.pressed.connect(_on_new_game_pressed)
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)

	save_load_window.load_requested.connect(_on_load_game)
	save_load_window.delete_requested.connect(_on_delete_slot)

	settings_window.visible = false
	save_load_window.visible = false


# =============================================================================
# 入场动画
# =============================================================================

func _animate_entrance() -> void:
	# 初始状态：隐藏所有元素
	_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	_set_title_opacity(0.0)
	_subtitle_label.modulate.a = 0.0

	for btn in [_btn_new_game, _btn_continue, _btn_settings, _btn_quit]:
		(btn as Button).modulate.a = 0.0
		(btn as Button).scale = Vector2(0.9, 0.9)

	# 步骤1: 黑色遮罩淡出 (0.6s)
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", 0.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 步骤2: 标题淡入 + 下移 (0.5s, delay 0.2s)
	tween.tween_callback(_animate_title_in)

	# 步骤3: 按钮交错入场
	tween.tween_callback(func():
		_animate_buttons_in()
	).set_delay(0.45)


func _animate_title_in() -> void:
	var tween := create_tween().set_parallel(true)

	# 光晕标签
	var glow := _title_label.get_parent().get_node_or_null("TitleGlow") as Label
	if glow:
		glow.modulate.a = 0.0
		tween.tween_property(glow, "modulate:a", 0.35, 0.6).set_ease(Tween.EASE_OUT)

	# 主标题淡入
	_set_title_opacity(0.0)
	tween.tween_property(_title_label, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)

	# 副标题淡入
	tween.tween_property(_subtitle_label, "modulate:a", 0.7, 0.4).set_ease(Tween.EASE_OUT)

	# 标题呼吸动画（无限循环）
	var breathe := create_tween().set_loops()
	breathe.tween_property(_title_label, "position:y", _title_label.position.y - 4, 1.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(_title_label, "position:y", _title_label.position.y, 1.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# 光晕呼吸
	if glow:
		var glow_breathe := create_tween().set_loops()
		glow_breathe.tween_property(glow, "modulate:a", 0.5, 2.0)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		glow_breathe.tween_property(glow, "modulate:a", 0.2, 2.0)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _animate_buttons_in() -> void:
	var buttons: Array = [_btn_new_game, _btn_continue, _btn_settings, _btn_quit]
	for i in range(buttons.size()):
		var btn := buttons[i] as Button
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "modulate:a", 1.0, 0.35)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)\
			.set_delay(i * 0.08)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.45)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)\
			.set_delay(i * 0.08)


# =============================================================================
# 按钮动效
# =============================================================================

func _on_button_hover(btn: Button) -> void:
	# 先移除已有的旧光晕（防止重复叠加）
	var old_glow := btn.get_node_or_null("_hover_glow")
	if old_glow:
		old_glow.queue_free()

	# 缩放动效
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.15)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 主题色发光层
	var accent: Color = btn.get_meta("accent_color", COLOR_CYAN) as Color
	var glow_rect := ColorRect.new()
	glow_rect.name = "_hover_glow"
	glow_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_rect.color = Color(accent.r, accent.g, accent.b, 0.08)
	glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(glow_rect)
	btn.move_child(glow_rect, 0)


func _on_button_unhover(btn: Button) -> void:
	# 缩放回正常
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 立即移除光晕（不用 Tween 淡出，避免引用已释放节点）
	var glow := btn.get_node_or_null("_hover_glow")
	if glow:
		glow.queue_free()


func _on_button_press(btn: Button) -> void:
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.08)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)


func _on_button_release(btn: Button) -> void:
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.1)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)


# =============================================================================
# 场景过渡
# =============================================================================

func _transition_to_scene(scene_path: String) -> void:
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", 1.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(scene_path)
	)


# =============================================================================
# 按钮回调
# =============================================================================

func _on_new_game_pressed() -> void:
	GameState.reset()
	_transition_to_scene("res://scenes/game_screen.tscn")


func _on_continue_pressed() -> void:
	save_load_window.set_mode("load")
	save_load_window.visible = true
	# 弹窗入场动画
	save_load_window.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(save_load_window, "modulate:a", 1.0, 0.2)


func _on_settings_pressed() -> void:
	settings_window.visible = true
	settings_window.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(settings_window, "modulate:a", 1.0, 0.2)


func _on_quit_pressed() -> void:
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", 1.0, 0.4)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		get_tree().quit()
	)


func _on_load_game(slot_index: int) -> void:
	var data = SaveManager.load_from_slot(slot_index)
	if data.is_empty():
		return
	GameState.set_flag("__pending_load_data", data)
	_transition_to_scene("res://scenes/game_screen.tscn")


func _on_delete_slot(slot_index: int) -> void:
	SaveManager.delete_slot(slot_index)
	save_load_window.set_mode("load")


# =============================================================================
# 辅助函数
# =============================================================================

func _set_title_opacity(a: float) -> void:
	_title_label.modulate.a = a


func _create_vignette_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV;
	float vignette = 1.0 - distance(uv, vec2(0.5)) * 1.8;
	vignette = smoothstep(0.0, 0.7, vignette);
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - vignette) * 0.55);
}
"""
	return shader
