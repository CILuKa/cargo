# 地形系统使用指南

## 系统架构

### 核心组件
- **TerrainType（Resource）**: 地形类型定义，存储静态属性（材料、贴图、物理参数）
- **TerrainManager**: 地形管理系统，管理地形类型和地形实例
- **PhysicsSystem集成**: 通过BoardContext接口调用物理系统方法

### 数据结构选择
采用 **Resource + Dictionary 混合方案**：
- **TerrainType使用Resource**: 类型安全、编辑器友好、性能高（预加载）
- **TerrainInstance使用Dictionary**: 灵活、可序列化、运行时修改

## 如何创建新的地形类型

### 方式1：在Godot编辑器中创建.tres文件

1. 在编辑器中右键点击 `res://data/terrain_types/` 目录
2. 选择 "新建资源" → 选择 "TerrainType"
3. 配置地形属性（见下文字段说明）
4. 保存为 `.tres` 文件（如 `stone_floor.tres`）

### 方式2：从JSON配置创建（需要转换）

1. 创建JSON配置文件（参考示例文件）
2. 在编辑器中手动创建对应的.tres文件
3. 或编写转换脚本批量导入

## 地形属性字段说明

### 基础属性
| 字段名 | 类型 | 说明 | 示例 |
|--------|------|------|------|
| terrain_type_id | String | 地形类型唯一标识符 | "stone_floor" |
| display_name | String | 显示名称 | "石制地面" |
| usage_type | Enum | 地块用途类型 | WALKABLE/SOLID/INTERACTIVE/HAZARD |

### 物理属性
| 字段名 | 类型 | 说明 | 默认值 |
|--------|------|------|--------|
| material_type | Enum | 材料类型（塑料/木材/石材/金属） | STONE |
| mass | float | 质量（千克） | 100.0 |
| friction_coefficient | float | 摩擦系数（0-无摩擦，1-正常，>1-高摩擦） | 1.0 |

### 生命值属性
| 字段名 | 类型 | 说明 | 默认值 |
|--------|------|------|--------|
| has_health | bool | 是否拥有生命值 | true |
| custom_max_health | int | 自定义生命值（-1=自动计算） | -1 |

**自动计算公式**: `max_health = mass * 材料系数`
- 塑料: 材料系数 = 25
- 木材: 材料系数 = 20
- 石材: 材料系数 = 30
- 金属: 材料系数 = 30

### 交互属性
| 字段名 | 类型 | 说明 | 默认值 |
|--------|------|------|--------|
| is_attackable | bool | 是否可被攻击 | false |
| is_interactive | bool | 是否可交互 | false |
| transform_to_id | String | 交互后转变的地形类型ID | "" |

### 移动属性
| 字段名 | 类型 | 说明 | 默认值 |
|--------|------|------|--------|
| is_passable | bool | 是否可经过 | true |

### 贴图属性
| 字段名 | 类型 | 说明 |
|--------|------|------|
| texture_paths | Array[String] | 六个面的贴图路径（按Godot Cubemap顺序） |

**顺序**: +X(右), -X(左), +Y(上), -Y(下), +Z(前), -Z(后)

### 高度属性
| 字段名 | 类型 | 说明 | 默认值 |
|--------|------|------|--------|
| base_height | int | 基础高度（格子数） | 0 |

## 如何在战斗中使用地形

### 1. 初始化（自动完成）
```gdscript
# TacticsBoard._init_systems() 中自动初始化
_terrain_manager = TerrainManager.new()
_terrain_manager.load_terrain_types_from_dir("res://data/terrain_types/")
```

### 2. 从战斗JSON加载地形实例
```json
{
  "terrain": {
	"instances": [
	  {
		"terrain_type_id": "stone_floor",
		"grid_pos": {"x": 5, "y": 5}
	  },
	  {
		"terrain_type_id": "wooden_door_closed",
		"grid_pos": {"x": 7, "y": 5}
	  }
	]
  }
}
```

### 3. 运行时查询地形属性
```gdscript
# 获取地形高度
var height = _terrain_manager.get_terrain_height(Vector2i(5, 5))

# 获取摩擦系数
var friction = _terrain_manager.get_terrain_friction(Vector2i(5, 5))

# 检查是否可经过
var passable = _terrain_manager.is_terrain_passable(Vector2i(7, 5))

# 检查是否可交互
var interactive = _terrain_manager.is_terrain_interactive(Vector2i(7, 5))
```

### 4. 交互地形
```gdscript
# 交互地形（如开关门）
var result = _terrain_manager.interact_terrain(Vector2i(7, 5))
if result.success:
	print("交互成功，新地形类型: ", result.new_type_id)
```

### 5. 应用动能伤害到地形
```gdscript
# 通过物理系统应用动能伤害
var damage = _physics_system._ctx.apply_kinetic_damage_to_terrain(
	7, 5, impact_velocity, impact_mass
)
```

## 性能优化

### 查询优化
- **物理属性缓存**: TerrainInstance在初始化时缓存物理属性，避免重复查询TerrainType
- **Resource预加载**: TerrainType资源在初始化时预加载，避免运行时动态加载

### 大地图支持
- **O(1)查询复杂度**: 地形实例使用Dictionary存储，格子坐标直接索引
- **批量加载**: 从JSON批量加载地形实例，一次性初始化所有缓存属性

## 示例场景

### 场景1：门的开关
```gdscript
# 玩家交互关闭的门
var door_grid = Vector2i(7, 5)
if _terrain_manager.is_terrain_interactive(door_grid):
	var result = _terrain_manager.interact_terrain(door_grid)
	# 门从 "wooden_door_closed" 转变为 "wooden_door_open"
	# is_passable 从 false 变为 true
```

### 场景2：地形损坏
```gdscript
# 玩家撞击窗户
var window_grid = Vector2i(9, 5)
var impact_velocity = Vector3(10, 0, 5)  # 高速撞击
var impact_mass = 80.0  # 玩家质量

var damage = _terrain_manager.apply_kinetic_damage_to_terrain(
	window_grid, impact_velocity, impact_mass
)
# 窗户生命值减少，可能损坏消失
```

## 未来扩展

### 可扩展点
- **新增材料类型**: 在TerrainType.MaterialType枚举中添加新类型
- **新增用途类型**: 在TerrainType.TerrainUsage枚举中添加新类型
- **自定义交互逻辑**: 继承TerrainManager并扩展interact_terrain方法
- **地形特效**: 在handle_terrain_death中添加坍塌动画等

### 集成建议
- **事件系统**: 地形交互、损坏等事件可以触发剧情节点
- **存档系统**: 地形实例状态可序列化到存档JSON
- **技能系统**: 某些技能可能直接影响地形（如地震术）

## 技术细节

### 材料系数对照表
| 材料 | 材料系数 | 动能抗性 | 说明 |
|------|----------|----------|------|
| PLASTIC | 25 | 0.5 | 容易损坏 |
| WOOD | 20 | 0.7 | 一般抗性 |
| STONE | 30 | 1.0 | 高抗性 |
| METAL | 30 | 1.5 | 最高抗性 |

### 动能伤害公式
```
kinetic_damage = |impact_velocity.length() * impact_mass| * kinetic_resistance
```

## 常见问题

**Q: 为什么TerrainType使用Resource而不是JSON？**
A: Resource提供类型安全、编辑器可视化配置、预加载性能优势，适合静态配置数据。

**Q: 如何批量创建地形类型？**
A: 创建JSON配置后，可以在编辑器中批量导入或编写转换脚本。

**Q: 地形实例如何序列化到存档？**
A: 调用 `_terrain_manager.get_all_terrain_instances()` 获取所有实例的字典数据，保存到JSON。

**Q: 地形损坏后如何处理？**
A: 地形生命值归零时自动调用 `handle_terrain_death()`，可以扩展该方法添加坍塌动画等效果。
