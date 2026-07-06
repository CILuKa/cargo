# 地形编辑器使用指南

## 系统概述

战棋地图3D可视化编辑器是一个完整的地图编辑系统，包括：
1. **地形类型定义系统**（TerrainType + JSON配置）
2. **战斗JSON格式规范**（支持稀疏和密集两种格式）
3. **Godot地形读取系统**（集成TerrainManager和PhysicsSystem）
4. **Python可视化编辑器**（3D交互式编辑）

## 文件结构

```
FIRST_TRY/
├── data/
│   ├── battle_example.json          # 战斗配置文件（地图数据）
│   ├── terrain_types/               # 地形类型配置目录
│   │   ├── terrain_stone_floor.json
│   │   ├── terrain_wooden_door_closed.json
│   │   ├── terrain_wooden_door_open.json
│   │   ├── terrain_stone_wall.json
│   │   └── terrain_metal_window.json
│   └── battle_terrain_example.json  # 示例战斗配置
├── scripts/
│   ├── terrain_type.gd              # 地形类型Resource类
│   ├── terrain_manager.gd           # 地形管理系统
│   ├── physics_system.gd            # 物理系统（集成地形）
│   └── tactics_board.gd             # 战棋棋盘（读取地形）
├── tools/
│   └── terrain_editor.py            # Python可视化编辑器
└── docs/
	├── terrain_json_format.md       # JSON格式设计范式
	├── terrain_system_usage.md      # 地形系统使用指南
	└── terrain_editor_usage.md      # 本文件
```

## 使用流程

### 1. 定义地形类型

在 `data/terrain_types/` 目录中创建地形类型JSON文件：

```json
{
  "terrain_type_id": "stone_floor",
  "display_name": "石制地面",
  "material_type": "STONE",
  "mass": 100.0,
  "base_height": 0,
  "is_passable": true
}
```

参见已有示例文件：
- `terrain_stone_floor.json` - 石制地面
- `terrain_wooden_door_closed.json` - 关闭的木门
- `terrain_wooden_door_open.json` - 打开的木门
- `terrain_stone_wall.json` - 石制墙壁
- `terrain_metal_window.json` - 金属窗户

### 2. 运行可视化编辑器

安装依赖：
```bash
pip install pygame PyOpenGL PyOpenGL_accelerate
```

运行编辑器：
```bash
python tools/terrain_editor.py data/battle_example.json data/terrain_types
```

或使用默认路径：
```bash
python tools/terrain_editor.py
```

### 3. 编辑地图

#### 操作说明

| 操作 | 功能 |
|------|------|
| **左键点击** | 赋值单个地块 |
| **右键拖动** | 批量赋值地块（滑动赋值） |
| **中键拖动** | 旋转3D视角 |
| **ESC键** | 退出编辑器 |
| **S键** | 快捷保存地图 |
| **底部面板** | 选择地形类型 |
| **保存按钮** | 保存地图到JSON |

#### 编辑步骤

1. **选择地形类型**：在底部面板点击地形类型按钮
2. **赋值地块**：
   - 左键点击单个格子赋值
   - 右键拖动批量赋值多个格子
3. **删除地块**：选择"删除"选项，点击/拖动删除地块
4. **旋转视角**：中键拖动调整3D视角，观察地图
5. **保存地图**：点击"保存地图"按钮或按S键保存

### 4. JSON文件格式

编辑器保存的JSON格式（稀疏格式，性能最优）：

```json
{
  "grid_cols": 20,
  "grid_rows": 20,
  "excluded_tiles": [
	{"col": 0, "row": 0}
  ],
  "terrain": {
	"default_type": "stone_floor",
	"tiles": [
	  {"col": 5, "row": 5, "type_id": "wooden_door_closed", "height": 1},
	  {"col": 8, "row": 5, "type_id": "stone_wall"}
	]
  },
  "units": [...],
  "win_conditions": [...],
  "camera_look_at": {...}
}
```

格式优势：
- **稀疏数组**：只保存特殊地块，节省99%+存储空间
- **default_type**：未显式定义的格子使用默认类型
- **兼容旧代码**：保留原有字段（units、win_conditions等）

### 5. Godot加载地形

战斗场景启动时，TacticsBoard自动加载地形：

```gdscript
# 初始化时自动执行
_terrain_manager.load_terrain_types_from_dir("res://data/terrain_types/")
load_battle_config("res://data/battle_example.json")
```

地形查询接口：

```gdscript
# 获取地形高度
var height = _terrain_manager.get_terrain_height(Vector2i(5, 5))

# 获取摩擦系数（通过PhysicsSystem）
var friction = _physics_system._ctx.get_terrain_friction(5, 5)

# 检查是否可经过
var passable = _physics_system._ctx.is_terrain_passable(7, 5)

# 交互地形（如开关门）
var result = _terrain_manager.interact_terrain(Vector2i(7, 5))
```

## 高级功能

### 1. 批量编辑技巧

**右键滑动赋值**：
- 选中地形类型
- 右键按下开始拖动
- 拖动路径上的所有格子被赋值
- 适合快速创建墙壁、走廊等

**删除模式**：
- 选中"删除"选项
- 点击/拖动删除地块
- 删除的地块会添加到 `excluded_tiles` 数组

### 2. 视角控制

**中键拖动旋转**：
- 水平拖动：旋转地图（45°视角）
- 垂直拖动：调整俯角（10°-80°）
- 适合观察立体地形结构

### 3. 地形类型管理

**添加新地形类型**：
1. 在 `data/terrain_types/` 创建新JSON文件
2. 定义所有必需字段（见字段说明）
3. 编辑器自动读取并显示在底部面板

**字段说明**：
```json
{
  "terrain_type_id": "必需，唯一标识符",
  "display_name": "必需，显示名称",
  "material_type": "必需，材料类型（PLASTIC/WOOD/STONE/METAL）",
  "mass": "可选，质量（千克）",
  "base_height": "可选，基础高度（格子数）",
  "is_passable": "可选，是否可经过",
  "is_interactive": "可选，是否可交互",
  "custom_max_health": "可选，自定义生命值"
}
```

## 性能优化

### 1. 稀疏格式优势

**存储效率对比**：

| 地图大小 | 密集格式行数 | 稀疏格式行数 | 节省比例 |
|----------|-------------|-------------|----------|
| 10x10 | 100 | 5（90%默认） | 95% |
| 200x200 | 40000 | 10（99.95%默认） | 99.975% |
| 复杂迷宫 | 400 | 400 | 0%（密集格式） |

**适用场景**：
- 大地图 + 规则棋盘 → 稀疏格式（推荐）
- 小地图 + 复杂迷宫 → 密集格式（编辑器生成）

### 2. 查询性能

**O(1)复杂度**：
- TerrainManager使用Dictionary直接索引
- PhysicsSystem缓存查询结果
- TacticsBoard优先查询TerrainManager

**缓存机制**：
- TerrainInstance初始化时缓存所有物理属性
- 避免重复查询TerrainType资源
- 大地图查询仍为O(1)

### 3. 加载性能

**Resource预加载**：
- TerrainType资源初始化时预加载
- 避免运行时动态加载JSON
- 类型安全 + 编辑器可视化

**按需创建实例**：
- 未显式定义的格子不预创建TerrainInstance
- TerrainManager查询时动态处理默认类型
- 节省初始化时间和内存

## 集成说明

### 1. PhysicsSystem集成

地形物理属性查询通过PhysicsSystem.BoardContext接口：

```gdscript
# 获取地形摩擦系数
func get_terrain_friction(col: int, row: int) -> float:
	if _board._terrain_manager != null:
		return _board._terrain_manager.get_terrain_friction(Vector2i(col, row))
	return 1.0  # 默认摩擦系数
```

### 2. 战斗系统集成

地形实例在战斗配置加载时自动创建：

```gdscript
func _load_terrain() -> void:
	# 读取JSON配置
	var terrain_config = _battle_config.get("terrain", {})

	# 创建TerrainManager实例
	for tile_data in terrain_config.get("tiles", []):
		var instance = _terrain_manager.create_terrain_instance(
			tile_data.type_id, Vector2i(tile_data.col, tile_data.row)
		)
```

### 3. 存档系统集成

地形状态可序列化到存档：

```gdscript
# 保存地形状态
var terrain_data = _terrain_manager.get_all_terrain_instances()
save_data["terrain_instances"] = terrain_data

# 加载地形状态
_terrain_manager.load_terrain_instances_from_dict(load_data["terrain_instances"])
```

## 常见问题

### Q1: 编辑器无法启动？

检查依赖安装：
```bash
pip install pygame PyOpenGL PyOpenGL_accelerate
```

检查文件路径：
```bash
python tools/terrain_editor.py data/battle_example.json data/terrain_types
```

### Q2: 地形类型不显示？

检查JSON文件格式：
- 必需字段：`terrain_type_id`、`display_name`
- 文件位置：`data/terrain_types/` 目录
- 文件扩展名：`.json`

### Q3: 保存后Godot无法加载？

检查JSON格式兼容性：
- `terrain` 对象包含 `default_type` 字段
- `tiles` 数组元素包含 `type_id` 字段
- `excluded_tiles` 数组格式正确

### Q4: 如何创建不规则棋盘？

使用"删除"模式：
1. 选中"删除"选项
2. 点击/拖动删除边缘格子
3. 保存后 `excluded_tiles` 记录删除位置

### Q5: 如何批量创建相同高度的地块？

方法1：右键滑动赋值
方法2：定义TerrainType的base_height
方法3：在JSON中统一指定height字段

## 未来扩展

### 可扩展点

1. **新增材料类型**：
   - 在TerrainTypeConfig添加新材料
   - 定义材料系数和颜色

2. **新增地形用途**：
   - 扩展TerrainUsage枚举
   - 实现特殊交互逻辑

3. **地形特效系统**：
   - 坍塌动画
   - 破坏特效
   - 状态变化视觉反馈

4. **编辑器增强**：
   - 地形高度编辑
   - 自定义生命值设置
   - 复制/粘贴地形区域

## 技术细节

### OpenGL渲染优化

- **深度测试**：启用GL_DEPTH_TEST避免遮挡错误
- **光照系统**：GL_LIGHT0提供环境光+漫反射
- **颜色材质**：GL_COLOR_MATERIAL简化材质设置
- **射线拾取**：gluUnProject实现鼠标3D坐标转换

### Pygame UI集成

- **混合渲染**：OpenGL渲染3D地图，Pygame渲染UI
- **事件处理**：统一处理鼠标/键盘事件
- **状态切换**：glEnable/glDisable切换渲染模式

## 总结

战棋地图3D可视化编辑器提供了完整的地图编辑解决方案：
- **高效格式**：稀疏数组节省99%+存储空间
- **可视化编辑**：3D交互式编辑，直观高效
- **系统集成**：自动集成PhysicsSystem和战斗系统
- **性能优化**：O(1)查询复杂度，支持大地图

通过本系统，可以快速创建复杂地形地图，并无缝集成到战棋战斗系统中！
