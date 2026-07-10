@tool
extends Control
class_name TacticsBoard

## 战棋棋盘弹窗：正交视图 — 正方体紧密拼装成网格
##
## 战斗系统：
## 1. 剧情触发 battle 效果 → GameScreen 调用 load_battle_config() 加载配置
## 2. 点击棋盘上的己方单位选中，显示移动范围
## 3. 移动后显示行动菜单（攻击/技能/待机）
## 4. 回合制：TurnManager 管理行动顺序，SkillSystem 处理技能执行

# =============================================================================
# 信号
# =============================================================================

## 战斗结果信号
## 携带结构化结果字典：{"type": "win"|"lose", "branch": "分支ID", "next": "目标节点"}
signal battle_result(result: Dictionary)

## 战斗结束信号（替代旧版单一字符串信号，保持兼容）
signal battle_ended(outcome: String)

## 单位被选中信号
signal unit_selected(unit: TacticsUnit)

## 单位移动完成信号
signal unit_moved(unit: TacticsUnit, from_pos: Vector2i, to_pos: Vector2i)

## 回合切换信号
signal turn_changed(unit: TacticsUnit)

# =============================================================================
# 棋盘参数 — 可在编辑器中直接修改
# =============================================================================

## 网格列数（X 轴方向），由战斗配置动态设置，默认 10
@export var _grid_cols: int = 10

## 网格行数（Z 轴方向），由战斗配置动态设置，默认 10
@export var _grid_rows: int = 10

## 初始地块类型ID（新建棋盘时的默认地块类型，编辑器可用）
@export var _initial_terrain_type: String = "stone_floor"

## 被排除的格子集合（key: Vector2i(col, row)），用于不规则棋盘
var _excluded_tiles: Dictionary = {}


## 检查指定格子是否为有效棋盘格子
func _is_valid_tile(col: int, row: int) -> bool:
	if col < 0 or col >= _grid_cols or row < 0 or row >= _grid_rows:
		return false
	return not _excluded_tiles.has(Vector2i(col, row))

## 正方体边长（长 = 宽 = 高），单位：Godot 3D 世界单位
const TILE_SIZE := 1.0

# =============================================================================
# 节点引用（@onready 在 _ready() 之前自动绑定场景中的节点）
# =============================================================================

## 半透明遮罩层，点击可关闭弹窗
@onready var overlay: ColorRect = $Overlay

## 面板右上角的 X 关闭按钮
@onready var close_x_button: Button = $Panel/CloseXButton

## 面板底部的"关闭"文字按钮
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

## 面板本身
@onready var panel: Panel = $Panel

## 标题标签
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel

## 正交相机，俯视拍摄棋盘
@onready var camera: Camera3D = $Panel/VBoxContainer/SubViewportContainer/SubViewport/Camera3D

## SubViewport 容器，用于检测鼠标是否在棋盘区域上
@onready var subviewport_container: SubViewportContainer = $Panel/VBoxContainer/SubViewportContainer
## SubViewport，用于渲染 3D 场景
@onready var subviewport: SubViewport = $Panel/VBoxContainer/SubViewportContainer/SubViewport

## 所有格子立方体的父节点容器
@onready var tile_container: Node3D = $Panel/VBoxContainer/SubViewportContainer/SubViewport/TileContainer

@onready var directional_light: DirectionalLight3D = $Panel/VBoxContainer/SubViewportContainer/SubViewport/DirectionalLight3D

## 二维数组存储所有格子节点的引用，_tiles[row][col]
var _tiles: Array = []

## 标记棋盘是否已生成，避免重复生成
var _board_generated := false

# =============================================================================
# 相机控制状态（3D透视视角）
# =============================================================================

## 右键是否正在拖动（用于平移）
var _is_dragging := false

## 中键是否正在拖动（用于旋转视角）
var _is_rotating := false

## 上一帧鼠标位置，用于计算拖动增量
var _last_mouse_pos := Vector2.ZERO

## 平移灵敏度（世界单位/像素）
const PAN_SPEED := 0.02

## 旋转灵敏度（度/像素）
const ROTATE_SPEED := 0.4

## 滚轮缩放灵敏度
const ZOOM_SPEED := 2.0

## 相机距离范围限制
const CAMERA_DISTANCE_MIN := 3.0
const CAMERA_DISTANCE_MAX := 50.0

## 相机俯仰角（绕X轴，度）
var _camera_angle_x: float = 55.0

## 相机偏航角（绕Y轴，度）
var _camera_angle_y: float = 45.0

## 相机距离目标点的距离
var _camera_distance: float = 20.0

## 相机看向的目标点（棋盘中心）
var _camera_target: Vector3 = Vector3.ZERO

# =============================================================================
# 战斗配置状态
# =============================================================================

## 当前加载的战斗配置数据
var _battle_config: Dictionary = {}

## 当前加载的地形配置数据（从 battle_terrain_XXX.json 读取）
var _terrain_config: Dictionary = {}

## 胜负条件列表（从配置解析）
var _win_conditions: Array = []
var _lose_conditions: Array = []

## 单位数据字典：unit_id → {team, col, row, properties, node, alive}
var _unit_data: Dictionary = {}

## 单位节点字典：unit_id → TacticsUnit（新的 TacticsUnit 系统）
var _unit_nodes: Dictionary = {}

## SkillSystem 实例
var _skill_system: SkillSystem

## TurnManager 实例
var _turn_manager: TurnManager

## PhysicsSystem 实例（统一管理矢量速度、碰撞、摩擦、重力等物理逻辑）
var _physics_system: PhysicsSystem

## TerrainManager 实例（统一管理地形类型和地形实例）
var _terrain_manager: TerrainManager

## 当前选中的单位
var _selected_unit: TacticsUnit = null

# =============================================================================
# 战斗状态机 — 控制玩家交互流程
# =============================================================================

enum CombatState {
	IDLE,               # 没有选中单位
	UNIT_SELECTED,      # 已选中单位，显示行动菜单
	MOVE_MODE,          # 点击"移动"后，显示移动范围，等待点击格子
	ATTACK_MODE,        # 点击"攻击"后，显示攻击范围，等待点击目标
	SKILL_TARGET_MODE,  # 选择技能后，显示技能范围，等待点击目标
	DIRECTION_MODE,     # 推击技能选中目标后，等待选择8方向
	THROW_TARGET_MODE,  # 投掷技能目标选择：26格立体范围
	THROW_DIRECTION_MODE, # 投掷技能方向选择：26格可选方向
	ACTION_SUB_MENU,    # 动作子菜单：跳下 / 交互
	JUMP_DOWN_MODE,     # 跳下模式：周围八格高亮（限低2格+）
	INTERACT_MODE       # 交互模式：周围八格白色框架（仅同层可交互地形）
}

## 当前战斗状态
var _combat_state: CombatState = CombatState.IDLE

## 当前是否为玩家回合（用于防止敌方回合期间误选单位）
var _is_player_turn: bool = false

## 当前移动范围高亮格子的坐标列表
var _move_range: Array = []

## 移动范围高亮立方体节点列表
var _move_range_cubes: Array = []

## 当前显示的高亮格子类型（"move", "attack", "skill", "direction"）
var _highlight_type: String = ""

## 行动菜单是否显示
var _action_menu_visible: bool = false

## 动作子菜单是否显示（跳下/交互）
var _action_sub_menu_visible: bool = false
var _debug_input_count: int = 0
var _debug_viewport_count: int = 0
var _debug_click_count: int = 0

## 待处理的行动（"attack", "skill_{skill_id}"）
var _pending_action: String = ""

## 待处理的技能 ID（用于推击等需要方向选择的技能）
var _pending_skill_id: String = ""

## 8方向选择的目标单位
var _direction_target: TacticsUnit = null

## 投掷技能的目标单位或地形格子（Vector3i(col, row, layer)）
var _throw_target_pos: Vector3i = Vector3i(-1, -1, -1)
var _throw_target_unit: TacticsUnit = null

## 当前悬浮高亮的线框索引（用于改变颜色）
var _hovered_wireframe_idx: int = -1
var _hovered_wireframe_original_colors: Array = []

## 地形数据：{Vector2i(col,row): {height: int, type: String}}
var _terrain_data: Dictionary = {}
var _max_terrain_height: int = 0

## 侧边留空区域引用（用于放置人物）
var _left_margin: Control
var _right_margin: Control

## 是否已进入全屏战斗模式
var _is_fullscreen := false


# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		# 编辑器模式：生成预览棋盘
		_editor_init()
		return
	_runtime_init()


## 编辑器模式初始化：生成预览棋盘供编辑器视窗显示
func _editor_init() -> void:
	# 编辑器中使用默认尺寸和类型
	if _grid_cols <= 0:
		_grid_cols = 10
	if _grid_rows <= 0:
		_grid_rows = 10
	if _terrain_config.is_empty():
		_terrain_config = {"terrain_config": {"default_type": _initial_terrain_type}}
	# 生成棋盘预览
	_clear_children()
	_create_base_platform()
	_create_tiles()
	_setup_camera()
	print("[TacticsBoard] 编辑器预览棋盘已生成: ", _grid_cols, "x", _grid_rows)


## 运行时初始化：连接信号、创建 UI、生成棋盘
func _runtime_init() -> void:
	# 连接关闭按钮的信号到关闭函数
	close_x_button.pressed.connect(_on_close_pressed)
	close_button.pressed.connect(_on_close_pressed)

	# 连接遮罩层的点击事件（点击遮罩区域关闭弹窗）
	overlay.gui_input.connect(_on_overlay_clicked)

	# 为棋盘视窗添加两侧留空（用于显示人物）
	_setup_side_margins()

	# 禁用 SubViewport 的 GUI 输入，防止事件被 SubViewport 消费
	if subviewport:
		subviewport.gui_disable_input = true
		print("[TacticsBoard] _runtime_init: gui_disable_input = true")

	# 初始化技能系统和回合管理器
	_init_systems()

	# 生成棋盘
	_generate_board()


# =============================================================================
# 关闭逻辑
# =============================================================================

func _on_close_pressed() -> void:
	# 隐藏整个弹窗（包括遮罩、面板、棋盘）
	visible = false
	# 退出全屏模式
	_exit_fullscreen()


func _on_overlay_clicked(event: InputEvent) -> void:
	# 检测是否为鼠标左键点击
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		visible = false
		_exit_fullscreen()


# =============================================================================
# 侧边留空 — 棋盘视窗两侧留出空间用于显示人物
# =============================================================================

## 将 SubViewportContainer 包裹在 HBoxContainer 中，两侧添加 Control 留空
func _setup_side_margins() -> void:
	# 使用 @onready 变量，避免 $ 路径在特殊时机返回 null
	var svp_container := subviewport_container
	if svp_container == null:
		return
	var vbox := svp_container.get_parent()
	if vbox == null:
		return

	# 获取 SubViewportContainer 在 VBoxContainer 中的位置
	var svp_index := svp_container.get_index()

	# 从 VBoxContainer 中移除
	vbox.remove_child(svp_container)

	# 创建 HBoxContainer 包裹 SubViewportContainer + 两侧留空
	var hbox := HBoxContainer.new()
	hbox.name = "BoardArea"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 左侧留空区域
	_left_margin = Control.new()
	_left_margin.name = "LeftMargin"
	_left_margin.custom_minimum_size = Vector2(160, 0)
	_left_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 右侧留空区域
	_right_margin = Control.new()
	_right_margin.name = "RightMargin"
	_right_margin.custom_minimum_size = Vector2(160, 0)
	_right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

	hbox.add_child(_left_margin)
	hbox.add_child(svp_container)
	hbox.add_child(_right_margin)

	# 插入到 VBoxContainer 中原来的位置
	vbox.add_child(hbox)
	vbox.move_child(hbox, svp_index)


# =============================================================================
# 全屏模式 — 战斗时面板铺满屏幕，隐藏标题和关闭按钮
# =============================================================================

## 进入全屏战斗模式
func _enter_fullscreen() -> void:
	if _is_fullscreen:
		return
	if panel == null:
		return
	_is_fullscreen = true

	# 面板铺满全屏
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0

	# 隐藏标题和关闭按钮（战斗期间只能通过结果按钮退出）
	title_label.visible = false
	close_button.visible = false
	close_x_button.visible = false

	# 遮罩层不需要（全屏面板自己就是遮罩）
	overlay.visible = false


## 退出全屏战斗模式，恢复为居中弹窗
func _exit_fullscreen() -> void:
	if not _is_fullscreen:
		return
	if panel == null:
		_is_fullscreen = false
		return
	_is_fullscreen = false

	# 恢复面板为居中弹窗
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -500
	panel.offset_top = -350
	panel.offset_right = 500
	panel.offset_bottom = 350

	# 恢复标题和关闭按钮
	title_label.visible = true
	close_button.visible = true
	close_x_button.visible = true

	# 恢复遮罩层
	overlay.visible = true


# =============================================================================
# 棋盘生成（主入口）
# =============================================================================

func _generate_board() -> void:
	# 如果已经生成过，跳过重复生成
	if _board_generated:
		return

	# 先清除容器中已有的子节点（防止残留）
	_clear_children()

	# 按顺序：底座 → 正方体格子 → 设置相机
	_create_base_platform()
	_create_tiles()
	_setup_camera()

	_board_generated = true


## 清除 TileContainer 中的所有子节点
func _clear_children() -> void:
	if tile_container == null:
		return
	for child in tile_container.get_children():
		child.queue_free()
	_tiles.clear()


# =============================================================================
# 底座 — 整个棋盘下方的深色底板
# =============================================================================

func _create_base_platform() -> void:
	# 计算棋盘四个角的世界坐标（用于确定底座尺寸）
	var corners: Array = [
		_grid_to_world(0, 0),
		_grid_to_world(_grid_cols - 1, 0),
		_grid_to_world(_grid_cols - 1, _grid_rows - 1),
		_grid_to_world(0, _grid_rows - 1),
	]

	# 计算 X 轴和 Z 轴的包围盒范围
	var x_min: float = corners[0].x; var x_max: float = corners[0].x
	var z_min: float = corners[0].z; var z_max: float = corners[0].z
	for c in corners:
		x_min = minf(x_min, c.x); x_max = maxf(x_max, c.x)
		z_min = minf(z_min, c.z); z_max = maxf(z_max, c.z)

	# 底座宽度 = 包围盒宽度 + 一个格子的余量
	var bw: float = (x_max - x_min) + TILE_SIZE
	# 底座深度 = 包围盒深度 + 一个格子的余量
	var bd: float = (z_max - z_min) + TILE_SIZE

	# 创建薄板网格作为底座
	var mesh := BoxMesh.new()
	mesh.size = Vector3(bw, 0.04, bd)     # 宽、高(很薄)、深

	# 创建网格实例并放置
	var platform := MeshInstance3D.new()
	platform.name = "BasePlatform"
	platform.mesh = mesh
	platform.position = Vector3(0, -0.02, 0)   # 稍微低于 Y=0，使格子底部嵌入

	# 深色材质，形成底座阴影效果
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.08, 0.05)   # 深棕黑色
	platform.material_override = mat

	tile_container.add_child(platform)


# =============================================================================
# 正方体格子拼装 — 支持高度轴和地形
# =============================================================================

func _create_tiles() -> void:
	# 从配置加载地形数据
	_load_terrain()

	for row in range(_grid_rows):
		var row_tiles: Array = []
		for col in range(_grid_cols):
			if not _is_valid_tile(col, row):
				row_tiles.append(null)  # 排除的格子留空占位
				continue
			var key := Vector2i(col, row)
			var terrain = _terrain_data.get(key, {"height": 0, "type_id": _initial_terrain_type})
			var type_id: String = terrain.get("type_id", _initial_terrain_type)
			# 确保type_id不是空气标记
			if type_id == "__AIR__":
				type_id = _initial_terrain_type
			var height: int = terrain.get("height", 0)
			var tile_node := _create_cube_tile(col, row, height, type_id, terrain.get("layers", []))
			tile_container.add_child(tile_node)
			row_tiles.append(tile_node)

			# 为未在 terrain_manager 中注册的地块创建实例（确保可通过性等查询正确）
			if _terrain_manager != null and not key in _terrain_data:
				var instance := _terrain_manager.create_terrain_instance(type_id, key)
				if instance != null:
					instance.current_height = height
		_tiles.append(row_tiles)


## 根据战斗配置路径推导地形配置路径并加载
## 规则：battle_001.json → battle_terrain_001.json（同目录下）
func _load_terrain_config(battle_path: String) -> Dictionary:
	# 从 battle_XXX.json 推导 battle_terrain_XXX.json
	var terrain_path: String = battle_path.replace("battle_", "battle_terrain_")

	var file := FileAccess.open(terrain_path, FileAccess.READ)
	if file == null:
		push_warning("TacticsBoard: 地形配置不存在，使用空配置: " + terrain_path)
		return {}

	var json_text := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("TacticsBoard: 地形配置 JSON 解析失败: " + json.get_error_message())
		return {}

	print("[TacticsBoard] 加载地形配置: ", terrain_path)
	return json.data


## 从战斗配置中加载地形数据（支持地块类型）
## 支持两种格式：
##   1. 稀疏格式：default_type + tiles数组（性能最优）
##   2. 密集格式：grid二维数组 + height_grid（适合编辑器生成）
func _load_terrain() -> void:
	_terrain_data.clear()
	var terrain_config: Dictionary = _terrain_config.get("terrain_config", {})

	# 获取默认地块类型：地形配置 > 战斗配置initial_terrain_type > 默认stone_floor
	var default_type: String = terrain_config.get("default_type", "")
	if default_type.is_empty():
		default_type = _battle_config.get("initial_terrain_type", "stone_floor")

	# 格式1：稀疏数组（tiles）— 支持 layers 多层格式和旧版 type_id + height 格式
	var tiles: Array = terrain_config.get("tiles", [])
	for t in tiles:
		var col: int = t.get("col", 0)
		var row: int = t.get("row", 0)
		var key := Vector2i(col, row)

		# 新格式：layers 数组（每个元素是该层的地形类型ID，"__AIR__"表示空气层）
		var layers: Array = t.get("layers", [])
		if not layers.is_empty():
			# 找到最顶层非空气类型作为该格子的主类型
			var top_type_id: String = _initial_terrain_type
			for li in range(layers.size() - 1, -1, -1):
				if layers[li] != "__AIR__":
					top_type_id = layers[li]
					break
			# layers.size() = 层数（1层=地面），游戏height = 层数-1（0=地面）
			var height: int = layers.size() - 1

			_terrain_data[key] = {
				"type_id": top_type_id,
				"height": height,
				"layers": layers,
				"custom_health": t.get("custom_health", -1),
				"is_open": t.get("is_open", false)
			}

			# 为每层创建TerrainManager地形实例（仅顶层）
			if _terrain_manager != null:
				var instance := _terrain_manager.create_terrain_instance(top_type_id, key)
				if instance != null:
					instance.current_height = height
					var custom_health: int = t.get("custom_health", -1)
					if custom_health >= 0:
						instance.current_health = custom_health
						instance.max_health = custom_health
		else:
			# 旧格式兼容：type_id + height
			var type_id: String = t.get("type_id", t.get("type", default_type))
			var height: int = t.get("height", -1)  # -1表示使用TerrainType.base_height

			_terrain_data[key] = {
				"type_id": type_id,
				"height": height,
				"custom_health": t.get("custom_health", -1),
				"is_open": t.get("is_open", false)
			}

			if _terrain_manager != null:
				var instance := _terrain_manager.create_terrain_instance(type_id, key)
				if instance != null:
					if height >= 0:
						instance.current_height = height
					var custom_health: int = t.get("custom_health", -1)
					if custom_health >= 0:
						instance.current_health = custom_health
						instance.max_health = custom_health

	# 格式2：密集数组（grid）
	var grid: Array = terrain_config.get("grid", [])
	if not grid.is_empty():
		var height_grid: Array = terrain_config.get("height_grid", [])
		for row_idx in range(grid.size()):
			var row_data: Array = grid[row_idx]
			for col_idx in range(row_data.size()):
				var type_id_val = row_data[col_idx]
				if type_id_val != null and type_id_val != "":
					var key := Vector2i(col_idx, row_idx)
					var height_val: int = 0
					if row_idx < height_grid.size() and col_idx < height_grid[row_idx].size():
						height_val = height_grid[row_idx][col_idx]

					_terrain_data[key] = {
						"type_id": str(type_id_val),
						"height": height_val
					}

					if _terrain_manager != null:
						var instance := _terrain_manager.create_terrain_instance(str(type_id_val), key)
						if instance != null and height_val >= 0:
							instance.current_height = height_val

	print("[TacticsBoard] 地形加载完成: tiles=", tiles.size(),
		" grid=", grid.size(),
		" default_type=", default_type)

	# 缓存最大地形高度（用于点击检测从高到低扫描）
	_max_terrain_height = 0
	for key in _terrain_data:
		var h: int = _terrain_data[key].get("height", 0)
		if h > _max_terrain_height:
			_max_terrain_height = h

## 创建单个正方体格子（支持高度堆叠，根据每层地形类型着色）
## @param col: 列索引
## @param row: 行索引
## @param height: 高度层级（0=平地，1=1层高，2=2层高...）
## @param terrain_type: 地形类型ID（用于查找颜色，无layer_types时使用）
## @param layer_types: 每层的地形类型ID数组（优先使用，每层独立着色）
func _create_cube_tile(col: int, row: int, height: int = 0, terrain_type: String = "flat", layer_types: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = "Cube_%d_%d" % [col, row]

	var pos := _grid_to_world(col, row)
	root.position = Vector3(pos.x, 0, pos.z)

	# 为整个方块添加一个 StaticBody3D 作为碰撞体（用于射线检测）
	var static_body := StaticBody3D.new()
	static_body.name = "CollisionBody"
	# 设置碰撞层：第1层（默认物理层）+ 第5层（用于交互检测）
	static_body.collision_layer = 0b00000000_00000000_00000000_00010001
	root.add_child(static_body)

	# 堆叠正方体（高度 ≥ 0，至少1层），跳过空气层
	var total_layers := maxi(height, 0) + 1
	# 找到最后一个非空气层索引，用于顶层着色
	var last_real_layer := -1
	for li in range(total_layers - 1, -1, -1):
		if li >= layer_types.size() or layer_types[li] != "__AIR__":
			last_real_layer = li
			break

	for layer in range(total_layers):
		# 跳过空气层（不创建方块）
		if layer < layer_types.size() and layer_types[layer] == "__AIR__":
			continue

		var mesh := BoxMesh.new()
		mesh.size = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)

		var cube := MeshInstance3D.new()
		cube.name = "Mesh_L%d" % layer
		cube.mesh = mesh
		cube.position = Vector3(0, TILE_SIZE * 0.5 + layer * TILE_SIZE, 0)

		# 该层的地形类型：优先从 layer_types 取，否则统一用 terrain_type
		var layer_type: String = ""
		if layer < layer_types.size():
			layer_type = layer_types[layer]
		if layer_type.is_empty():
			layer_type = terrain_type

		var layer_color: Color = _get_terrain_color(layer_type, col, row)

		var mat := StandardMaterial3D.new()
		if layer == last_real_layer:
			mat.albedo_color = layer_color
		else:
			mat.albedo_color = layer_color.darkened(0.15)

		cube.material_override = mat
		root.add_child(cube)

		# 为该层添加碰撞形状
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "Collision_L%d" % layer
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
		collision_shape.shape = box_shape
		collision_shape.position = Vector3(0, TILE_SIZE * 0.5 + layer * TILE_SIZE, 0)
		static_body.add_child(collision_shape)

	return root


## 根据地型类型ID获取显示颜色
func _get_terrain_color(type_id: String, col: int, row: int) -> Color:
	# 棋盘格基准色
	var is_light := (col + row) % 2 == 0
	var base_light := Color(0.88, 0.83, 0.74)
	var base_dark := Color(0.52, 0.46, 0.38)

	if _terrain_manager == null:
		return base_light if is_light else base_dark

	var terrain_type := _terrain_manager.get_terrain_type(type_id)
	if terrain_type == null:
		return base_light if is_light else base_dark

	# 根据 material_type 着色
	match terrain_type.material_type:
		TerrainType.MaterialType.STONE:
			return Color(0.62, 0.62, 0.65)  # 灰色石材
		TerrainType.MaterialType.WOOD:
			return Color(0.65, 0.42, 0.22)  # 棕色木材
		TerrainType.MaterialType.METAL:
			return Color(0.55, 0.58, 0.62)  # 银灰金属
		TerrainType.MaterialType.PLASTIC:
			return Color(0.3, 0.75, 0.8)    # 青色塑料
		_:
			return base_light if is_light else base_dark


# =============================================================================
# 坐标转换 — 俯视正方形网格
# =============================================================================

## 将网格坐标 (col, row) 转换为 3D 世界坐标
## 俯视图下为标准正方形网格：
##   - col 映射到 X 轴（从左到右）
##   - row 映射到 Z 轴（从上到下）
##   - 网格居中，原点 (0,0,0) 位于网格中心
func _grid_to_world(col: int, row: int) -> Vector3:
	# 计算相对于网格中心的偏移
	var cx: float = col - (_grid_cols - 1) * 0.5
	var rz: float = row - (_grid_rows - 1) * 0.5

	# 俯视图：col → X轴，row → Z轴
	var x: float = cx * TILE_SIZE                  # 世界 X 坐标
	var z: float = rz * TILE_SIZE                  # 世界 Z 坐标

	return Vector3(x, 0, z)


## 获取格子上方用于放置角色的位置（Y 偏移到正方体顶部，考虑地形高度和空中高度）
## @param override_height: 可选，覆盖地形高度（用于飞行单位等不在地形顶部的角色）
## @param air_height_offset: 空中相对高度偏移（用于跃过障碍物时的空中位置）
func _grid_to_world_top(col: int, row: int, override_height: int = -1, air_height_offset: float = 0.0) -> Vector3:
	var pos := _grid_to_world(col, row)
	var height: int = override_height
	var is_passable: bool = false
	if height < 0:
		var key := Vector2i(col, row)
		var terrain: Dictionary = _terrain_data.get(key, {"height": 0, "type": "flat"})
		height = terrain.get("height", 0)
	is_passable = _is_tile_passable(col, row)

	# 计算实际Y坐标
	# 可通过地形：单位站在内部（地面层），Y = TILE_SIZE * height
	# 不可通过地形：单位站在上表面，Y = TILE_SIZE * (height + 1)
	# 空中偏移：air_height_offset（世界坐标高度）
	var surface_y: float = TILE_SIZE * float(height) if is_passable else TILE_SIZE * (height + 1)
	pos.y = surface_y + air_height_offset + 0.01
	return pos


# =============================================================================
# 相机设置 — 3D透视视角，类似地图编辑器
# =============================================================================

func _setup_camera() -> void:
	# 透视投影：提供正常的3D视角
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE

	# 从配置读取相机目标位置（默认看向棋盘中心）
	var camera_look_at: Dictionary = _battle_config.get("camera_look_at", {})
	var look_col: int = camera_look_at.get("col", _grid_cols / 2)
	var look_row: int = camera_look_at.get("row", _grid_rows / 2)
	var look_height: float = camera_look_at.get("height", 1.0)

	# 将格子坐标转换为世界坐标
	_camera_target = _grid_to_world(look_col, look_row)
	_camera_target.y = look_height  # 设置高度

	# 根据棋盘大小计算初始相机距离
	var max_dim := maxf(_grid_cols, _grid_rows)
	_camera_distance = max_dim * 1.1
	_camera_distance = clampf(_camera_distance, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)

	# 初始化相机角度
	_camera_angle_x = 55.0  # 俯仰角
	_camera_angle_y = 45.0  # 偏航角

	# 根据角度和距离计算相机位置
	_update_camera_position()

	# 设置透视相机参数
	camera.fov = 45.0  # 视野角度
	camera.near = 0.1
	camera.far = maxf(200.0, max_dim * 10.0)

	print("[TacticsBoard] 相机设置: 目标格子(", look_col, ",", look_row, ")",
		" 目标位置(", _camera_target.x, ",", _camera_target.y, ",", _camera_target.z, ")",
		" 距离=", _camera_distance, " 角度(", _camera_angle_x, ",", _camera_angle_y, ")",
		" 位置(", camera.position.x, ",", camera.position.y, ",", camera.position.z, ")")


## 根据相机角度和距离更新相机位置
func _update_camera_position() -> void:
	if camera == null:
		return

	# 将角度转换为弧度
	var rad_yaw := deg_to_rad(_camera_angle_y)
	var rad_pitch := deg_to_rad(_camera_angle_x)

	# 计算相机位置（围绕目标点）
	# 公式：cam_pos = target + distance * (cos(yaw)*cos(pitch), sin(pitch), sin(yaw)*cos(pitch))
	var cam_x := _camera_target.x + _camera_distance * cos(rad_yaw) * cos(rad_pitch)
	var cam_y := _camera_target.y + _camera_distance * sin(rad_pitch)
	var cam_z := _camera_target.z + _camera_distance * sin(rad_yaw) * cos(rad_pitch)

	camera.position = Vector3(cam_x, cam_y, cam_z)

	# 相机看向目标点
	camera.look_at(_camera_target, Vector3.UP)


# =============================================================================
# 鼠标交互 — 右键拖动平移 / 中键拖动旋转 / 滚轮缩放
# =============================================================================

## 全局输入处理：仅在棋盘可见且鼠标位于 SubViewport 区域内时响应
func _input(event: InputEvent) -> void:
	# 调试：打印前5个事件
	if _debug_input_count < 5:
		_debug_input_count += 1
		print("[TacticsBoard] _input #", _debug_input_count, ": ", event, " visible=", visible, " camera=", camera != null, " container=", subviewport_container != null)

	# 棋盘不可见时不处理
	if not visible:
		return

	# 相机或视口未就绪时不处理鼠标交互
	if camera == null or subviewport_container == null:
		return

	# 鼠标不在 SubViewport 区域内时不处理
	if not _is_mouse_in_viewport():
		return

	# 只处理鼠标事件
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# --- 中键：旋转相机视角 ---
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				# 中键按下：开始旋转
				_is_rotating = true
				_last_mouse_pos = mb.position
			else:
				# 中键释放：停止旋转
				_is_rotating = false

		# --- 右键：平移相机 ---
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				# 右键按下：开始拖动
				_is_dragging = true
				_last_mouse_pos = mb.position
			else:
				# 右键释放：停止拖动
				_is_dragging = false

		# --- 滚轮：缩放（调整相机距离） ---
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			# 向上滚动 → 放大（减小相机距离）
			_camera_distance = maxf(_camera_distance - ZOOM_SPEED, CAMERA_DISTANCE_MIN)
			_update_camera_position()

		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# 向下滚动 → 缩小（增大相机距离）
			_camera_distance = minf(_camera_distance + ZOOM_SPEED, CAMERA_DISTANCE_MAX)
			_update_camera_position()

		# --- 左键点击：单位选中 / 移动 ---
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# 子菜单（动作/技能）可见时：点击外部关闭，点击内部交由按钮处理
			if _action_sub_menu_visible:
				var sub_a := get_node_or_null("ActionSubMenu")
				var sub_s := get_node_or_null("SkillSubMenu")
				var pos := get_global_mouse_position()
				if (sub_a is Control and sub_a.get_global_rect().has_point(pos)) or \
				   (sub_s is Control and sub_s.get_global_rect().has_point(pos)):
					return  # 点击在子菜单内，不处理
				_close_action_sub_menu()
				return
			if _action_menu_visible:
				# 菜单可见时阻止棋盘点击（动作模式例外）
				if _combat_state != CombatState.INTERACT_MODE and _combat_state != CombatState.THROW_TARGET_MODE and _combat_state != CombatState.THROW_DIRECTION_MODE and _combat_state != CombatState.JUMP_DOWN_MODE and _combat_state != CombatState.DIRECTION_MODE:
					return
			print("[TacticsBoard] 左键点击，全局位置: ", get_global_mouse_position())
			_on_left_click(mb)

	# --- 鼠标移动：执行旋转或平移 ---
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion

		# 中键拖动：旋转相机角度
		if _is_rotating:
			var dx := mm.relative.x
			var dy := mm.relative.y
			# 水平移动改变偏航角（yaw）
			_camera_angle_y += dx * ROTATE_SPEED
			# 垂直移动改变俯仰角（pitch），限制在5-89度之间
			_camera_angle_x = clampf(_camera_angle_x + dy * ROTATE_SPEED, 5.0, 89.0)
			_update_camera_position()

		# 右键拖动：平移相机和目标点
		elif _is_dragging:
			# 使用相机的局部坐标轴进行平移：
			#   basis.x = 相机右方向（屏幕右）
			#   basis.z = 相机前方向（屏幕前）
			# 同时移动相机和目标点，保持相对距离不变
			var move := Vector3.ZERO
			move -= camera.global_transform.basis.x * mm.relative.x * PAN_SPEED
			move += camera.global_transform.basis.y * mm.relative.y * PAN_SPEED
			camera.position += move
			_camera_target += move

		# 投掷/交互悬浮高亮
		if _combat_state == CombatState.THROW_TARGET_MODE or _combat_state == CombatState.THROW_DIRECTION_MODE or _combat_state == CombatState.INTERACT_MODE:
			_update_hover_highlight(get_global_mouse_position())


## GUI 输入处理（备用：当 _input 无法正常接收事件时使用）
func _gui_input(event: InputEvent) -> void:
	# 只在战斗模式下处理（overlay 不可见时）
	if overlay.visible:
		return
	if not visible:
		return
	if camera == null or subviewport_container == null:
		return

	print("[TacticsBoard] _gui_input: event=", event)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# 子菜单（动作/技能）可见时：点击外部关闭，点击内部交由按钮处理
			if _action_sub_menu_visible:
				var sub_a := get_node_or_null("ActionSubMenu")
				var sub_s := get_node_or_null("SkillSubMenu")
				var pos := get_global_mouse_position()
				if (sub_a is Control and sub_a.get_global_rect().has_point(pos)) or \
				   (sub_s is Control and sub_s.get_global_rect().has_point(pos)):
					return
				_close_action_sub_menu()
				return
			if _action_menu_visible:
				if _combat_state != CombatState.INTERACT_MODE and _combat_state != CombatState.THROW_TARGET_MODE and _combat_state != CombatState.THROW_DIRECTION_MODE and _combat_state != CombatState.JUMP_DOWN_MODE and _combat_state != CombatState.DIRECTION_MODE:
					return
			print("[TacticsBoard] _gui_input: 左键点击")
			_on_left_click(mb)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(_camera_distance - ZOOM_SPEED, CAMERA_DISTANCE_MIN)
			_update_camera_position()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(_camera_distance + ZOOM_SPEED, CAMERA_DISTANCE_MAX)
			_update_camera_position()

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_rotating:
			var dx := mm.relative.x
			var dy := mm.relative.y
			_camera_angle_y += dx * ROTATE_SPEED
			_camera_angle_x = clampf(_camera_angle_x + dy * ROTATE_SPEED, 5.0, 89.0)
			_update_camera_position()
		elif _is_dragging:
			var move := Vector3.ZERO
			move -= camera.global_transform.basis.x * mm.relative.x * PAN_SPEED
			move += camera.global_transform.basis.y * mm.relative.y * PAN_SPEED
			camera.position += move
			_camera_target += move


## 未处理输入（调试用：检查 _input 是否被调用）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			print("[TacticsBoard] _unhandled_input: 未处理的左键点击！_input 可能未被调用")


## 检测鼠标是否在 SubViewport 容器的矩形区域内
func _is_mouse_in_viewport() -> bool:
	if subviewport_container == null:
		print("[TacticsBoard] _is_mouse_in_viewport: container null")
		return false
	var mouse_pos: Vector2 = get_global_mouse_position()
	var rect: Rect2 = subviewport_container.get_global_rect()
	var result := rect.has_point(mouse_pos)
	# 调试：打印前5次调用
	if _debug_viewport_count < 5:
		_debug_viewport_count += 1
		print("[TacticsBoard] _is_mouse_in_viewport #", _debug_viewport_count, ": mouse=", mouse_pos, " rect=", rect, " result=", result)
	if not result and _debug_viewport_count >= 5:
		print("[TacticsBoard] _is_mouse_in_viewport: mouse=", mouse_pos, " rect=", rect)
	return result


# =============================================================================
# 公共接口 — 供外部脚本调用
# =============================================================================

# ---------------------------------------------------------------------------
# 战斗配置加载 — 从 JSON 文件加载战斗场景（背景、单位、颜色、分支）
# ---------------------------------------------------------------------------

## 加载战斗配置 JSON 文件并应用到棋盘
## 每个战斗场景有独立的 JSON 配置文件，定义：
##   - background: 背景图路径
##   - tile_light_color / tile_dark_color: 格子颜色
##   - win_next / lose_next: 剧情分支目标节点 ID
##   - units: 参战单位列表（位置、类型、纹理）
## @param config_path: 战斗配置 JSON 文件路径，如 "res://data/battles/battle_001.json"
func load_battle_config(config_path: String) -> void:
	# 重置调试计数器
	_debug_input_count = 0
	_debug_viewport_count = 0
	print("[TacticsBoard] load_battle_config: ", config_path)

	# 从 JSON 加载战斗配置
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("TacticsBoard: 无法加载战斗配置: " + config_path)
		return

	var json_text := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("TacticsBoard: 战斗配置 JSON 解析失败: " + json.get_error_message())
		return

	_battle_config = json.data
	print("[TacticsBoard] 从 JSON 加载: ", config_path)

	# 解析网格尺寸（支持自定义大小）
	_grid_cols = _battle_config.get("grid_cols", 10)
	_grid_rows = _battle_config.get("grid_rows", 10)

	# 加载对应的地形配置文件（battle_terrain_XXX.json）
	_terrain_config = _load_terrain_config(config_path)

	# 解析排除格子（从地形配置中读取）
	_excluded_tiles.clear()
	var terrain_cfg: Dictionary = _terrain_config.get("terrain_config", {})
	var excluded: Array = terrain_cfg.get("excluded_tiles", [])
	for entry in excluded:
		_excluded_tiles[Vector2i(entry.get("col", -1), entry.get("row", -1))] = true

	# 解析胜负条件
	_win_conditions = _battle_config.get("win_conditions", [])
	_lose_conditions = _battle_config.get("lose_conditions", [])

	# 进入全屏战斗模式
	_enter_fullscreen()

	# 重新生成棋盘（含地形）
	_clear_children()
	_create_base_platform()
	_create_tiles()
	_setup_camera()

	# 逐步应用配置
	_apply_tile_colors()       # 1. 格子颜色
	_place_battle_units()      # 2. 放置单位
	# _apply_battle_background()  # 3. 背景（待实现，需要 WorldEnvironment 节点）


## 从 BattleScene 场景加载战斗配置
## @param config_path: 战斗场景路径，如 "res://scenes/battles/battle_001.tscn"
func load_from_battle_scene(config_path: String) -> void:
	# 重置调试计数器
	_debug_input_count = 0
	_debug_viewport_count = 0
	print("[TacticsBoard] load_from_battle_scene: ", config_path)

	# 加载 BattleScene 场景
	var scene_resource := load(config_path) as PackedScene
	if scene_resource == null:
		push_error("TacticsBoard: 无法加载战斗场景: " + config_path)
		return

	var battle_scene := scene_resource.instantiate() as BattleScene
	if battle_scene == null:
		push_error("TacticsBoard: 场景根节点不是 BattleScene: " + config_path)
		return

	# 从 BattleScene 导出属性生成配置字典
	_battle_config = battle_scene.to_battle_config()
	print("[TacticsBoard] 从场景加载: battle_id=%s" % battle_scene.battle_id)

	# 解析网格尺寸
	_grid_cols = battle_scene.grid_cols
	_grid_rows = battle_scene.grid_rows

	# 加载地形配置
	var terrain_path: String = battle_scene.get_terrain_config_path()
	if not terrain_path.is_empty():
		_terrain_config = _load_terrain_config(terrain_path)
	else:
		# 尝试自动推断地形文件路径
		var auto_terrain: String = config_path.get_base_dir().replace("scenes/battles", "data/battles") + "/battle_terrain_" + battle_scene.battle_id.replace("battle_", "") + ".json"
		if FileAccess.file_exists(auto_terrain):
			_terrain_config = _load_terrain_config(auto_terrain)
		else:
			_terrain_config = {}
			push_warning("TacticsBoard: 未找到地形配置: battle_id=%s" % battle_scene.battle_id)

	# 解析排除格子
	_excluded_tiles.clear()
	var terrain_cfg: Dictionary = _terrain_config.get("terrain_config", {})
	var excluded: Array = terrain_cfg.get("excluded_tiles", [])
	for entry in excluded:
		_excluded_tiles[Vector2i(entry.get("col", -1), entry.get("row", -1))] = true

	# 解析胜负条件（从 ConditionResource 转换为字典列表）
	_win_conditions = []
	for cond in battle_scene.win_conditions:
		_win_conditions.append(cond.to_condition_dict())
	_lose_conditions = []
	for cond in battle_scene.lose_conditions:
		_lose_conditions.append(cond.to_condition_dict())

	# 设置相机位置
	_battle_config["camera_look_at"] = {
		"col": battle_scene.camera_look_at_col,
		"row": battle_scene.camera_look_at_row,
		"height": battle_scene.camera_look_at_height
	}

	# 进入全屏战斗模式
	_enter_fullscreen()

	# 重新生成棋盘（含地形）
	_clear_children()
	_create_base_platform()
	_create_tiles()
	_setup_camera()

	# 逐步应用配置
	_apply_tile_colors()       # 1. 格子颜色
	_place_battle_units()      # 2. 放置单位

	# 清理临时实例
	battle_scene.queue_free()


## 通用战斗加载入口 — 自动检测 .tscn 或 .json 格式
## @param config_path: 战斗配置路径（.tscn 场景 或 .json 文件）
func load_battle(config_path: String) -> void:
	if config_path.ends_with(".tscn"):
		load_from_battle_scene(config_path)
	else:
		load_battle_config(config_path)


## 应用战斗配置中的格子颜色（根据地型类型着色）
func _apply_tile_colors() -> void:
	# 遍历所有格子，根据地型类型设置材质颜色
	for row in range(_tiles.size()):
		var row_tiles: Array = _tiles[row]
		for col in range(row_tiles.size()):
			var root: Node3D = row_tiles[col]
			if root == null:
				continue  # 跳过排除的格子

			# 获取该格子的地形类型ID
			var type_id: String = ""
			if _terrain_data.has(Vector2i(col, row)):
				type_id = _terrain_data[Vector2i(col, row)].get("type_id", "")
			var terrain_color: Color = _get_terrain_color(type_id, col, row)

			# 收集所有 MeshInstance3D 子节点，按名称排序
			var mesh_children: Array = []
			for child in root.get_children():
				var cube := child as MeshInstance3D
				if cube != null:
					mesh_children.append(cube)
			mesh_children.sort_custom(func(a, b): return a.name < b.name)

			# 顶层使用完整颜色，下层使用暗色
			for i in range(mesh_children.size()):
				var cube: MeshInstance3D = mesh_children[i]
				var mat := StandardMaterial3D.new()
				if i == mesh_children.size() - 1:
					mat.albedo_color = terrain_color
				else:
					mat.albedo_color = terrain_color.darkened(0.15)
				cube.material_override = mat


## 根据战斗配置放置单位到棋盘上
func _place_battle_units() -> void:
	clear_characters()
	_unit_data.clear()
	_unit_nodes.clear()

	# 加载 TacticsUnit 场景模板
	const UNIT_SCENE_PATH := "res://scenes/tactics_unit.tscn"
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	if unit_scene == null:
		push_error("TacticsBoard: 无法加载 TacticsUnit 场景模板: " + UNIT_SCENE_PATH)
		return

	# 清空 TurnManager 的旧单位
	if _turn_manager:
		_turn_manager.clear_units()

	var units: Array = _battle_config.get("units", [])
	for unit in units:
		var unit_id: String = unit.get("id", "")
		var col: int = unit.get("col", 0)
		var row: int = unit.get("row", 0)
		var unit_height: int = unit.get("height", -1)  # -1表示使用地形高度
		var team: String = unit.get("team", "neutral")
		var character_id: String = unit.get("character_id", "")

		# 从 CharacterRoster 获取角色 Resource
		var char_res := CharacterRoster.get_character_resource(character_id)
		if char_res == null:
			push_error("TacticsBoard: 未找到角色数据: " + character_id + " (unit: " + unit_id + ")")
			continue

		# 从场景模板实例化 TacticsUnit
		var unit_node: TacticsUnit = unit_scene.instantiate()
		unit_node.name = "Unit_%s" % unit_id
		unit_node.unit_id = unit_id
		unit_node.team = team

		# 通过 Resource 统一应用属性（含子脚本差异化初始化）
		char_res.apply_to_unit(unit_node)
		unit_node.skill_system = _skill_system

		# 设置网格位置
		unit_node.grid_pos = Vector2i(col, row)
		unit_node.position = _grid_to_world_top(col, row, unit_height)

		# 设置精灵纹理
		var sprite: Sprite3D = unit_node.get_node_or_null("Sprite3D")
		if sprite:
			var tex_path: String = unit.get("texture", "")
			if not tex_path.is_empty():
				var tex: Texture2D = load(tex_path)
				if tex:
					sprite.texture = tex

		# 设置名称标签
		var label: Label3D = unit_node.get_node_or_null("NameLabel")
		if label:
			label.text = unit_node.unit_name

		# 根据队伍设置颜色标记（应用到 Sprite3D 子节点）
		if sprite:
			match team:
				"player": sprite.modulate = Color(0.5, 0.8, 1.0)
				"enemy":  sprite.modulate = Color(1.0, 0.4, 0.4)
				_:        sprite.modulate = Color(0.5, 1.0, 0.5)

		# 添加到场景中
		tile_container.add_child(unit_node)

		# 注册到 TurnManager
		if _turn_manager:
			_turn_manager.register_unit(unit_node)

		# 连接死亡信号
		unit_node.died.connect(_on_battle_unit_died)

		# 存储单位数据（properties 从 Resource 导出，实际战斗数据从 TacticsUnit 读取）
		_unit_data[unit_id] = {
			"team": team,
			"col": col,
			"row": row,
			"height": unit_height,
			"character_id": character_id,
			"properties": char_res.to_dict(),
			"node": unit_node,
			"alive": true
		}
		_unit_nodes[unit_id] = unit_node


# ---------------------------------------------------------------------------
# 角色放置方法
# ---------------------------------------------------------------------------

## 在指定格子上放置一个静态 Sprite3D 角色（简单纹理，无动画）
## @param col: 列索引
## @param row: 行索引
## @param texture: 2D 纹理
## @return: 创建的 Sprite3D 节点
func place_character(col: int, row: int, texture: Texture2D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "Char_Sprite_%d_%d" % [col, row]
	sprite.texture = texture
	sprite.position = _grid_to_world_top(col, row)        # 放在格子顶部
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED    # 始终面向相机
	sprite.pixel_size = 0.01                               # 像素大小
	tile_container.add_child(sprite)
	return sprite


## 在指定格子上放置一个 AnimatedSprite3D 角色（支持动画，也可当静态精灵用）
## AnimatedSprite3D 不播放动画时显示 SpriteFrames 中第一帧，等同于 Sprite3D
## @param col: 列索引
## @param row: 行索引
## @param sprite_frames: SpriteFrames 资源（含各动画帧）
## @param default_animation: 默认播放的动画名（空字符串 = 不播放，显示第一帧）
## @return: 创建的 AnimatedSprite3D 节点
func place_animated_character(col: int, row: int, sprite_frames: SpriteFrames, default_animation: String = "") -> AnimatedSprite3D:
	var anim := AnimatedSprite3D.new()
	anim.name = "Char_Anim_%d_%d" % [col, row]
	anim.sprite_frames = sprite_frames
	anim.position = _grid_to_world_top(col, row)          # 放在格子顶部
	anim.billboard = BaseMaterial3D.BILLBOARD_ENABLED      # 始终面向相机
	anim.pixel_size = 0.01                                 # 像素大小

	# 如果指定了默认动画则播放，否则停留在第一帧（等同于静态精灵）
	if not default_animation.is_empty() and sprite_frames.has_animation(default_animation):
		anim.animation = default_animation
		anim.play()

	tile_container.add_child(anim)
	return anim


## 快捷方法：用单张纹理创建 AnimatedSprite3D（无动画，仅一帧）
## 适合暂时没有动画素材但想预留动画接口的情况
## @param col: 列索引
## @param row: 行索引
## @param texture: 2D 纹理
## @return: 创建的 AnimatedSprite3D 节点
func place_character_as_animated(col: int, row: int, texture: Texture2D) -> AnimatedSprite3D:
	# 创建一个只有单帧 default 动画的 SpriteFrames
	var frames := SpriteFrames.new()
	frames.add_animation("default")
	frames.add_frame("default", texture)

	return place_animated_character(col, row, frames, "default")


## 清除棋盘上所有角色精灵（Sprite3D、AnimatedSprite3D 和 TacticsUnit）
func clear_characters() -> void:
	if tile_container == null:
		return
	for child in tile_container.get_children():
		if child is Sprite3D or child is AnimatedSprite3D or child is TacticsUnit:
			child.queue_free()
	_clear_move_range()


# ---------------------------------------------------------------------------
# 单位管理 — 死亡、移动、属性查询
# ---------------------------------------------------------------------------

## 标记指定单位死亡（隐藏节点，设置 alive=false）
func _set_unit_dead(unit_id: String) -> void:
	if not _unit_data.has(unit_id):
		return
	var data = _unit_data[unit_id]
	data["alive"] = false
	if data["node"]:
		data["node"].visible = false


## 标记指定单位存活（恢复可见）
func _set_unit_alive(unit_id: String) -> void:
	if not _unit_data.has(unit_id):
		return
	var data = _unit_data[unit_id]
	data["alive"] = true
	if data["node"]:
		data["node"].visible = true


## 获取所有存活单位（按队伍筛选）
func get_alive_units(team: String = "") -> Array:
	var result: Array = []
	for unit_id in _unit_data:
		var data = _unit_data[unit_id]
		if data["alive"]:
			if team.is_empty() or data["team"] == team:
				result.append({"id": unit_id, "data": data})
	return result


## 获取某单位的属性值
func get_unit_property(unit_id: String, key: String, default = null):
	if not _unit_data.has(unit_id):
		return default
	return _unit_data[unit_id]["properties"].get(key, default)


## 获取单位所在格子坐标
func get_unit_position(unit_id: String) -> Vector2i:
	if not _unit_data.has(unit_id):
		return Vector2i(-1, -1)
	var data = _unit_data[unit_id]
	return Vector2i(data["col"], data["row"])


# ---------------------------------------------------------------------------
# 胜负条件检查
# ---------------------------------------------------------------------------

## 检查所有胜负条件，返回首个满足的结果
## 返回 {} 表示无触发条件
func _check_conditions() -> Dictionary:
	# 先检查失败条件
	for lc in _lose_conditions:
		if _check_single_condition(lc):
			return {"type": "lose", "branch": lc.get("id", ""), "next": lc.get("next", "")}

	# 再检查胜利条件
	for wc in _win_conditions:
		if _check_single_condition(wc):
			return {"type": "win", "branch": wc.get("id", ""), "next": wc.get("next", "")}

	# 无条件满足
	return {}


## 检查单个条件是否满足
func _check_single_condition(condition: Dictionary) -> bool:
	var cond_type: String = condition.get("type", "")
	var params: Dictionary = condition.get("params", {})

	match cond_type:
		"eliminate_all":
			# 消灭指定队伍的所有单位
			var team: String = params.get("team", "enemy")
			return get_alive_units(team).is_empty()

		"eliminate_count":
			# 消灭指定队伍的至少 N 个单位
			var team: String = params.get("team", "enemy")
			var count: int = params.get("count", 1)
			var total := _count_units_by_team(team)
			var alive := get_alive_units(team).size()
			return (total - alive) >= count

		"all_units_dead":
			# 指定队伍的所有单位死亡
			var team: String = params.get("team", "player")
			return get_alive_units(team).is_empty()

		"unit_dead":
			# 指定单位死亡
			var unit_id: String = params.get("unit_id", "")
			if _unit_data.has(unit_id):
				return not _unit_data[unit_id]["alive"]
			return false

		"unit_alive":
			# 指定单位存活（用于保护目标）
			var unit_id: String = params.get("unit_id", "")
			if _unit_data.has(unit_id):
				return _unit_data[unit_id]["alive"]
			return false

		"survive_turns":
			# 存活指定回合数（需要回合系统支持，暂未实现）
			return false

		"escape_all":
			# 所有指定单位撤离到指定区域
			return false

		"reach_zone":
			# 指定单位到达指定区域
			return false

	return false


## 统计某队伍的总单位数（含存活和死亡）
func _count_units_by_team(team: String) -> int:
	var count := 0
	for unit_id in _unit_data:
		if _unit_data[unit_id]["team"] == team:
			count += 1
	return count


## 获取指定格子的世界坐标（顶部位置）
func get_tile_position(col: int, row: int) -> Vector3:
	return _grid_to_world_top(col, row)


# =============================================================================
# 系统初始化
# =============================================================================

## 创建 SkillSystem 和 TurnManager 节点
func _init_systems() -> void:
	# 技能系统
	_skill_system = SkillSystem.new()
	_skill_system.name = "SkillSystem"
	add_child(_skill_system)

	# 加载默认技能
	_skill_system.load_skills([
		"res://data/skills/skill_attack.json",
		"res://data/skills/skill_heal.json",
		"res://data/skills/skill_fireball.json",
		"res://data/skills/skill_push.json"
	])

	# 回合管理器
	_turn_manager = TurnManager.new()
	_turn_manager.name = "TurnManager"
	add_child(_turn_manager)

	# 连接回合信号
	_turn_manager.unit_turn_started.connect(_on_battle_turn_started)
	_turn_manager.unit_turn_ended.connect(_on_battle_turn_ended)
	_turn_manager.all_actions_done.connect(_on_all_actions_done)
	_turn_manager.round_started.connect(_on_round_started)
	_turn_manager.round_ended.connect(_on_round_ended)

	# 物理系统（通过 BoardContext 接口解耦棋盘依赖）
	var ctx := PhysicsSystem.BoardContext.new()
	ctx.configure(self)
	_physics_system = PhysicsSystem.new(ctx)

	# 地形管理系统（统一管理地形类型和地形实例）
	_terrain_manager = TerrainManager.new()
	_terrain_manager.set_physics_system(_physics_system)

	# 加载地形类型资源（从目录加载所有.tres和.json文件）
	_terrain_manager.load_terrain_types_from_dir("res://data/terrain_types/")
	print("[TacticsBoard] 地形系统初始化完成，已加载 ", _terrain_manager.get_terrain_type_count(), " 种地形类型")


# =============================================================================
# 左键点击 — 单位选中 / 移动
# =============================================================================

## 处理左键点击
func _on_left_click(event: InputEventMouseButton) -> void:
	# 行动菜单/技能菜单显示时不处理棋盘点击（但动作模式例外）
	if _action_menu_visible and _combat_state != CombatState.INTERACT_MODE and _combat_state != CombatState.THROW_TARGET_MODE and _combat_state != CombatState.THROW_DIRECTION_MODE and _combat_state != CombatState.JUMP_DOWN_MODE and _combat_state != CombatState.DIRECTION_MODE:
		return

	# 使用全局鼠标位置
	var global_mouse := get_global_mouse_position()

	# 3D线框选取模式：使用AABB检测，不受2D格子限制
	# 这些模式在2D射线下可能返回(-1,-1)（如点击空中线框），
	# 必须在2D检测之前单独处理
	# 注意：3D检测失败时不自动取消模式，让用户可以继续尝试选取
	if _combat_state == CombatState.THROW_TARGET_MODE:
		var throw_target := _get_throw_target_3d(global_mouse)
		if throw_target != Vector3i(-1, -1, -1):
			_on_throw_target_selected(throw_target)
		return
	if _combat_state == CombatState.THROW_DIRECTION_MODE:
		var throw_dir := _get_throw_direction_3d(global_mouse)
		if throw_dir != Vector3i(-1, -1, -1):
			_apply_throw_direction(throw_dir)
		return
	if _combat_state == CombatState.INTERACT_MODE:
		var inter_3d := _get_throw_target_3d(global_mouse)
		if inter_3d != Vector3i(-1, -1, -1):
			_execute_interact(inter_3d.x, inter_3d.y)
		return

	var clicked_grid := _get_grid_from_mouse(global_mouse)
	print("[TacticsBoard] _on_left_click: state=", _combat_state, " grid=", clicked_grid)
	if clicked_grid == Vector2i(-1, -1):
		return

	var col: int = clicked_grid.x
	var row: int = clicked_grid.y

	match _combat_state:
		CombatState.IDLE:
			# 仅在玩家回合时允许选中己方单位
			if not _is_player_turn:
				return
			# 点击单位选中
			var clicked_unit := _get_unit_at(col, row)
			if clicked_unit != null:
				_select_unit(clicked_unit)

		CombatState.UNIT_SELECTED:
			# 点击移动范围高亮 → 进入移动
			if _highlight_type == "move" and _move_range.has(clicked_grid):
				_move_unit_to(_selected_unit, col, row)
				return
			# 点击攻击范围 → 执行攻击
			if _highlight_type == "attack" and _move_range.has(clicked_grid):
				_execute_attack_on_tile(col, row)
				return
			# 点击其他单位 → 切换选中
			var clicked_unit := _get_unit_at(col, row)
			if clicked_unit != null and clicked_unit != _selected_unit:
				_select_unit(clicked_unit)
			# 点击空地 → 取消选中
			elif clicked_unit == null:
				_deselect_unit()

		CombatState.MOVE_MODE:
			# 点击移动范围高亮 → 移动
			if _move_range.has(clicked_grid):
				_move_unit_to(_selected_unit, col, row)
			else:
				# 点击非移动范围 → 取消移动模式，回到选中状态
				_cancel_move_mode()

		CombatState.ATTACK_MODE:
			# 点击攻击范围 → 执行攻击
			if _move_range.has(clicked_grid):
				_execute_attack_on_tile(col, row)
			else:
				_cancel_attack_mode()

		CombatState.SKILL_TARGET_MODE:
			# 点击技能范围 → 执行技能
			if _move_range.has(clicked_grid):
				_execute_skill_on_tile(_pending_skill_id, col, row)
			else:
				_cancel_skill_mode()

		CombatState.DIRECTION_MODE:
			# 方向选择：使用专用射线检测，避免高层地形抢占低层方向方块
			var dir_grid := _get_grid_for_direction(global_mouse)
			if _move_range.has(dir_grid):
				_apply_velocity_direction(dir_grid.x, dir_grid.y)
			else:
				_cancel_direction_mode()

		CombatState.JUMP_DOWN_MODE:
			# 跳下：使用专用射线检测（跳下方块悬空在角色高度，不在实际地形高度层）
			var jump_grid := _get_grid_for_jump_down(global_mouse)
			if jump_grid != Vector2i(-1, -1) and _move_range.has(jump_grid):
				_execute_jump_down(jump_grid.x, jump_grid.y)
			elif clicked_grid != Vector2i(-1, -1) and _move_range.has(clicked_grid):
				# 兜底：标准射线也能命中（目标地形高度与角色同层时）
				_execute_jump_down(col, row)
			else:
				_cancel_jump_down_mode()


## 方向选择射线检测：使用3D地形方块射线检测，获取2D格子坐标
func _get_grid_for_direction(screen_pos: Vector2) -> Vector2i:
	if subviewport_container == null or camera == null:
		return Vector2i(-1, -1)

	var svp := subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if svp == null:
		return Vector2i(-1, -1)

	var viewport_rect := subviewport_container.get_global_rect()
	var local_pos := screen_pos - viewport_rect.position
	var container_size := viewport_rect.size

	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > container_size.x or local_pos.y > container_size.y:
		return Vector2i(-1, -1)

	var viewport_pos := Vector2(
		local_pos.x / container_size.x * svp.size.x,
		local_pos.y / container_size.y * svp.size.y
	)

	# 使用3D射线检测地形方块
	var from := camera.project_ray_origin(viewport_pos)
	var to := from + camera.project_ray_normal(viewport_pos) * 100.0

	var world_3d := svp.get_world_3d()
	if world_3d == null:
		return Vector2i(-1, -1)
	var space_state := world_3d.direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 0b00000000_00000000_00000000_00000001
	params.collide_with_areas = false

	var result := space_state.intersect_ray(params)
	if not result.is_empty():
		var hit_pos: Vector3 = result["position"]
		var grid := _grid_from_world_pos(hit_pos)
		if _move_range.has(grid):
			return grid

	# 回退：使用数学方法遍历 _move_range 中的候选位置
	return _get_grid_from_svp_direction(viewport_pos)


## 方向模式回退检测：使用AABB数学方法遍历候选位置
func _get_grid_from_svp_direction(svp_pos: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)

	var from := camera.project_ray_origin(svp_pos)
	var to := from + camera.project_ray_normal(svp_pos) * 100.0
	var inv_transform := tile_container.global_transform.affine_inverse()
	var local_origin := inv_transform * from
	var local_ray := inv_transform.basis * camera.project_ray_normal(svp_pos)
	var half := TILE_SIZE * 0.45

	for pos in _move_range:
		if not (pos is Vector2i):
			continue
		var p := pos as Vector2i
		# 方向方块通常在单位所在高度（考虑空中高度）
		var display_layer := _get_unit_effective_layer(_direction_target)
		var aabb_center := Vector3(
			(p.x - (_grid_cols - 1) * 0.5) * TILE_SIZE,
			TILE_SIZE * (float(display_layer) + 0.5),
			(p.y - (_grid_rows - 1) * 0.5) * TILE_SIZE
		)
		var t := _ray_aabb_intersect(local_origin, local_ray, aabb_center, Vector3(half, half, half))
		if t > 0 and t < INF:
			return p

	return Vector2i(-1, -1)


## 跳下模式射线检测：使用3D地形方块检测获取2D格子坐标
func _get_grid_for_jump_down(screen_pos: Vector2) -> Vector2i:
	if subviewport_container == null or camera == null or _selected_unit == null:
		return Vector2i(-1, -1)

	var svp := subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if svp == null:
		return Vector2i(-1, -1)

	var viewport_rect := subviewport_container.get_global_rect()
	var local_pos := screen_pos - viewport_rect.position
	var container_size := viewport_rect.size

	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > container_size.x or local_pos.y > container_size.y:
		return Vector2i(-1, -1)

	var viewport_pos := Vector2(
		local_pos.x / container_size.x * svp.size.x,
		local_pos.y / container_size.y * svp.size.y
	)

	# 使用3D射线检测地形方块
	var from := camera.project_ray_origin(viewport_pos)
	var to := from + camera.project_ray_normal(viewport_pos) * 100.0

	var world_3d := svp.get_world_3d()
	if world_3d != null:
		var space_state := world_3d.direct_space_state
		var params := PhysicsRayQueryParameters3D.create(from, to)
		params.collision_mask = 0b00000000_00000000_00000000_00000001
		params.collide_with_areas = false

		var result := space_state.intersect_ray(params)
		if not result.is_empty():
			var hit_pos: Vector3 = result["position"]
			var grid := _grid_from_world_pos(hit_pos)
			if _move_range.has(grid):
				return grid

	# 回退：AABB数学方法（跳下方块悬浮在角色高度）
	var current_height := _get_unit_effective_layer(_selected_unit)
	var inv_transform := tile_container.global_transform.affine_inverse()
	var local_origin := inv_transform * from
	var local_ray := inv_transform.basis * camera.project_ray_normal(viewport_pos)
	var half := TILE_SIZE * 0.42

	for pos in _move_range:
		if not (pos is Vector2i):
			continue
		var p := pos as Vector2i
		var aabb_center := Vector3(
			(p.x - (_grid_cols - 1) * 0.5) * TILE_SIZE,
			TILE_SIZE * (float(current_height) + 1.0),
			(p.y - (_grid_rows - 1) * 0.5) * TILE_SIZE
		)
		var t := _ray_aabb_intersect(local_origin, local_ray, aabb_center, Vector3(half, 0.04, half))
		if t > 0 and t < INF:
			return p

	return Vector2i(-1, -1)


## 通过 SubViewport 坐标发射射线，获取命中的棋盘格子
## 核心逻辑：射线 → tile_container 本地空间 → 从高到低扫描每个高度层 → 遮挡检测
## 关键修复：从最高地形层开始扫描，而非从Y=0往上找
##   原因：等距视角下射线倾斜，Y=0交点与高地形交点的XZ偏移随高度急剧增大
##   height≥3时Y=0交点已偏移多个格子，迭代修正无法收敛
func _get_grid_from_svp(svp_pos: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)

	var ray_origin := camera.project_ray_origin(svp_pos)
	var ray_dir := camera.project_ray_normal(svp_pos)

	if ray_dir.y >= 0:
		return Vector2i(-1, -1)

	# 将射线转换到 tile_container 本地空间（网格在此空间内是轴对齐的）
	var inv_transform := tile_container.global_transform.affine_inverse()
	var local_origin := inv_transform * ray_origin
	var local_dir := inv_transform.basis * ray_dir

	# 从高到低扫描每个高度层，找到射线命中的第一个有效格子顶部
	# 每个高度 h 对应的方块顶部平面 Y = TILE_SIZE * (h + 1)
	# 如果射线在该高度平面的交点处，对应格子的高度 >= h，则命中
	var max_h := _get_max_terrain_height()
	for h in range(max_h, -1, -1):
		var target_y := TILE_SIZE * (h + 1)
		var t := (target_y - local_origin.y) / local_dir.y
		if t <= 0:
			continue  # 射线不到达此高度平面

		var hit_x := local_origin.x + t * local_dir.x
		var hit_z := local_origin.z + t * local_dir.z
		var grid := _world_to_grid(Vector3(hit_x, target_y, hit_z))

		if grid == Vector2i(-1, -1):
			continue  # 超出棋盘范围或被排除

		var cell_h := _get_tile_height(grid.x, grid.y)
		if cell_h >= h:
			# 该格子的顶部在此高度层或更高，射线命中了此格子的顶面
			# 遮挡检测：确认没有更高的前方格子遮挡
			if cell_h > 0:
				if _check_terrain_occlusion(local_origin, local_dir, grid, cell_h):
					continue  # 被遮挡，检查下一层
			return grid

	return Vector2i(-1, -1)


## 通过屏幕坐标获取棋盘格子坐标（二维）
## 使用射线检测地形方块碰撞体，能检测方块的任何面（顶面、侧面、底面）
func _get_grid_from_mouse(screen_pos: Vector2) -> Vector2i:
	if subviewport_container == null or camera == null:
		return Vector2i(-1, -1)

	var svp := subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if svp == null:
		return Vector2i(-1, -1)

	var viewport_rect := subviewport_container.get_global_rect()
	var local_pos := screen_pos - viewport_rect.position
	var container_size := viewport_rect.size

	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > container_size.x or local_pos.y > container_size.y:
		return Vector2i(-1, -1)

	var viewport_pos := Vector2(
		local_pos.x / container_size.x * svp.size.x,
		local_pos.y / container_size.y * svp.size.y
	)

	# 射线检测：同时检测地形（层1 StaticBody3D）和单位（层2 Area3D）
	var from := camera.project_ray_origin(viewport_pos)
	var to := from + camera.project_ray_normal(viewport_pos) * 100.0

	var world_3d := svp.get_world_3d()
	if world_3d != null:
		var space_state := world_3d.direct_space_state

		# 先检测单位（层2 Area3D）— 用于选取空中单位
		var unit_params := PhysicsRayQueryParameters3D.create(from, to)
		unit_params.collision_mask = 0b00000000_00000000_00000000_00000010
		unit_params.collide_with_areas = true
		unit_params.collide_with_bodies = false
		var unit_result := space_state.intersect_ray(unit_params)
		if not unit_result.is_empty():
			# 从 Area3D 向上查找 TacticsUnit 节点
			var node: Node = unit_result["collider"]
			while node != null:
				if node is TacticsUnit:
					var unit: TacticsUnit = node
					if not unit.is_dead():
						return unit.grid_pos
					break  # 死亡单位，继续检测地形
				node = node.get_parent()

		# 再检测地形（层1 StaticBody3D）
		var terrain_params := PhysicsRayQueryParameters3D.create(from, to)
		terrain_params.collision_mask = 0b00000000_00000000_00000000_00000001
		terrain_params.collide_with_areas = false
		terrain_params.collide_with_bodies = true
		var result := space_state.intersect_ray(terrain_params)
		if not result.is_empty():
			var hit_pos: Vector3 = result["position"]
			return _grid_from_world_pos(hit_pos)

	# 回退：平面扫描方法
	return _get_grid_from_svp(viewport_pos)


## 从世界坐标计算格子坐标
func _grid_from_world_pos(world_pos: Vector3) -> Vector2i:
	var col_f: float = world_pos.x / TILE_SIZE + (_grid_cols - 1) * 0.5
	var row_f: float = world_pos.z / TILE_SIZE + (_grid_rows - 1) * 0.5
	var col := floori(col_f + 0.5)
	var row := floori(row_f + 0.5)
	if not _is_valid_tile(col, row):
		return Vector2i(-1, -1)
	return Vector2i(col, row)


## 通过屏幕坐标获取三维格子坐标（包括高度层）
## 使用射线检测地形方块的碰撞体，返回 (col, row, layer)
func _get_3d_grid_from_mouse(screen_pos: Vector2) -> Vector3i:
	if subviewport_container == null or camera == null:
		return Vector3i(-1, -1, -1)

	var svp := subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if svp == null:
		return Vector3i(-1, -1, -1)

	var viewport_rect := subviewport_container.get_global_rect()
	var local_pos := screen_pos - viewport_rect.position
	var container_size := viewport_rect.size

	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > container_size.x or local_pos.y > container_size.y:
		return Vector3i(-1, -1, -1)

	var viewport_pos := Vector2(
		local_pos.x / container_size.x * svp.size.x,
		local_pos.y / container_size.y * svp.size.y
	)

	# 射线检测地形方块
	var from := camera.project_ray_origin(viewport_pos)
	var to := from + camera.project_ray_normal(viewport_pos) * 100.0

	var world_3d := svp.get_world_3d()
	if world_3d == null:
		return Vector3i(-1, -1, -1)
	var space_state := world_3d.direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	# 只检测第1层（地形方块）
	params.collision_mask = 0b00000000_00000000_00000000_00000001
	params.collide_with_areas = false

	var result := space_state.intersect_ray(params)
	if not result.is_empty():
		var hit_pos: Vector3 = result["position"]
		var grid_pos := _grid_from_world_pos(hit_pos)
		if grid_pos == Vector2i(-1, -1):
			return Vector3i(-1, -1, -1)
		var col := grid_pos.x
		var row := grid_pos.y
		# 计算高度层（从 Y 坐标推算）
		var layer := int(round(hit_pos.y / TILE_SIZE - 0.5))
		var tile_height := _get_tile_height(col, row)
		layer = clampi(layer, 0, tile_height)
		return Vector3i(col, row, layer)

	return Vector3i(-1, -1, -1)


## 检测射线是否被地形阻挡
## 在 XZ 平面上从目标格子向相机方向采样，检查中间格子是否遮挡射线
func _check_terrain_occlusion(local_origin: Vector3, local_dir: Vector3, target_grid: Vector2i, target_height: int) -> bool:
	var dir_xz := Vector2(local_dir.x, local_dir.z)
	if dir_xz.length_squared() < 0.000001:
		return false  # 垂直向下，不会被侧向遮挡

	dir_xz = dir_xz.normalized()

	# 目标格子的世界 XZ 中心
	var target_x := (target_grid.x - (_grid_cols - 1) * 0.5) * TILE_SIZE
	var target_z := (target_grid.y - (_grid_rows - 1) * 0.5) * TILE_SIZE

	# 射线到达目标 Y 平面的参数 t
	var target_y := TILE_SIZE * (target_height + 1)
	var t_target := (target_y - local_origin.y) / local_dir.y

	# 采样参数：步长为 0.25 个格子，确保不遗漏任何格子
	var step := TILE_SIZE * 0.25
	var max_dist := TILE_SIZE * float(_grid_cols + _grid_rows)

	var dist := step
	var last_grid := target_grid

	while dist < max_dist:
		# 从目标向相机方向步进（dir_xz 指向 target，反向即向相机）
		var sx := target_x - dir_xz.x * dist
		var sz := target_z - dir_xz.y * dist
		var check_grid := _world_to_grid(Vector3(sx, 0, sz))

		if check_grid == Vector2i(-1, -1) or check_grid == target_grid or check_grid == last_grid:
			dist += step
			continue

		last_grid = check_grid

		# 计算射线在该格子中心处的 Y 坐标
		var center_x := (check_grid.x - (_grid_cols - 1) * 0.5) * TILE_SIZE
		var center_z := (check_grid.y - (_grid_rows - 1) * 0.5) * TILE_SIZE
		var t: float
		if absf(local_dir.x) > absf(local_dir.z):
			t = (center_x - local_origin.x) / local_dir.x
		else:
			t = (center_z - local_origin.z) / local_dir.z

		# 跳过相机后方或目标后方的点
		if t <= 0.001 or t >= t_target - 0.001:
			dist += step
			continue

		var ray_y := local_origin.y + t * local_dir.y
		var cell_height := _get_tile_height(check_grid.x, check_grid.y)
		var cell_top_y := TILE_SIZE * (cell_height + 1)

		# 如果该格子顶部高于射线在该处的 Y，说明被遮挡
		if ray_y < cell_top_y - 0.01:
			return true

		dist += step

	return false


## 世界坐标 → 网格坐标（近似，用于点击检测）
func _world_to_grid(pos: Vector3) -> Vector2i:
	# 使用 floori 来获取格子坐标，避免边界处返回错误的格子
	var col_f := pos.x / TILE_SIZE + (_grid_cols - 1) * 0.5
	var row_f := pos.z / TILE_SIZE + (_grid_rows - 1) * 0.5
	var col := floori(col_f + 0.5)  # 四舍五入到最近的整数
	var row := floori(row_f + 0.5)

	if not _is_valid_tile(col, row):
		return Vector2i(-1, -1)
	return Vector2i(col, row)


# =============================================================================
# 单位选中 / 取消选中
# =============================================================================

## 选中单位
func _select_unit(unit: TacticsUnit) -> void:
	print("[TacticsBoard] _select_unit: unit=", unit.unit_id, " team=", unit.team)
	if unit == null:
		return

	# 只能选中己方单位
	if unit.team != "player":
		print("[TacticsBoard] _select_unit: 不是己方单位，跳过")
		return

	# 如果同一个单位，取消选中
	if _selected_unit == unit:
		print("[TacticsBoard] _select_unit: 同一单位，取消选中")
		_deselect_unit()
		return

	_deselect_unit()
	_selected_unit = unit
	_combat_state = CombatState.UNIT_SELECTED
	print("[TacticsBoard] _select_unit: 选中单位 ", unit.unit_id)

	# 显示名称标签
	var label: Label3D = unit.get_node_or_null("NameLabel") as Label3D
	if label:
		label.visible = true

	# 显示行动菜单
	_show_action_menu(unit)

	unit_selected.emit(unit)


## 取消选中
func _deselect_unit() -> void:
	if _selected_unit != null:
		var label: Label3D = _selected_unit.get_node_or_null("NameLabel") as Label3D
		if label:
			label.visible = false

	_close_action_menu()
	_selected_unit = null
	_combat_state = CombatState.IDLE
	_force_clear_all_wireframes()
	_highlight_type = ""


# =============================================================================
# 移动范围
# =============================================================================

## 显示移动范围（BFS 曼哈顿距离，使用剩余移动点数）
func _show_move_range(unit: TacticsUnit) -> void:
	_clear_move_range()

	# 空中单位不可通过移动命令移动
	if unit.physics.is_airborne:
		print("[TacticsBoard] 空中单位不可移动: %s air_height=%.2f" % [unit.unit_id, unit.physics.air_height])
		return

	var max_range: int = unit.remaining_move_points
	if max_range <= 0:
		return

	var start: Vector2i = unit.grid_pos
	var occupied_tiles: Dictionary = _get_occupied_tiles()

	# BFS
	var visited: Dictionary = {}
	var queue: Array = [start]
	visited[start] = 0

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var dist: int = visited[current]

		if dist >= max_range:
			continue

		# 四个方向
		var dirs: Array[Vector2i] = [
			Vector2i(0, -1), Vector2i(1, 0),
			Vector2i(0, 1), Vector2i(-1, 0)
		]

		for d in dirs:
			var next_pos := current + d
			if not _is_valid_tile(next_pos.x, next_pos.y):
				continue
			if visited.has(next_pos):
				continue

			# 检查高度差（不能超过 1）
			# 可通过地形：高度差放宽（可无障碍通过，但仍需相邻高度）
			var current_height := _get_tile_height(current.x, current.y)
			var next_height := _get_tile_height(next_pos.x, next_pos.y)
			if absi(next_height - current_height) > 1:
				continue

			# 可通过地形：无障碍穿过，即使被其他单位占据
			if occupied_tiles.has(next_pos) and next_pos != start:
				if _is_tile_passable(next_pos.x, next_pos.y):
					pass  # 可通过地形，允许穿过
				else:
					continue

			visited[next_pos] = dist + 1
			queue.append(next_pos)

	# 移除起点
	visited.erase(start)

	# 创建高亮立方体
	for pos in visited.keys():
		_create_move_range_cube(pos.x, pos.y)
		_move_range.append(pos)

	_highlight_type = "move"


## 清除移动范围高亮
func _clear_move_range() -> void:
	for cube in _move_range_cubes:
		if is_instance_valid(cube):
			cube.queue_free()
	_move_range_cubes.clear()
	_move_range.clear()
	_hovered_wireframe_idx = -1  # 重置悬浮索引


## 强制清除所有残留线框（包括 _move_range_cubes 列表之外的孤儿线框）
## 扫描 tile_container 中所有以线框前缀命名的节点并删除
func _force_clear_all_wireframes() -> void:
	# 先执行正常清除
	_clear_move_range()

	# 扫描 tile_container 中残留的线框节点
	if tile_container == null:
		return
	var to_remove: Array = []
	for child in tile_container.get_children():
		var name: String = child.name
		if name.begins_with("ThrowTarget_") or name.begins_with("ThrowDir_") or \
		   name.begins_with("Interact_") or name.begins_with("Direction_"):
			to_remove.append(child)
		elif child is MeshInstance3D and child != _selected_unit:
			# 移动范围高亮方块（半透明薄片）
			var mesh_inst: MeshInstance3D = child
			if mesh_inst.mesh is BoxMesh:
				var box: BoxMesh = mesh_inst.mesh
				# 移动范围方块特征：非常薄（Y < 0.1）
				if box.size.y < 0.1:
					to_remove.append(child)
	for node in to_remove:
		tile_container.remove_child(node)
		node.queue_free()


## 创建移动范围高亮立方体
func _create_move_range_cube(col: int, row: int) -> void:
	var cube := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TILE_SIZE * 0.9, 0.05, TILE_SIZE * 0.9)
	cube.mesh = mesh

	var height := _get_tile_height(col, row)
	var pos := _grid_to_world(col, row)
	# 可通过地形：标识显示在内部（与单位同层），不可通过：显示在表面
	if _is_tile_passable(col, row):
		cube.position = Vector3(pos.x, TILE_SIZE * height + 0.02, pos.z)
	else:
		cube.position = Vector3(pos.x, TILE_SIZE * (height + 1) + 0.02, pos.z)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cube.material_override = mat

	tile_container.add_child(cube)
	_move_range_cubes.append(cube)


# =============================================================================
# 单位移动
# =============================================================================

## 移动单位到目标格子 — 处理矢量速度交互和移动点数消耗
func _move_unit_to(unit: TacticsUnit, col: int, row: int) -> void:
	if unit == null:
		return

	# 空中单位不能通过移动命令移动
	if unit.physics.is_airborne:
		print("[TacticsBoard] 空中单位不可移动: %s air_height=%.2f" % [unit.unit_id, unit.physics.air_height])
		return

	var from_pos := unit.grid_pos

	# 计算移动距离（曼哈顿距离）
	var raw_dir := Vector2(col - from_pos.x, row - from_pos.y)
	var distance: int = absi(raw_dir.x) + absi(raw_dir.y)
	if distance <= 0:
		return

	# 高度差：主动移动时，1格落差无坠落伤害
	var current_height := _get_tile_height(from_pos.x, from_pos.y)
	var next_height := _get_tile_height(col, row)
	var height_diff := next_height - current_height
	if height_diff < 0 and absi(height_diff) == 1:
		pass  # 1格落差：主动移动不触发坠落伤害

	# 消耗移动点数并执行移动
	unit.remaining_move_points -= distance

	# 执行移动
	unit.set_grid_pos(col, row)
	unit.position = _grid_to_world_top(col, row)

	# 更新 _unit_data
	if _unit_data.has(unit.unit_id):
		_unit_data[unit.unit_id]["col"] = col
		_unit_data[unit.unit_id]["row"] = row

	_clear_move_range()
	unit_moved.emit(unit, from_pos, Vector2i(col, row))

	# 移动后：如果还有移动点数且未行动，重新显示行动菜单
	if unit.remaining_move_points > 0 or not unit.has_acted:
		_combat_state = CombatState.UNIT_SELECTED
		_show_action_menu(unit)
	else:
		# 无法再行动，结束回合
		_end_current_unit_turn()


# =============================================================================
# 行动菜单
# =============================================================================

## 显示行动菜单（移动 / 攻击 / 技能 / 动作 / 待机）
func _show_action_menu(unit: TacticsUnit) -> void:
	_close_action_menu()
	_action_menu_visible = true
	_action_sub_menu_visible = false

	var menu := Panel.new()
	menu.name = "ActionMenu"
	menu.size = Vector2(220, 220)
	menu.position = Vector2(20, 20)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "ActionVBox"
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = unit.unit_name + " — 速度: " + str(unit.remaining_move_points)
	if unit.physics.velocity.length() > 0.01:
		title.text += " | 矢量: %.1f" % unit.physics.velocity.length()
	title.text += " | 质量: %.1f" % unit.physics.mass
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	# 移动按钮（始终可用，只要有移动点数）
	if unit.remaining_move_points > 0:
		var move_btn := _create_action_button("移动 (%d步)" % unit.remaining_move_points, _on_action_move)
		vbox.add_child(move_btn)

	# 攻击按钮（每回合只能一次）
	if not unit.has_acted:
		var atk_btn := _create_action_button("攻击", _on_action_attack)
		vbox.add_child(atk_btn)

		# 技能按钮
		var skill_btn := _create_action_button("技能", _on_skill_sub_menu)
		vbox.add_child(skill_btn)

	# 动作按钮（始终可用，只要有移动点数）
	if unit.remaining_move_points > 0:
		var action_btn := _create_action_button("动作", _on_action_sub_menu)
		vbox.add_child(action_btn)

	# 待机按钮
	var wait_btn := _create_action_button("待机", _on_action_wait)
	vbox.add_child(wait_btn)

	menu.add_child(vbox)
	add_child(menu)


## 创建行动菜单按钮
func _create_action_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_FILL
	btn.pressed.connect(callback)
	return btn


## 移动行动 — 进入移动模式
func _on_action_move() -> void:
	_close_action_menu()

	if _selected_unit == null:
		return

	_combat_state = CombatState.MOVE_MODE
	_show_move_range(_selected_unit)


## 攻击行动
func _on_action_attack() -> void:
	_close_action_menu()

	if _selected_unit == null:
		return

	# 显示攻击范围（以单位为基准，1格范围）
	_combat_state = CombatState.ATTACK_MODE
	_show_attack_range(_selected_unit)


## 技能行动
func _on_action_skill() -> void:
	_close_action_menu()

	if _selected_unit == null:
		return

	var skills := _selected_unit.get_skills()
	if skills.is_empty():
		return

	# 显示技能选择菜单
	_show_skill_menu(_selected_unit, skills)


## 待机行动
func _on_action_wait() -> void:
	_close_action_menu()
	_selected_unit.has_acted = true
	_end_current_unit_turn()


## 取消移动模式
func _cancel_move_mode() -> void:
	_clear_move_range()
	_combat_state = CombatState.UNIT_SELECTED
	_show_action_menu(_selected_unit)


## 取消攻击模式
func _cancel_attack_mode() -> void:
	_clear_move_range()
	_combat_state = CombatState.UNIT_SELECTED
	_show_action_menu(_selected_unit)


## 取消技能模式
func _cancel_skill_mode() -> void:
	_clear_move_range()
	_combat_state = CombatState.UNIT_SELECTED
	_show_action_menu(_selected_unit)


## 取消方向选择模式
func _cancel_direction_mode() -> void:
	_clear_move_range()
	_direction_target = null
	_combat_state = CombatState.SKILL_TARGET_MODE
	# 重新显示技能范围
	_show_skill_range(_selected_unit, _pending_skill_id)


## 关闭行动菜单
func _close_action_menu() -> void:
	_action_menu_visible = false
	var menu := get_node_or_null("ActionMenu")
	if menu:
		menu.queue_free()


# =============================================================================
# 动作子菜单
# =============================================================================

## 显示动作子菜单（跳下 / 交互 / 投掷）
func _on_action_sub_menu() -> void:
	# 关闭已有的子菜单
	_close_action_sub_menu()
	_action_sub_menu_visible = true

	var sub_menu := Panel.new()
	sub_menu.name = "ActionSubMenu"
	sub_menu.size = Vector2(160, 130)  # 增加高度以容纳投掷按钮
	# 定位在动作按钮右侧
	sub_menu.position = Vector2(245, 20)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	sub_menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "动作"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	vbox.add_child(title)

	# 投掷按钮
	var throw_btn := _create_action_button("投掷", _on_action_throw)
	vbox.add_child(throw_btn)

	# 跳下按钮
	var jump_btn := _create_action_button("跳下", _on_action_jump_down)
	vbox.add_child(jump_btn)

	# 交互按钮
	var interact_btn := _create_action_button("交互", _on_action_interact)
	vbox.add_child(interact_btn)

	sub_menu.add_child(vbox)
	add_child(sub_menu)


## 关闭弹出子菜单（动作/技能通用）
func _close_action_sub_menu() -> void:
	_action_sub_menu_visible = false
	var sub := get_node_or_null("ActionSubMenu")
	if sub:
		sub.queue_free()
	var sub2 := get_node_or_null("SkillSubMenu")
	if sub2:
		sub2.queue_free()


# =============================================================================
# 技能子菜单
# =============================================================================

## 显示技能子菜单（和动作子菜单同一风格）
func _on_skill_sub_menu() -> void:
	_close_action_sub_menu()
	_action_sub_menu_visible = true

	if _selected_unit == null:
		return

	var skills := _selected_unit.get_skills()
	if skills.is_empty():
		return

	var sub_menu := Panel.new()
	sub_menu.name = "SkillSubMenu"
	sub_menu.size = Vector2(180, 40 + skills.size() * 44)
	sub_menu.position = Vector2(245, 60)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	sub_menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "技能"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 0.8))
	vbox.add_child(title)

	for skill in skills:
		var btn := _create_action_button(skill.get("name", skill.get("id", "???")), \
			_on_skill_selected_from_sub.bind(skill.get("id", "")))
		vbox.add_child(btn)

	sub_menu.add_child(vbox)
	add_child(sub_menu)


## 从子菜单中选择技能后的回调
func _on_skill_selected_from_sub(skill_id: String) -> void:
	_close_action_sub_menu()
	_close_action_menu()

	if _selected_unit == null:
		return

	_pending_skill_id = skill_id
	_combat_state = CombatState.SKILL_TARGET_MODE
	_show_skill_range(_selected_unit, skill_id)


# =============================================================================
# 跳下动作
# =============================================================================

## 显示跳下目标范围：周围八格中低于当前高度2格及以上的格子
func _on_action_jump_down() -> void:
	_close_action_sub_menu()
	_close_action_menu()

	if _selected_unit == null:
		return

	_combat_state = CombatState.JUMP_DOWN_MODE
	_show_jump_down_range(_selected_unit)


## 投掷动作：进入投掷目标选择模式
func _on_action_throw() -> void:
	_close_action_sub_menu()
	_close_action_menu()

	if _selected_unit == null:
		return

	# 投掷是动作而非技能，不设置 _pending_skill_id
	_combat_state = CombatState.THROW_TARGET_MODE
	_show_throw_target_range(_selected_unit)


func _show_jump_down_range(unit: TacticsUnit) -> void:
	_clear_move_range()
	var center := unit.grid_pos
	var current_height := _get_unit_effective_layer(unit)

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var tx := center.x + dx
			var ty := center.y + dy
			if not _is_valid_tile(tx, ty):
				continue

			# 只选择低于当前高度2格及以上的格子
			var target_height := _get_tile_height(tx, ty)
			var height_diff := current_height - target_height
			if height_diff >= 2:
				_create_jump_down_cube(tx, ty, current_height)
				_move_range.append(Vector2i(tx, ty))

	_highlight_type = "jump_down"


## 创建跳下目标高亮立方体（红色半透明，悬空在角色同一高度）
## @param display_height: 角色当前所在高度，立方体悬浮在此高度而非目标地面
func _create_jump_down_cube(col: int, row: int, display_height: int) -> void:
	var cube := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TILE_SIZE * 0.85, 0.08, TILE_SIZE * 0.85)
	cube.mesh = mesh

	var pos := _grid_to_world(col, row)
	# 立方体悬空在角色同一高度，而不是落在地面上
	cube.position = Vector3(pos.x, TILE_SIZE * (display_height + 1) + 0.04, pos.z)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.1, 0.5)  # 红色 = 危险/跳下
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cube.material_override = mat

	tile_container.add_child(cube)
	_move_range_cubes.append(cube)


## 执行跳下：强制移动到目标位置，设置空中状态，消耗1点移动点数
func _execute_jump_down(col: int, row: int) -> void:
	_clear_move_range()

	if _selected_unit == null:
		return

	var from_pos := _selected_unit.grid_pos
	var target_pos := Vector2i(col, row)

	# 消耗1点移动点数
	_selected_unit.remaining_move_points -= 1

	# 计算高度差
	var current_height := _get_tile_height(from_pos.x, from_pos.y)
	var target_height := _get_tile_height(col, row)
	var height_diff := current_height - target_height

	# 移动到目标位置（悬空状态）
	_selected_unit.set_grid_pos(col, row)
	_selected_unit.physics.air_height = float(height_diff)
	_selected_unit.physics.fall_height = float(height_diff)
	_selected_unit.physics.is_airborne = true
	_selected_unit.physics.velocity = Vector2.ZERO
	_selected_unit.position = _grid_to_world_top(col, row, -1, float(height_diff))

	# 更新 _unit_data
	if _unit_data.has(_selected_unit.unit_id):
		_unit_data[_selected_unit.unit_id]["col"] = col
		_unit_data[_selected_unit.unit_id]["row"] = row

	unit_moved.emit(_selected_unit, from_pos, target_pos)

	print("[TacticsBoard] 跳下: %s (%d,%d)→(%d,%d) 高度差=%d 进入自由落体" % [
		_selected_unit.unit_id, from_pos.x, from_pos.y, col, row, height_diff
	])

	# 跳下后：如果还有移动点数且未行动，重新显示菜单
	if _selected_unit.remaining_move_points > 0 or not _selected_unit.has_acted:
		_combat_state = CombatState.UNIT_SELECTED
		_show_action_menu(_selected_unit)
	else:
		_end_current_unit_turn()


## 取消跳下模式
func _cancel_jump_down_mode() -> void:
	_clear_move_range()
	_combat_state = CombatState.UNIT_SELECTED
	_show_action_menu(_selected_unit)


# =============================================================================
# 交互动作
# =============================================================================

## 显示交互目标范围：周围八格中同层且可交互的地形
func _on_action_interact() -> void:
	_close_action_sub_menu()
	_close_action_menu()

	if _selected_unit == null:
		return

	_combat_state = CombatState.INTERACT_MODE
	_show_interact_range(_selected_unit)


func _show_interact_range(unit: TacticsUnit) -> void:
	_clear_move_range()
	var center := unit.grid_pos
	var current_height := _get_unit_effective_layer(unit)

	# 显示8个相邻格子的白色线框（无论是否可交互）
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var tx := center.x + dx
			var ty := center.y + dy
			if not _is_valid_tile(tx, ty):
				continue

			# 显示白色线框（无论是否可交互）
			var target_height := _get_tile_height(tx, ty)
			_create_interact_wireframe_cube(tx, ty, target_height)

			# 高度差 ≤ 1 且可交互的地形才能点击
			if absi(target_height - current_height) <= 1 and _is_tile_interactive(tx, ty):
				_move_range.append(Vector3i(tx, ty, target_height))

	# 头顶：同col/row，高度+1（如果可交互）
	var above_height := current_height + 1
	_create_interact_wireframe_cube(center.x, center.y, above_height)
	if _is_tile_interactive(center.x, center.y):
		_move_range.append(Vector3i(center.x, center.y, above_height))

	# 脚下：同col/row，高度-1（如果 >= 0 且可交互）
	if current_height > 0:
		var below_height := current_height - 1
		_create_interact_wireframe_cube(center.x, center.y, below_height)
		if _is_tile_interactive(center.x, center.y):
			_move_range.append(Vector3i(center.x, center.y, below_height))

	_highlight_type = "interact"


## 判断指定格子是否为可交互地形（usage_type == INTERACTIVE）
func _is_tile_interactive(col: int, row: int) -> bool:
	if _terrain_manager == null:
		return false
	var key := Vector2i(col, row)
	var instance := _terrain_manager.get_terrain_instance(key)
	if instance == null:
		return false
	var terrain_type := _terrain_manager.get_terrain_type(instance.terrain_type_id)
	if terrain_type == null:
		return false
	return terrain_type.is_interactive


## 判断指定格子是否为可通过地形（is_passable == true）
func _is_tile_passable(col: int, row: int) -> bool:
	if _terrain_manager == null:
		return true  # 无地形管理器时默认可通过
	return _terrain_manager.is_terrain_passable(Vector2i(col, row))


## 创建交互目标白色线框立方体（只有棱、无面）
func _create_interact_wireframe_cube(col: int, row: int, wire_height: int = -1) -> void:
	var height: int = wire_height if wire_height >= 0 else _get_tile_height(col, row)
	_create_wireframe_cube(col, row, height, "Interact", Color(1.0, 1.0, 1.0, 0.85))


## 执行交互：将可交互地形转换为目标地形
func _execute_interact(col: int, row: int) -> void:
	_clear_move_range()

	if _selected_unit == null or _terrain_manager == null:
		return

	var key := Vector2i(col, row)
	var instance := _terrain_manager.get_terrain_instance(key)
	if instance == null:
		return

	var old_type_id := instance.terrain_type_id
	var terrain_type := _terrain_manager.get_terrain_type(old_type_id)
	if terrain_type == null or not terrain_type.is_interactive or terrain_type.transform_to_id.is_empty():
		return

	# 交互前检查目标地形的可通过性
	var target_type_id: String = terrain_type.transform_to_id
	var target_type := _terrain_manager.get_terrain_type(target_type_id)
	var unit_on_tile := _get_unit_at(col, row)
	if unit_on_tile != null and unit_on_tile != _selected_unit:
		if target_type != null and not target_type.is_passable:
			# 目标地形不可通过且有单位站在上面，阻止交互
			print("[TacticsBoard] 交互阻止: (%d,%d) 目标地形 %s 不可通过，但 %s 站在上面" % [
				col, row, target_type_id, unit_on_tile.unit_id
			])
			_cancel_interact_mode()
			return
		# 目标地形可通过：允许交互（单位可以站在可通过地形内部）

	# 在TerrainManager中执行交互（获取转换后的类型ID）
	var result := _terrain_manager.interact_terrain(key)
	if not result.get("success", false):
		print("[TacticsBoard] 交互失败: (%d,%d) type=%s" % [col, row, old_type_id])
		return

	var new_type_id: String = result.get("new_type_id", "")

	# 始终更新 _terrain_data（即使是 fallback 地块也要创建条目）
	if not _terrain_data.has(key):
		_terrain_data[key] = {}
	_terrain_data[key]["type_id"] = new_type_id
	var new_terrain_type := _terrain_manager.get_terrain_type(new_type_id)
	if new_terrain_type != null:
		_terrain_data[key]["height"] = new_terrain_type.base_height
		# 重建 layers 数组：每层使用新地形类型（完整转换）
		var new_layers: Array = []
		for i in range(new_terrain_type.base_height + 1):
			new_layers.append(new_type_id)
		_terrain_data[key]["layers"] = new_layers
		print("[TacticsBoard] 交互 layers 更新: (%d,%d) layers=%s" % [col, row, new_layers])

	# 重建该格子的视觉方块（先清除旧方块 + 更新 _tiles 引用）
	_clear_tiles_at(col, row)
	_build_single_tile(col, row)
	# 更新 _tiles 数组中的引用（指向新创建的节点）
	var new_tile_node := _find_tile_node(col, row)
	if new_tile_node != null and row < _tiles.size() and col < _tiles[row].size():
		_tiles[row][col] = new_tile_node

	# 如果该格子上有单位，更新其视觉位置（可通过性可能变化）
	var unit_here := _get_unit_at(col, row)
	if unit_here != null:
		unit_here.position = _grid_to_world_top(col, row, -1, unit_here.physics.air_height)

	# 交互后：消耗1点移动点数
	var old_mp := _selected_unit.remaining_move_points
	_selected_unit.remaining_move_points -= 1
	print("[TacticsBoard] 移动点数消耗: %s %d → %d" % [
		_selected_unit.unit_id, old_mp, _selected_unit.remaining_move_points
	])

	print("[TacticsBoard] 交互: (%d,%d) %s → %s" % [col, row, old_type_id, new_type_id])

	# 交互后：如果还有移动点数且未行动，重新显示菜单
	if _selected_unit.remaining_move_points > 0 or not _selected_unit.has_acted:
		_combat_state = CombatState.UNIT_SELECTED
		_show_action_menu(_selected_unit)
	else:
		_end_current_unit_turn()


## 取消交互模式
func _cancel_interact_mode() -> void:
	_clear_move_range()
	_combat_state = CombatState.UNIT_SELECTED
	_show_action_menu(_selected_unit)


# =============================================================================
# 地形重建辅助
# =============================================================================

## 清除指定格子的所有方块节点（立即从场景树移除，防止新旧节点共存）
func _clear_tiles_at(col: int, row: int) -> void:
	var cube_name := "Cube_%d_%d" % [col, row]
	for child in tile_container.get_children():
		if child.name == cube_name and child is Node3D:
			tile_container.remove_child(child)  # 立即从场景树移除
			child.queue_free()
	print("[TacticsBoard] _clear_tiles_at: 已清除 (%d,%d) 的旧方块" % [col, row])


## 查找指定格子的方块节点（用于更新 _tiles 引用）
func _find_tile_node(col: int, row: int) -> Node3D:
	var cube_name := "Cube_%d_%d" % [col, row]
	for child in tile_container.get_children():
		if child.name == cube_name and child is Node3D:
			return child
	return null

## 为单格重建方块（使用_terrain_data中的最新数据，含每层类型）
func _build_single_tile(col: int, row: int) -> void:
	var key := Vector2i(col, row)
	var terrain: Dictionary = _terrain_data.get(key, {})
	var height: int = terrain.get("height", 0)
	var type_id: String = terrain.get("type_id", "")
	var layers: Array = terrain.get("layers", [])

	print("[TacticsBoard] _build_single_tile: (%d,%d) type_id=%s height=%d layers=%s" % [col, row, type_id, height, layers])

	if type_id.is_empty():
		print("[TacticsBoard] _build_single_tile: type_id为空，跳过重建")
		return

	var tile_node := _create_cube_tile(col, row, height, type_id, layers)
	tile_container.add_child(tile_node)
	print("[TacticsBoard] _build_single_tile: 新方块已添加到场景树 node=%s" % tile_node.name)


func _show_attack_range(unit: TacticsUnit) -> void:
	_clear_move_range()
	var center := unit.grid_pos
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var tx := center.x + dx
			var ty := center.y + dy
			if not _is_valid_tile(tx, ty):
				continue
			_create_move_range_cube(tx, ty)
			_move_range.append(Vector2i(tx, ty))
	_highlight_type = "attack"


## 显示技能菜单
func _show_skill_menu(unit: TacticsUnit, skills: Array) -> void:
	_action_menu_visible = true

	var menu := Panel.new()
	menu.name = "SkillMenu"
	menu.size = Vector2(220, 40 + skills.size() * 44)
	menu.position = Vector2(20, 20)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "SkillVBox"
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "选择技能"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	for skill in skills:
		var btn := Button.new()
		btn.text = skill.get("name", skill.get("id", "???"))
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_FILL

		var skill_id: String = skill.get("id", "")
		btn.pressed.connect(_on_skill_selected.bind(skill_id))
		vbox.add_child(btn)

	# 取消按钮
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(0, 36)
	cancel.size_flags_horizontal = Control.SIZE_FILL
	cancel.pressed.connect(_close_skill_menu)
	vbox.add_child(cancel)

	menu.add_child(vbox)
	add_child(menu)


## 技能选择
func _on_skill_selected(skill_id: String) -> void:
	_close_skill_menu()
	_close_action_menu()

	if _selected_unit == null:
		return

	var skill_data: Dictionary = _skill_system.get_skill(skill_id)
	if skill_data.is_empty():
		return

	# 检查是否为投掷技能（range_mode == "cube_26"）
	var range_mode: String = skill_data.get("range_mode", "")
	if range_mode == "cube_26":
		# 进入投掷目标选择模式
		_pending_skill_id = skill_id
		_combat_state = CombatState.THROW_TARGET_MODE
		_show_throw_target_range(_selected_unit)
		return

	_pending_skill_id = skill_id
	_combat_state = CombatState.SKILL_TARGET_MODE
	_show_skill_range(_selected_unit, skill_id)


## 显示技能范围
func _show_skill_range(unit: TacticsUnit, skill_id: String) -> void:
	_clear_move_range()

	var skill_range: int = _skill_system.get_skill_range(skill_id)
	var center := unit.grid_pos
	for dy in range(-skill_range, skill_range + 1):
		for dx in range(-skill_range, skill_range + 1):
			if dx == 0 and dy == 0:
				continue
			var tx := center.x + dx
			var ty := center.y + dy
			if not _is_valid_tile(tx, ty):
				continue
			_create_move_range_cube(tx, ty)
			_move_range.append(Vector2i(tx, ty))
	_highlight_type = "skill"


## 关闭技能菜单
func _close_skill_menu() -> void:
	_action_menu_visible = false
	var menu := get_node_or_null("SkillMenu")
	if menu:
		menu.queue_free()


## 在指定格子上执行攻击
func _execute_attack_on_tile(col: int, row: int) -> void:
	_clear_move_range()
	_pending_action = ""
	_pending_skill_id = ""

	if _selected_unit == null:
		return

	var target := _get_unit_at(col, row)
	if target == null:
		return

	# 基础攻击伤害
	var damage := maxi(1, _selected_unit.atk - target.def)
	target.take_damage(damage)

	_selected_unit.has_acted = true

	# 攻击后：如果还有移动点数，重新显示菜单
	if _selected_unit.remaining_move_points > 0:
		_combat_state = CombatState.UNIT_SELECTED
		_show_action_menu(_selected_unit)
	else:
		_end_current_unit_turn()


## 在指定格子上执行技能
func _execute_skill_on_tile(skill_id: String, col: int, row: int) -> void:
	_clear_move_range()

	if _selected_unit == null:
		return

	var target := _get_unit_at(col, row)
	if target == null:
		return

	# 检查技能是否需要方向选择
	var skill_data: Dictionary = _skill_system.get_skill(skill_id)
	if skill_data.is_empty():
		return

	# 检查是否有需要方向选择的效果（add_velocity 或 apply_momentum）
	var has_direction_select: bool = false
	for effect in skill_data.get("effects", []):
		var etype: String = effect.get("type", "")
		if (etype == "add_velocity" or etype == "apply_momentum") and effect.get("direction_select", false):
			has_direction_select = true
			break

	if has_direction_select:
		# 进入方向选择模式
		_direction_target = target
		_pending_skill_id = skill_id
		_combat_state = CombatState.DIRECTION_MODE
		_show_direction_ui(target)
		return

	# 普通技能：直接执行
	var result := _skill_system.execute_skill(skill_id, _selected_unit, target)
	if result.get("success", false):
		_selected_unit.has_acted = true

		# 技能后：如果还有移动点数，重新显示菜单
		if _selected_unit.remaining_move_points > 0:
			_combat_state = CombatState.UNIT_SELECTED
			_show_action_menu(_selected_unit)
		else:
			_end_current_unit_turn()


# =============================================================================
# 8方向选择 — 推击技能用
# =============================================================================

## 显示8方向选择UI
func _show_direction_ui(target: TacticsUnit) -> void:
	_clear_move_range()
	var center := target.grid_pos

	for offset in PhysicsSystem.DIRECTION_OFFSETS:
		var tx := center.x + offset.x
		var ty := center.y + offset.y
		if not _is_valid_tile(tx, ty):
			continue
		_create_direction_cube(tx, ty)
		_move_range.append(Vector2i(tx, ty))

	_highlight_type = "direction"


## 创建方向选择高亮（箭头状）
## 使用目标单位的有效高度层（考虑空中高度），确保方向方块与单位在同一视觉高度
func _create_direction_cube(col: int, row: int) -> void:
	var cube := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TILE_SIZE * 0.8, 0.06, TILE_SIZE * 0.8)
	cube.mesh = mesh

	# 使用目标单位的有效高度（考虑空中状态），而非地形高度
	var display_layer := _get_unit_effective_layer(_direction_target) if _direction_target != null else _get_tile_height(col, row)
	var pos := _grid_to_world(col, row)
	cube.position = Vector3(pos.x, TILE_SIZE * (display_layer + 1) + 0.03, pos.z)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cube.material_override = mat

	tile_container.add_child(cube)
	_move_range_cubes.append(cube)


## 应用矢量速度方向（推击技能）
## 委托给 PhysicsSystem 处理实际的物理计算
func _apply_velocity_direction(col: int, row: int) -> void:
	_clear_move_range()

	if _direction_target == null or _selected_unit == null:
		return

	var skill_data := _skill_system.get_skill(_pending_skill_id)
	if not skill_data.is_empty():
		_physics_system.apply_velocity_direction(
			_direction_target,
			_direction_target.grid_pos,
			col, row,
			skill_data
		)

	# 推击执行后强制清除所有残留线框
	_force_clear_all_wireframes()

	_direction_target = null
	_pending_skill_id = ""
	_selected_unit.has_acted = true

	# 技能后：如果还有移动点数，重新显示菜单
	if _selected_unit.remaining_move_points > 0:
		_combat_state = CombatState.UNIT_SELECTED
		_show_action_menu(_selected_unit)
	else:
		_end_current_unit_turn()


# =============================================================================
# 矢量速度结算 — 委托给 PhysicsSystem
# =============================================================================

## 结算单位的矢量速度（委托给 PhysicsSystem）
func _settle_velocity(unit: TacticsUnit) -> void:
	_physics_system.settle_velocity(unit)


## 获取地块摩擦系数（委托给 PhysicsSystem）
func _get_tile_friction(col: int, row: int) -> float:
	return _physics_system.get_tile_friction(col, row)


# =============================================================================
# 回合管理 — 集成 TurnManager
# =============================================================================

## 每轮开始时统一刷新所有单位的状态
func _on_round_started(round_num: int) -> void:
	print("[TacticsBoard] _on_round_started: round=", round_num)
	for unit in _turn_manager.get_alive_units():
		var friction: float = _get_tile_friction(unit.grid_pos.x, unit.grid_pos.y)
		unit.remaining_move_points = unit.get_move_points(friction)
		unit.has_acted = false

## 每轮结束时处理
## 注意：矢量速度结算已在 _end_current_unit_turn 中逐单位执行，不再在此统一结算
func _on_round_ended(round_num: int) -> void:
	print("[TacticsBoard] _on_round_ended: round=", round_num)

## 回合开始
func _on_battle_turn_started(unit: TacticsUnit) -> void:
	print("[TacticsBoard] _on_battle_turn_started: unit=", unit.unit_id, " team=", unit.team)

	# 初始化移动点数（空中单位无法移动）
	var friction: float = _get_tile_friction(unit.grid_pos.x, unit.grid_pos.y)
	unit.remaining_move_points = unit.get_move_points(friction)
	unit.has_acted = false

	_is_player_turn = (unit.team == "player")

	_deselect_unit()
	turn_changed.emit(unit)

	# 按队伍分派回合行为
	match unit.team:
		"player":
			pass  # 等待玩家输入
		"enemy":
			_enemy_ai_act(unit)
		"neutral":
			# 中立单位：暂无 AI，自动跳过
			_end_current_unit_turn()
		_:
			_end_current_unit_turn()


## 回合结束
func _on_battle_turn_ended(unit: TacticsUnit) -> void:
	_force_clear_all_wireframes()


## 所有行动结束
func _on_all_actions_done() -> void:
	# 检查胜负条件
	var result := _check_conditions()
	if not result.is_empty():
		_on_battle_conclusion(result)
		return

	# 没有触发条件，继续下一回合
	if _turn_manager:
		_turn_manager.start_battle()


## 结束当前单位行动
func _end_current_unit_turn() -> void:
	_combat_state = CombatState.IDLE
	_deselect_unit()

	# 矢量速度结算（在回合结束前滑动）
	if _turn_manager:
		var current_unit := _turn_manager.get_current_unit()
		if current_unit != null:
			_settle_velocity(current_unit)

	if _turn_manager:
		_turn_manager.end_current_turn()


## 战斗单位死亡回调
func _on_battle_unit_died(unit: TacticsUnit) -> void:
	# 更新 _unit_data
	if _unit_data.has(unit.unit_id):
		_unit_data[unit.unit_id]["alive"] = false

	# 检查胜负条件
	var result := _check_conditions()
	if not result.is_empty():
		_on_battle_conclusion(result)


## 战斗结果处理
func _on_battle_conclusion(result: Dictionary) -> void:
	# 获取对应分支的 next（支持 string 或 {file, node} 字典格式）
	var branch_id: String = result.get("branch", "")
	var next_target: Variant = ""

	# 查找对应条件
	var conditions: Array
	if result["type"] == "win":
		conditions = _win_conditions
	else:
		conditions = _lose_conditions

	for cond in conditions:
		if cond.get("id", "") == branch_id:
			next_target = cond.get("next", "")
			break

	# 发出战斗结果信号
	result["next"] = next_target
	battle_result.emit(result)
	battle_ended.emit(result["type"])


# =============================================================================
# 简易 AI — 敌方单位自动行动
# =============================================================================

## 敌方 AI 行动
func _enemy_ai_act(unit: TacticsUnit) -> void:
	# 初始化移动点数（空中单位无法移动）
	var friction: float = _get_tile_friction(unit.grid_pos.x, unit.grid_pos.y)
	unit.remaining_move_points = unit.get_move_points(friction)
	unit.has_acted = false

	# 找到最近的己方单位
	var nearest_player: TacticsUnit = null
	var nearest_dist: int = 999

	for player_unit in _turn_manager.get_units_by_team("player"):
		var dist := absi(player_unit.grid_pos.x - unit.grid_pos.x) + absi(player_unit.grid_pos.y - unit.grid_pos.y)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_player = player_unit

	if nearest_player == null:
		_end_current_unit_turn()
		return

	# 如果相邻，攻击
	if nearest_dist <= 1:
		_execute_ai_attack(unit, nearest_player)
		unit.has_acted = true
		_end_current_unit_turn()
		return

	# 否则向最近单位移动
	var move_dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(-1, 0)
	]

	var best_dir := Vector2i.ZERO
	var best_new_dist := nearest_dist
	for d in move_dirs:
		var new_pos := unit.grid_pos + d
		if not _is_valid_tile(new_pos.x, new_pos.y):
			continue
		if _get_unit_at(new_pos.x, new_pos.y) != null:
			continue
		var new_dist := absi(nearest_player.grid_pos.x - new_pos.x) + absi(nearest_player.grid_pos.y - new_pos.y)
		if new_dist < best_new_dist:
			best_dir = d
			best_new_dist = new_dist

	# 安全检查：空中单位不能移动
	if unit.physics.is_airborne:
		_log_ai("AI单位在空中，无法移动: %s air_height=%.2f" % [unit.unit_id, unit.physics.air_height])
		_end_current_unit_turn()
		return

	if best_dir != Vector2i.ZERO:
		var new_pos := unit.grid_pos + best_dir
		unit.set_grid_pos(new_pos.x, new_pos.y)
		# AI移动时保持air_height（虽然空中单位不应该移动，但为了完整性）
		unit.position = _grid_to_world_top(new_pos.x, new_pos.y, -1, unit.physics.air_height)
		unit.remaining_move_points -= 1
		if _unit_data.has(unit.unit_id):
			_unit_data[unit.unit_id]["col"] = new_pos.x
			_unit_data[unit.unit_id]["row"] = new_pos.y

	_end_current_unit_turn()


## AI 执行攻击
func _execute_ai_attack(attacker: TacticsUnit, target: TacticsUnit) -> void:
	var damage := maxi(1, attacker.atk - target.def)
	target.take_damage(damage)


# =============================================================================
# 工具方法
# =============================================================================

## AI 日志输出
func _log_ai(msg: String) -> void:
	print("[AI] ", msg)

## 获取指定格子的单位
func _get_unit_at(col: int, row: int) -> TacticsUnit:
	for unit_id in _unit_nodes:
		var unit: TacticsUnit = _unit_nodes[unit_id]
		if unit.grid_pos == Vector2i(col, row) and not unit.is_dead():
			return unit
	return null


## 根据格子坐标和高度层查找单位（3D版本，考虑空中高度）
## @param col: 列坐标
## @param row: 行坐标
## @param layer: 高度层（可选，-1表示不检查高度层，只检查格子坐标）
func _get_unit_at_layer(col: int, row: int, layer: int = -1) -> TacticsUnit:
	for unit_id in _unit_nodes:
		var unit: TacticsUnit = _unit_nodes[unit_id]
		if unit.is_dead():
			continue
		if unit.grid_pos != Vector2i(col, row):
			continue
		if layer < 0:
			return unit  # 不检查高度层，返回第一个匹配的
		var unit_layer := _get_unit_effective_layer(unit)
		if unit_layer == layer:
			return unit
	return null


## 计算单位的有效高度层（考虑地形高度 + 空中高度）
## 用于线框放置和3D选取，确保空中单位的线框显示在正确的高度
func _get_unit_effective_layer(unit: TacticsUnit) -> int:
	if unit.physics.is_airborne and unit.physics.air_height > 0.0:
		var terrain_h := _get_tile_height(unit.grid_pos.x, unit.grid_pos.y)
		var air_layers := int(round(unit.physics.air_height / TILE_SIZE))
		return terrain_h + air_layers
	return _get_tile_height(unit.grid_pos.x, unit.grid_pos.y)


## 获取被占据的格子 {pos: unit_id}
func _get_occupied_tiles() -> Dictionary:
	var result: Dictionary = {}
	for unit_id in _unit_nodes:
		var unit: TacticsUnit = _unit_nodes[unit_id]
		if not unit.is_dead():
			result[unit.grid_pos] = unit_id
	return result


## 获取指定格子的地形高度
func _get_tile_height(col: int, row: int) -> int:
	var key := Vector2i(col, row)

	# 优先从TerrainManager查询（如果已集成）
	if _terrain_manager != null:
		var instance := _terrain_manager.get_terrain_instance(key)
		if instance != null:
			return instance.current_height

		# 如果TerrainManager没有实例，使用默认类型的高度
		var type_id := _terrain_manager.get_terrain_type_at(col, row, self)
		var terrain_type := _terrain_manager.get_terrain_type(type_id)
		if terrain_type != null:
			return terrain_type.base_height

	# 兜底：从_terrain_data查询（兼容旧代码）
	var terrain: Dictionary = _terrain_data.get(key, {"height": 0})
	var height: int = terrain.get("height", 0)
	if height < 0:  # -1表示使用TerrainType.base_height
		var type_id: String = terrain.get("type_id", "stone_floor")
		# 这里需要从TerrainType资源查询base_height
		# 但在旧代码兼容模式下，假设默认高度为0
		height = 0
	return height


## 获取最大地形高度（缓存值，用于点击检测从高到低扫描）
func _get_max_terrain_height() -> int:
	return _max_terrain_height


## 开始战斗（由外部调用，启动回合制）
func start_battle() -> void:
	if _turn_manager:
		_turn_manager.start_battle()


## 获取当前回合数
func get_current_round() -> int:
	if _turn_manager:
		return _turn_manager.get_current_round()
	return 0


# =============================================================================
# 投掷技能 — 26格立体范围目标选择 + 26格方向选择
# =============================================================================

## 显示投掷技能目标选择范围（以操作角色为中心的26格立体范围）
## 只显示有地形方块或单位的格子
## 中心高度层使用单位的实际高度（含air_height），空中单位的线框在正确高度
func _show_throw_target_range(unit: TacticsUnit) -> void:
	_clear_move_range()
	var center_col := unit.grid_pos.x
	var center_row := unit.grid_pos.y
	var center_layer := _get_unit_effective_layer(unit)

	# 3x3x3立体范围（排除中心）
	for dl in range(-1, 2):  # 高度层偏移
		for dr in range(-1, 2):  # row偏移
			for dc in range(-1, 2):  # col偏移
				if dc == 0 and dr == 0 and dl == 0:
					continue  # 排除中心

				var tc := center_col + dc
				var tr := center_row + dr
				var tl := center_layer + dl

				# 检查格子是否有效
				if not _is_valid_tile(tc, tr):
					continue
				# 检查高度层是否有效（不能低于地面）
				if tl < 0:
					continue

				# 检查该位置是否有地形方块或单位（排除操作角色自己）
				var has_terrain: bool = _has_terrain_at_layer(tc, tr, tl)
				var unit_at := _get_unit_at(tc, tr)
				var has_unit: bool = unit_at != null and unit_at != unit

				if not has_terrain and not has_unit:
					continue

				# 在当前层创建线框（地形/单位/两者都有）
				_create_throw_wireframe_cube(tc, tr, tl)
				_move_range.append(Vector3i(tc, tr, tl))

				# 如果有空中单位且其有效高度层不在当前3x3x3范围内，额外创建一层线框
				if has_unit and unit_at.physics.is_airborne and unit_at.physics.air_height > 0.0:
					var unit_effective := _get_unit_effective_layer(unit_at)
					if unit_effective != tl:
						# 空中单位在其有效高度层也需要一个线框
						_create_throw_wireframe_cube(tc, tr, unit_effective)
						_move_range.append(Vector3i(tc, tr, unit_effective))

	_highlight_type = "throw_target"


## 检查指定位置在指定高度层是否有地形方块
func _has_terrain_at_layer(col: int, row: int, layer: int) -> bool:
	var tile_height := _get_tile_height(col, row)
	# 如果地形高度 >= layer，说明该层有地形方块
	return tile_height >= layer


## 统一创建线框立方体（正确的立方体框架，12条边无缝衔接）
## @param name_prefix: 节点名前缀（如 "ThrowTarget", "ThrowDir", "Interact"）
## @param color: 线框颜色
func _create_wireframe_cube(col: int, row: int, layer: int, name_prefix: String, color: Color) -> Node3D:
	var pos := _grid_to_world(col, row)
	var center_y: float = TILE_SIZE * (float(layer) + 0.5)
	var half: float = TILE_SIZE * 0.5

	# 正确的12条边（使用 pos.x 和 pos.z 作为中心，不自出头）
	var edges: Array[Dictionary] = [
		# 底部4条边 — X方向边（中心X，Z±，底部Y）
		{"center": Vector3(pos.x, center_y - half, pos.z - half), "size": Vector3(TILE_SIZE, 0.04, 0.04)},
		{"center": Vector3(pos.x, center_y - half, pos.z + half), "size": Vector3(TILE_SIZE, 0.04, 0.04)},
		# 底部4条边 — Z方向边（中心Z，X±，底部Y）
		{"center": Vector3(pos.x - half, center_y - half, pos.z), "size": Vector3(0.04, 0.04, TILE_SIZE)},
		{"center": Vector3(pos.x + half, center_y - half, pos.z), "size": Vector3(0.04, 0.04, TILE_SIZE)},
		# 顶部4条边 — X方向边
		{"center": Vector3(pos.x, center_y + half, pos.z - half), "size": Vector3(TILE_SIZE, 0.04, 0.04)},
		{"center": Vector3(pos.x, center_y + half, pos.z + half), "size": Vector3(TILE_SIZE, 0.04, 0.04)},
		# 顶部4条边 — Z方向边
		{"center": Vector3(pos.x - half, center_y + half, pos.z), "size": Vector3(0.04, 0.04, TILE_SIZE)},
		{"center": Vector3(pos.x + half, center_y + half, pos.z), "size": Vector3(0.04, 0.04, TILE_SIZE)},
		# 4条垂直边
		{"center": Vector3(pos.x - half, center_y, pos.z - half), "size": Vector3(0.04, TILE_SIZE, 0.04)},
		{"center": Vector3(pos.x - half, center_y, pos.z + half), "size": Vector3(0.04, TILE_SIZE, 0.04)},
		{"center": Vector3(pos.x + half, center_y, pos.z - half), "size": Vector3(0.04, TILE_SIZE, 0.04)},
		{"center": Vector3(pos.x + half, center_y, pos.z + half), "size": Vector3(0.04, TILE_SIZE, 0.04)},
	]

	var wireframe_root := Node3D.new()
	wireframe_root.name = "%s_%d_%d_%d" % [name_prefix, col, row, layer]

	for edge in edges:
		var edge_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = edge["size"]
		edge_mesh.mesh = box
		edge_mesh.position = edge["center"]

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		edge_mesh.material_override = mat

		wireframe_root.add_child(edge_mesh)

	tile_container.add_child(wireframe_root)
	_move_range_cubes.append(wireframe_root)
	return wireframe_root


## 创建投掷目标线框立方体（白色）
func _create_throw_wireframe_cube(col: int, row: int, layer: int) -> void:
	_create_wireframe_cube(col, row, layer, "ThrowTarget", Color(1.0, 1.0, 1.0, 0.85))


## 获取鼠标点击的投掷目标3D位置
## 使用数学方法计算射线与候选格子的 AABB 相交
func _get_throw_target_3d(screen_pos: Vector2) -> Vector3i:
	if subviewport_container == null or camera == null:
		return Vector3i(-1, -1, -1)

	var svp := subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if svp == null:
		return Vector3i(-1, -1, -1)

	var viewport_rect := subviewport_container.get_global_rect()
	var local_pos := screen_pos - viewport_rect.position
	var container_size := viewport_rect.size

	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > container_size.x or local_pos.y > container_size.y:
		return Vector3i(-1, -1, -1)

	var viewport_pos := Vector2(
		local_pos.x / container_size.x * svp.size.x,
		local_pos.y / container_size.y * svp.size.y
	)

	# 计算射线，转换到 tile_container 本地空间
	var from := camera.project_ray_origin(viewport_pos)
	var to := from + camera.project_ray_normal(viewport_pos) * 100.0

	var inv_transform := tile_container.global_transform.affine_inverse()
	var local_origin := inv_transform * from
	var local_ray := inv_transform.basis * camera.project_ray_normal(viewport_pos)

	# 遍历所有候选位置，检查射线-AABB 相交
	var best_t: float = INF
	var best_pos := Vector3i(-1, -1, -1)
	var half := TILE_SIZE * 0.45  # 略小于半边，避免边界重叠

	for pos in _move_range:
		if not (pos is Vector3i):
			continue
		var p := pos as Vector3i
		# 计算该格子的 AABB 中心
		var aabb_center := Vector3(
			(p.x - (_grid_cols - 1) * 0.5) * TILE_SIZE,
			TILE_SIZE * (float(p.z) + 0.5),
			(p.y - (_grid_rows - 1) * 0.5) * TILE_SIZE
		)
		# AABB 射线相交测试
		var t := _ray_aabb_intersect(local_origin, local_ray, aabb_center, Vector3(half, half, half))
		if t > 0 and t < best_t:
			best_t = t
			best_pos = p

	return best_pos


## 射线与 AABB 相交测试（返回最近交点距离 t，无交点返回 INF）
func _ray_aabb_intersect(origin: Vector3, dir: Vector3, box_center: Vector3, box_half: Vector3) -> float:
	var t_min: float = -INF
	var t_max: float = INF
	var inv_dir := Vector3(1.0 / dir.x, 1.0 / dir.y, 1.0 / dir.z)

	for i in range(3):
		var lo := box_center[i] - box_half[i] - origin[i]
		var hi := box_center[i] + box_half[i] - origin[i]
		var t1 := lo * inv_dir[i]
		var t2 := hi * inv_dir[i]
		if t1 > t2:
			var tmp := t1; t1 = t2; t2 = tmp
		if t1 > t_min:
			t_min = t1
		if t2 < t_max:
			t_max = t2
		if t_min > t_max:
			return INF

	if t_min > 0:
		return t_min
	elif t_max > 0:
		return t_max
	return INF


## 投掷目标选择完成：进入方向选择模式
func _on_throw_target_selected(target_pos: Vector3i) -> void:
	_clear_move_range()

	_throw_target_pos = target_pos

	# 检查目标位置是否有单位（禁止投掷自己），优先匹配高度层
	var unit_at_target := _get_unit_at_layer(target_pos.x, target_pos.y, target_pos.z)
	if unit_at_target == null:
		# 回退到2D查找（兼容地形投掷等场景）
		unit_at_target = _get_unit_at(target_pos.x, target_pos.y)
	if unit_at_target == _selected_unit:
		unit_at_target = null
	_throw_target_unit = unit_at_target

	# 检查行动点数是否足够
	if _throw_target_unit != null:
		# 投掷单位消耗1点行动点
		if _selected_unit.remaining_move_points < 1:
			print("[TacticsBoard] 投掷单位需要1点行动点数，当前只有 %d" % _selected_unit.remaining_move_points)
			_cancel_throw_mode()
			return
	else:
		# 投掷地形消耗2点行动点
		if _selected_unit.remaining_move_points < 2:
			print("[TacticsBoard] 投掷地形需要2点行动点数，当前只有 %d" % _selected_unit.remaining_move_points)
			_cancel_throw_mode()
			return

	# 进入方向选择模式
	_combat_state = CombatState.THROW_DIRECTION_MODE
	_show_throw_direction_range(target_pos)


## 显示投掷方向选择范围（以目标为中心的26格可选方向）
func _show_throw_direction_range(target_pos: Vector3i) -> void:
	_clear_move_range()

	var center_col := target_pos.x
	var center_row := target_pos.y
	var center_layer := target_pos.z

	# 26个方向偏移（使用PhysicsSystem的DIRECTION_OFFSETS_3D）
	for offset in PhysicsSystem.DIRECTION_OFFSETS_3D:
		var dc := offset.x
		var dr := offset.y
		var dl := offset.z

		var tc := center_col + dc
		var tr := center_row + dr
		var tl := center_layer + dl

		# 创建白色线框立方体表示可选方向
		_create_throw_direction_wireframe(tc, tr, tl, offset)
		_move_range.append(offset)  # 存储方向偏移量

	_highlight_type = "throw_direction"


## 创建投掷方向线框立方体（白色）
func _create_throw_direction_wireframe(col: int, row: int, layer: int, direction: Vector3i) -> void:
	_create_wireframe_cube(col, row, layer, "ThrowDir", Color(1.0, 1.0, 1.0, 0.85))


## 获取鼠标点击的投掷方向（数学方法计算射线与方向格子相交）
func _get_throw_direction_3d(screen_pos: Vector2) -> Vector3i:
	if subviewport_container == null or camera == null:
		return Vector3i(-1, -1, -1)

	var svp := subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if svp == null:
		return Vector3i(-1, -1, -1)

	var viewport_rect := subviewport_container.get_global_rect()
	var local_pos := screen_pos - viewport_rect.position
	var container_size := viewport_rect.size

	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > container_size.x or local_pos.y > container_size.y:
		return Vector3i(-1, -1, -1)

	var viewport_pos := Vector2(
		local_pos.x / container_size.x * svp.size.x,
		local_pos.y / container_size.y * svp.size.y
	)

	# 计算射线，转换到 tile_container 本地空间
	var from := camera.project_ray_origin(viewport_pos)
	var inv_transform := tile_container.global_transform.affine_inverse()
	var local_origin := inv_transform * from
	var local_ray := inv_transform.basis * camera.project_ray_normal(viewport_pos)

	# 对每个方向偏移，计算对应格子的 AABB 并测试相交
	var best_t: float = INF
	var best_dir := Vector3i(-1, -1, -1)
	var half := TILE_SIZE * 0.45

	for offset in _move_range:
		if not (offset is Vector3i):
			continue
		var d := offset as Vector3i
		# 方向格子位置 = 目标位置 + 方向偏移
		var tc := _throw_target_pos.x + d.x
		var tr := _throw_target_pos.y + d.y
		var tl := _throw_target_pos.z + d.z

		var aabb_center := Vector3(
			(tc - (_grid_cols - 1) * 0.5) * TILE_SIZE,
			TILE_SIZE * (float(tl) + 0.5),
			(tr - (_grid_rows - 1) * 0.5) * TILE_SIZE
		)
		var t := _ray_aabb_intersect(local_origin, local_ray, aabb_center, Vector3(half, half, half))
		if t > 0 and t < best_t:
			best_t = t
			best_dir = d

	return best_dir


## 应用投掷方向（执行物理效果）
func _apply_throw_direction(direction: Vector3i) -> void:
	_clear_move_range()

	# 投掷动作参数（硬编码）
	const THROW_IMPULSE: float = 1.5

	if _throw_target_unit != null:
		# 目标有单位：投掷该单位，消耗1点行动点
		_physics_system.apply_velocity_direction_3d(
			_throw_target_unit,
			_throw_target_pos,
			direction,
			THROW_IMPULSE
		)
		_selected_unit.remaining_move_points -= 1
		print("[TacticsBoard] 投掷单位 %s，消耗1点行动点" % _throw_target_unit.unit_id)
	else:
		# 目标为地形方块：消耗2点行动点
		print("[TacticsBoard] 投掷地形方块 (%d,%d,%d)，消耗2点行动点" % [
			_throw_target_pos.x, _throw_target_pos.y, _throw_target_pos.z
		])
		_selected_unit.remaining_move_points -= 2

	# 投掷执行后再次强制清除所有残留线框（立即结算可能产生新线框）
	_force_clear_all_wireframes()

	# 投掷完成后，重置状态
	_throw_target_pos = Vector3i(-1, -1, -1)
	_throw_target_unit = null

	# 如果还有移动点数且未行动，重新显示菜单
	if _selected_unit.remaining_move_points > 0 or not _selected_unit.has_acted:
		_combat_state = CombatState.UNIT_SELECTED
		_show_action_menu(_selected_unit)
	else:
		_end_current_unit_turn()


## 取消投掷目标选择模式
func _cancel_throw_mode() -> void:
	_clear_move_range()
	_pending_skill_id = ""
	_throw_target_pos = Vector3i(-1, -1, -1)
	_throw_target_unit = null
	_combat_state = CombatState.UNIT_SELECTED
	_show_action_menu(_selected_unit)


## 取消投掷方向选择模式
func _cancel_throw_direction_mode() -> void:
	_clear_move_range()
	# 回到目标选择模式（允许重新选择目标）
	_combat_state = CombatState.THROW_TARGET_MODE
	_show_throw_target_range(_selected_unit)


## 统一悬停高亮（鼠标移动时调用）
## 所有模式统一使用AABB数学方法检测悬停的线框
func _update_hover_highlight(screen_pos: Vector2) -> void:
	if subviewport_container == null or camera == null:
		return

	var svp := subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if svp == null:
		return

	var viewport_rect := subviewport_container.get_global_rect()
	var local_pos := screen_pos - viewport_rect.position
	var container_size := viewport_rect.size

	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > container_size.x or local_pos.y > container_size.y:
		_restore_all_wireframes_to_white()
		return

	var viewport_pos := Vector2(
		local_pos.x / container_size.x * svp.size.x,
		local_pos.y / container_size.y * svp.size.y
	)

	# 统一使用AABB数学方法检测悬停的线框
	# 所有模式的线框名称都包含绝对网格坐标：prefix_col_row_layer
	var from := camera.project_ray_origin(viewport_pos)
	var inv_transform := tile_container.global_transform.affine_inverse()
	var local_origin := inv_transform * from
	var local_ray := inv_transform.basis * camera.project_ray_normal(viewport_pos)
	var half := TILE_SIZE * 0.45

	var best_t: float = INF
	var hovered_idx: int = -1

	for i in range(_move_range_cubes.size()):
		var cube_root: Node = _move_range_cubes[i]
		if not (cube_root is Node3D):
			continue
		var name_str: String = cube_root.name
		var parts := name_str.split("_")
		if parts.size() >= 4:
			# 线框名称格式: "前缀_col_row_layer"（都是绝对网格坐标）
			var col := parts[1].to_int()
			var row := parts[2].to_int()
			var layer := parts[3].to_int()
			var aabb_center := Vector3(
				(col - (_grid_cols - 1) * 0.5) * TILE_SIZE,
				TILE_SIZE * (float(layer) + 0.5),
				(row - (_grid_rows - 1) * 0.5) * TILE_SIZE
			)
			var t := _ray_aabb_intersect(local_origin, local_ray, aabb_center, Vector3(half, half, half))
			if t > 0 and t < best_t:
				best_t = t
				hovered_idx = i

	# 更新高亮
	if hovered_idx != _hovered_wireframe_idx:
		if _hovered_wireframe_idx >= 0 and _hovered_wireframe_idx < _move_range_cubes.size():
			_set_wireframe_color(_hovered_wireframe_idx, Color(1.0, 1.0, 1.0, 0.85))
		if hovered_idx >= 0 and hovered_idx < _move_range_cubes.size():
			_set_wireframe_color(hovered_idx, Color(1.0, 0.8, 0.2, 0.85))
		_hovered_wireframe_idx = hovered_idx


## 设置线框颜色
func _set_wireframe_color(idx: int, color: Color) -> void:
	if idx < 0 or idx >= _move_range_cubes.size():
		return

	var wireframe_root: Node = _move_range_cubes[idx]
	if wireframe_root is Node3D:
		# 遍历所有子节点，找到 MeshInstance3D 并修改颜色
		for child in wireframe_root.get_children():
			if child is MeshInstance3D:
				var mat: StandardMaterial3D = child.material_override as StandardMaterial3D
				if mat != null:
					mat.albedo_color = color


## 恢复所有线框为白色
func _restore_all_wireframes_to_white() -> void:
	for i in range(_move_range_cubes.size()):
		_set_wireframe_color(i, Color(1.0, 1.0, 1.0, 0.85))
	_hovered_wireframe_idx = -1
