class_name UnitSpawnConfig
extends Resource

## 单位出生点配置（用于战斗场景）
## 每个条目描述一个单位在战斗开始时的位置和属性

@export var spawn_id: String = ""           # 唯一标识符（如 "knight_1"）
@export var character_id: String = ""        # 角色ID（引用 CharacterRoster 中注册的角色类型）
@export_group("位置")
@export var col: int = 0                    # 网格列坐标
@export var row: int = 0                    # 网格行坐标
@export_group("归属")
@export var team: String = "player"         # 队营: player | enemy | neutral
@export_group("外观覆盖")
@export_file("*.png", "*.jpg") var texture_path: String = ""  # 可选：覆盖角色默认贴图


## 转换为旧格式字典（兼容 _place_battle_units 接口）
func to_spawn_dict() -> Dictionary:
	return {
		"id": spawn_id,
		"character_id": character_id,
		"type": "sprite",
		"col": col,
		"row": row,
		"texture": texture_path if not texture_path.is_empty() else "",
		"team": team
	}
