@tool
class_name BattleScene
extends Node3D

## 战斗场景 — 每场战斗对应一个 .tscn 场景文件
##
## 场景结构（由 import_battle_to_scene.gd 自动生成）：
##   BattleScene (根节点，存储战斗数据)
##   ├── WorldEnvironment
##   ├── DirectionalLight3D
##   ├── Camera3D
##   ├── TerrainContainer
##   │   ├── BasePlatform
##   │   ├── Cube_X_Y (TerrainCube 实例)
##   │   └── ...
##   └── UnitContainer
##       ├── Unit_XXX (UnitSpawnMarker 实例)
##       └── ...
##
## 地形数据仍由 terrain_editor.py 编辑 JSON 文件，本场景通过 terrain_json_path 引用
## 运行时由 tactics_board.load_battle() 加载，通过 to_battle_config() 转换为旧格式

const TILE_SIZE := 1.0

## === 基础信息 ===
@export var battle_id: String = "":
	set(v): battle_id = v
@export var display_name: String = "":
	set(v): display_name = v

## === 网格设置 ===
@export var grid_cols: int = 10
@export var grid_rows: int = 10

## === 地形引用 ===
@export_file("*.json") var terrain_json_path: String = ""

## === 初始地形类型 ===
@export var initial_terrain_type: String = "stone_floor"

## === 相机位置 ===
@export var camera_look_at_col: int = 5
@export var camera_look_at_row: int = 4
@export var camera_look_at_height: float = 1.0

## === 单位出生点 ===
@export var unit_spawns: Array[UnitSpawnConfig] = []

## === 胜负条件 ===
@export var win_conditions: Array[ConditionResource] = []
@export var lose_conditions: Array[ConditionResource] = []

## === 外观设置 ===
@export var tile_light_color: Color = Color(0.88, 0.83, 0.74)
@export var tile_dark_color: Color = Color(0.52, 0.46, 0.38)
@export_file("*.png", "*.jpg") var background: String = ""


# =============================================================================
# 运行时接口（与 tactics_board 兼容）
# =============================================================================

## 转换为旧格式战斗配置字典（兼容 tactics_board.load_battle_config 接口）
func to_battle_config() -> Dictionary:
	var units_array: Array = []
	for spawn in unit_spawns:
		units_array.append(spawn.to_spawn_dict())

	var win_array: Array = []
	for cond in win_conditions:
		win_array.append(cond.to_condition_dict())

	var lose_array: Array = []
	for cond in lose_conditions:
		lose_array.append(cond.to_condition_dict())

	return {
		"battle_id": battle_id,
		"name": display_name,
		"background": background,
		"tile_light_color": _color_to_hex(tile_light_color),
		"tile_dark_color": _color_to_hex(tile_dark_color),
		"grid_cols": grid_cols,
		"grid_rows": grid_rows,
		"initial_terrain_type": initial_terrain_type,
		"camera_look_at": {
			"col": camera_look_at_col,
			"row": camera_look_at_row,
			"height": camera_look_at_height
		},
		"win_conditions": win_array,
		"lose_conditions": lose_array,
		"units": units_array
	}


## 获取地形配置 JSON 路径
func get_terrain_config_path() -> String:
	return terrain_json_path


## 网格坐标 → 世界坐标
func grid_to_world_pos(col: int, row: int) -> Vector3:
	var cx: float = col - (grid_cols - 1) * 0.5
	var rz: float = row - (grid_rows - 1) * 0.5
	return Vector3(cx * TILE_SIZE, 0, rz * TILE_SIZE)


## 从旧格式 JSON 字典构建 BattleScene 的导出属性
func load_from_dict(data: Dictionary) -> void:
	battle_id = data.get("battle_id", "")
	display_name = data.get("name", "")
	background = data.get("background", "")
	grid_cols = data.get("grid_cols", 10)
	grid_rows = data.get("grid_rows", 10)
	initial_terrain_type = data.get("initial_terrain_type", "stone_floor")

	var cam = data.get("camera_look_at", {})
	camera_look_at_col = cam.get("col", 5)
	camera_look_at_row = cam.get("row", 4)
	camera_look_at_height = cam.get("height", 1.0)

	tile_light_color = _hex_to_color(data.get("tile_light_color", "#E0D4BD"))
	tile_dark_color = _hex_to_color(data.get("tile_dark_color", "#847560"))

	# 解析单位出生点
	unit_spawns.clear()
	for unit_data in data.get("units", []):
		var spawn := UnitSpawnConfig.new()
		spawn.spawn_id = unit_data.get("id", "")
		spawn.character_id = unit_data.get("character_id", "")
		spawn.col = unit_data.get("col", 0)
		spawn.row = unit_data.get("row", 0)
		spawn.team = unit_data.get("team", "player")
		spawn.texture_path = unit_data.get("texture", "")
		unit_spawns.append(spawn)

	# 解析胜负条件（next 字段支持 string 或 {file, node} 字典格式）
	win_conditions.clear()
	for cond_data in data.get("win_conditions", []):
		var cond := ConditionResource.new()
		cond.condition_id = cond_data.get("id", "")
		cond.description = cond_data.get("description", "")
		cond.type = cond_data.get("type", "")
		cond.params = cond_data.get("params", {})
		_parse_next_field(cond, cond_data.get("next", ""))
		win_conditions.append(cond)

	lose_conditions.clear()
	for cond_data in data.get("lose_conditions", []):
		var cond := ConditionResource.new()
		cond.condition_id = cond_data.get("id", "")
		cond.description = cond_data.get("description", "")
		cond.type = cond_data.get("type", "")
		cond.params = cond_data.get("params", {})
		_parse_next_field(cond, cond_data.get("next", ""))
		lose_conditions.append(cond)


## 解析 next 字段：支持 string（同文件节点ID）或 {file, node}（跨文件引用）
func _parse_next_field(cond: ConditionResource, next_value: Variant) -> void:
	if next_value is String:
		cond.next_branch = next_value
		cond.next_file = ""
	elif next_value is Dictionary:
		cond.next_branch = next_value.get("node", "")
		cond.next_file = next_value.get("file", "")
	else:
		cond.next_branch = ""
		cond.next_file = ""


## Color → "#RRGGBB" 十六进制字符串
func _color_to_hex(color: Color) -> String:
	return "#%02X%02X%02X" % [int(color.r * 255.0), int(color.g * 255.0), int(color.b * 255.0)]


## "#RRGGBB" → Color
func _hex_to_color(hex: String) -> Color:
	if hex.is_empty():
		return Color.WHITE
	hex = hex.lstrip("#")
	if hex.length() < 6:
		return Color.WHITE
	var r := hex.substr(0, 2).hex_to_int() / 255.0
	var g := hex.substr(2, 2).hex_to_int() / 255.0
	var b := hex.substr(4, 2).hex_to_int() / 255.0
	return Color(r, g, b)
