class_name BattleTerrainResource
extends Resource

## 战斗地形资源 — 存储战斗地图的地形数据
## 由 terrain_editor.py 生成 JSON，Godot 加载时转换为 Resource
## 脚本与 .tres 数据文件同目录 (data/battles/)

# =============================================================================
# 属性
# =============================================================================

## 关联的战斗 ID
@export var battle_id: String = ""

## 默认地形类型
@export var default_type: String = "stone_floor"

## 排除的格子列表 [{col: int, row: int}]
@export var excluded_tiles: Array[Dictionary] = []

## 地形格子列表 [{col: int, row: int, layers: Array[String], height: int}]
@export var tiles: Array[Dictionary] = []

# =============================================================================
# 方法
# =============================================================================

## 转换为兼容 Dictionary（供 terrain_manager 和 tactics_board 加载）
func to_dict() -> Dictionary:
	return {
		"terrain_config": {
			"default_type": default_type,
			"excluded_tiles": excluded_tiles,
			"tiles": tiles,
		},
		"description": battle_id + "对应的地形配置",
	}

## 从 Dictionary 创建（兼容 JSON 加载）
static func from_dict(battle_id: String, data: Dictionary) -> BattleTerrainResource:
	var res := BattleTerrainResource.new()
	res.battle_id = battle_id
	var terrain_config: Dictionary = data.get("terrain_config", {})
	res.default_type = terrain_config.get("default_type", "stone_floor")

	# excluded_tiles
	var excluded: Array[Dictionary] = []
	for tile in terrain_config.get("excluded_tiles", []):
		excluded.append({"col": int(tile.get("col", 0)), "row": int(tile.get("row", 0))})
	res.excluded_tiles = excluded

	# tiles
	var tiles_arr: Array[Dictionary] = []
	for tile in terrain_config.get("tiles", []):
		var entry: Dictionary = {
			"col": int(tile.get("col", 0)),
			"row": int(tile.get("row", 0)),
			"height": int(tile.get("height", 1)),
		}
		# layers
		var layers_raw = tile.get("layers", [])
		var layers: Array[String] = []
		for l in layers_raw:
			layers.append(str(l) if l != null else "__AIR__")
		entry["layers"] = layers
		tiles_arr.append(entry)
	res.tiles = tiles_arr

	return res
