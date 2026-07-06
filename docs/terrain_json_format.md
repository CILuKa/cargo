# 地形JSON格式设计范式

## 设计原则
1. **性能高效**: 稀疏数组格式，只记录特殊地块，节省空间
2. **兼容性强**: 支持多种地形类型、高度、不规则形状
3. **易扩展**: 支持未来新增地形属性

## 格式设计

### 方案1：稀疏数组格式（推荐，性能最优）

```json
{
  "grid_cols": 20,
  "grid_rows": 20,
  "excluded_tiles": [
	{"col": 0, "row": 0},
	{"col": 19, "row": 19}
  ],
  "terrain": {
	"default_type": "stone_floor",  // 默认地块类型（未显式定义的格子）
	"tiles": [
	  // 特殊地块数组，只记录与默认类型不同的格子
	  {
		"col": 5,
		"row": 5,
		"type_id": "stone_floor",  // 地块类型ID（引用terrain_types）
		"height": 0,               // 高度（可选，默认使用type的base_height）
		"custom_health": -1        // 自定义生命值（可选，-1表示自动计算）
	  },
	  {
		"col": 7,
		"row": 5,
		"type_id": "wooden_door_closed",
		"height": 1,  // 覆盖base_height
		"is_open": false  // 交互状态（可选）
	  },
	  {
		"col": 8,
		"row": 5,
		"type_id": "stone_wall",
		// 不指定height，使用TerrainType.base_height（默认3）
	  }
	]
  },
  "units": [...],
  "win_conditions": [...],
  "lose_conditions": [...],
  "camera_look_at": {...}
}
```

### 方案2：密集数组格式（适合复杂地图编辑器生成）

```json
{
  "terrain": {
	"grid": [
	  // 二维数组，按行存储（row-major order）
	  ["stone_floor", "stone_floor", "wooden_door_closed", "stone_wall"],
	  ["stone_floor", null, "stone_floor", null],  // null表示excluded_tile
	  ["stone_floor", "metal_window", "stone_floor", "stone_floor"]
	],
	"height_grid": [
	  // 高度数组（可选，与grid一一对应）
	  [0, 0, 1, 3],
	  [0, null, 0, null],
	  [0, 2, 0, 0]
	]
  }
}
```

## 字段说明

### terrain对象结构

| 字段名 | 类型 | 必需 | 说明 |
|--------|------|------|------|
| default_type | String | 推荐 | 默认地块类型ID，未在tiles中定义的格子使用此类型 |
| tiles | Array | 可选 | 特殊地块数组（稀疏格式） |
| grid | Array[Array] | 可选 | 密集地块网格（密集格式） |
| height_grid | Array[Array] | 可选 | 密集高度网格（配合grid使用） |

### tiles数组元素结构（稀疏格式）

| 字段名 | 类型 | 必需 | 说明 |
|--------|------|------|------|
| col | int | 必需 | 格子列索引（0-based） |
| row | int | 必需 | 格子行索引（0-based） |
| type_id | String | 必需 | 地块类型ID（引用terrain_types） |
| height | int | 可选 | 高度（默认使用TerrainType.base_height） |
| custom_health | int | 可选 | 自定义生命值（-1=自动计算） |
| is_open | bool | 可选 | 交互状态（用于门等可交互地形） |

### excluded_tiles数组元素结构

| 字段名 | 类型 | 必需 | 说明 |
|--------|------|------|------|
| col | int | 必需 | 格子列索引 |
| row | int | 必需 | 格子行索引 |

## 性能分析

### 稀疏格式（方案1）
- **存储效率**: 对于大部分为默认地块的地图，节省90%+空间
- **查询效率**: O(1) - 使用Dictionary直接索引
- **适用场景**: 大地图、规则棋盘、少量特殊地块

### 密集格式（方案2）
- **存储效率**: 存储所有格子，适合复杂地图
- **查询效率**: O(1) - 数组直接索引
- **适用场景**: 小地图、复杂地图编辑器生成

## 查询逻辑（Godot代码实现）

```gdscript
func get_terrain_type_at(col: int, row: int) -> String:
	var key := Vector2i(col, row)
	
	# 1. 检查是否被排除
	if _excluded_tiles.has(key):
		return ""  # 无地块
	
	# 2. 检查稀疏数组（tiles）
	if _terrain_data.has(key):
		return _terrain_data[key].get("type_id", "stone_floor")
	
	# 3. 检查密集数组（grid）
	if _terrain_grid != null and row < _terrain_grid.size():
		var row_data := _terrain_grid[row]
		if col < row_data.size():
			var type_id := row_data[col]
			if type_id != null:
				return type_id
	
	# 4. 返回默认类型
	return _terrain_config.get("default_type", "stone_floor")
```

## 兼容性保证

- 两种格式可以共存，代码自动识别
- 空的terrain字段默认使用default_type填充整个地图
- 支持混合使用：部分使用tiles稀疏数组，部分使用grid密集数组

## 示例场景

### 场景1：大地图（200x200），90%为默认地面
```json
{
  "terrain": {
	"default_type": "stone_floor",
	"tiles": [
	  {"col": 50, "row": 50, "type_id": "stone_wall"},
	  {"col": 100, "row": 100, "type_id": "metal_window"}
	]
  }
}
```
存储：3行 vs 40000行（密集格式），节省99.99%空间

### 场景2：复杂迷宫地图（20x20）
```json
{
  "terrain": {
	"grid": [
	  ["stone_wall", "stone_floor", "stone_wall", ...],
	  ["stone_floor", "stone_floor", "stone_floor", ...],
	  ...
	]
  }
}
```
由地图编辑器生成，适合密集格式

### 场景3：不规则棋盘（有excluded_tiles）
```json
{
  "excluded_tiles": [
	{"col": 0, "row": 0},
	{"col": 0, "row": 1},
	{"col": 1, "row": 0}
  ],
  "terrain": {
	"default_type": "stone_floor",
	"tiles": [
	  {"col": 5, "row": 5, "type_id": "wooden_door_closed"}
	]
  }
}
```

## 迁移指南

### 从旧格式迁移（仅height和type字段）

旧格式：
```json
{
  "terrain": {
	"tiles": [
	  {"col": 10, "row": 10, "height": 2, "type": "hill"}
	]
  }
}
```

新格式：
```json
{
  "terrain": {
	"default_type": "stone_floor",
	"tiles": [
	  {"col": 10, "row": 10, "type_id": "stone_hill", "height": 2}
	]
  }
}
```

迁移步骤：
1. 创建对应的TerrainType资源（如stone_hill.tres）
2. 将type字段改为type_id（引用terrain_type_id）
3. 添加default_type字段（根据地图主要地块类型）

## 最佳实践

1. **大地图优先使用稀疏格式**：节省存储空间和加载时间
2. **小地图可使用密集格式**：编辑器生成方便
3. **定义合理的default_type**：减少tiles数组长度
4. **合理使用excluded_tiles**：不规则棋盘边缘处理
5. **height可选**：尽量依赖TerrainType.base_height，减少冗余数据
