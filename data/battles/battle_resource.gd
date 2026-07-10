class_name BattleResource
extends Resource

## 战斗配置资源 — 定义战斗的基础配置、胜负条件和单位部署
## 子脚本可覆盖虚方法实现差异化（如 Boss 战二阶段等）

# =============================================================================
# 基础属性
# =============================================================================

@export var battle_id: String = ""
@export var battle_name: String = ""
@export var background: String = ""
@export var tile_light_color: String = "#E0D4BD"
@export var tile_dark_color: String = "#847560"

# =============================================================================
# 地图属性
# =============================================================================

@export var grid_cols: int = 10
@export var grid_rows: int = 10
@export var initial_terrain_type: String = "stone_floor"

@export var camera_look_at_col: int = 0
@export var camera_look_at_row: int = 0
@export var camera_look_at_height: float = 1.0

# =============================================================================
# 胜负条件
# =============================================================================

@export var win_conditions: Array[Dictionary] = []
@export var lose_conditions: Array[Dictionary] = []

# =============================================================================
# 单位部署
# =============================================================================

@export var unit_spawns: Array[Dictionary] = []

# =============================================================================
# 虚方法 — 子脚本覆盖实现差异化
# =============================================================================

## 获取战斗修正器（子脚本覆盖，如 Boss 战有二阶段等）
func get_battle_modifiers() -> Dictionary:
	return {}

## 转换为兼容 Dictionary（供 tactics_board.gd 加载）
func to_dict() -> Dictionary:
	var d := {
		"battle_id": battle_id,
		"name": battle_name,
		"background": background,
		"tile_light_color": tile_light_color,
		"tile_dark_color": tile_dark_color,
		"grid_cols": grid_cols,
		"grid_rows": grid_rows,
		"initial_terrain_type": initial_terrain_type,
		"camera_look_at": {
			"col": camera_look_at_col,
			"row": camera_look_at_row,
			"height": camera_look_at_height
		},
		"win_conditions": win_conditions,
		"lose_conditions": lose_conditions,
		"units": unit_spawns,
	}
	return d
