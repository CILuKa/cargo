# FIRST_TRY 项目架构文档

> Godot 4.1+ 战术RPG × 视觉小说混合游戏项目  
> 日式学园背景，棋战+物理+可交互地形

---

## 目录结构概览

```
FIRST_TRY/
├── project.godot              # 项目配置（主场景 main_menu.tscn, 1920×1080）
├── scenes/                    # Godot 场景文件 (.tscn)
├── scripts/                   # GDScript 脚本（17个文件）
├── data/                      # JSON 数据配置
│   ├── battles/               # 战斗配置
│   ├── skills/                # 技能定义
│   ├── terrain_types/         # 地形类型定义
│   └── story/                 # 剧情分支子节点
├── assets/                    # 图片资源（角色立绘、单位精灵）
├── tools/                     # 外部工具
│   └── terrain_editor.py      # Python 3D 地形编辑器
└── docs/                      # 文档（地形格式、使用指南）
```

---

## 核心架构

```
┌─────────────────────────────────────────────────────┐
│                    Autoload（全局单例）                │
│  GameState ─ 剧情flag/好感度/章节                    │
│  SaveManager ─ 10档位存档                           │
│  CharacterRoster ─ 角色模板（knight, slime等）        │
└─────────────────────────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│   MainMenu       │            │   GameScreen      │
│   标题画面        │───────────▶│   主游戏画面       │
│  新游戏/读档/设置 │            │  立绘/对话/选择   │
└──────────────────┘            └────────┬─────────┘
                                        │ 触发battle效果
                                        ▼
                              ┌──────────────────┐
                              │  TacticsBoard     │
                              │  3D 战棋棋盘      │
                              │  ┌──────────────┐│
                              │  │ TurnManager   ││ 行动顺序
                              │  │ SkillSystem   ││ 技能执行
                              │  │ PhysicsSystem ││ 物理结算
                              │  │ TerrainManager││ 地形管理
                              │  └──────────────┘│
                              └──────────────────┘
```

**数据流**: JSON 配置 → GDScript 解析 → 运行时对象 → 场景渲染

---

## 文件作用速查

### 场景文件 (`scenes/`)

| 文件 | 作用 | 涉及的脚本 |
|------|------|-----------|
| `main_menu.tscn` | 标题画面（新游戏/读档/设置） | `main_menu.gd` |
| `game_screen.tscn` | 主游戏画面（立绘/对话/剧情树） | `game_screen.gd`, `dialogue_manager.gd` |
| `tactics_board.tscn` | 3D战棋棋盘（SubViewport 渲染） | `tactics_board.gd` |
| `tactics_unit.tscn` | 3D单位模板（Sprite3D + 名字标签） | `tactics_unit.gd` |
| `settings_window.tscn` | 设置弹出窗 | `settings_window.gd` |
| `save_load_window.tscn` | 存档/读档窗（10档位） | `save_load_window.gd` |
| `log_window.tscn` | 对话历史记录窗 | `log_window.gd` |

### GDScript 脚本 (`scripts/`)

| 文件 | 类型 | 作用 |
|------|------|------|
| `game_state.gd` | Autoload | 全局剧情flag、好感度、章节、路线 |
| `save_manager.gd` | Autoload | 存档管理（user://saves/slot_N.json） |
| `character_roster.gd` | Autoload | 角色模板库（属性、技能） |
| `main_menu.gd` | Control | 标题画面逻辑 |
| `game_screen.gd` | Control | 主游戏画面、加载战斗、管理子窗口 |
| `dialogue_manager.gd` | Node | JSON剧情解析器、效果执行、分支跳转 |
| `tactics_board.gd` | Control | **战棋核心**：棋盘生成、单位管理、行动菜单、移动/攻击/技能/交互 |
| `tactics_unit.gd` | Node3D | 单位属性（HP/ATK/DEF/速度/技能）、PhysicsBody引用 |
| `turn_manager.gd` | RefCounted | 行动槽回合排序（mental_speed） |
| `skill_system.gd` | RefCounted | 技能执行引擎（伤害/治疗/推击/传送） |
| `physics_system.gd` | RefCounted | 物理引擎（矢量速度结算、碰撞、重力、动能伤害） |
| `physics_body.gd` | Resource | 单体物理数据（质量、速度、动能计算） |
| `terrain_type.gd` | Resource | 地形类型定义类（材质、贴图、可通过/可交互） |
| `terrain_manager.gd` | RefCounted | 地形管理器（实例、查询、交互转换、伤害） |
| `settings_window.gd` | Control | 设置窗逻辑 |
| `save_load_window.gd` | Control | 存档窗UI逻辑 |
| `log_window.gd` | Control | 对话历史窗逻辑 |

### JSON 数据配置 (`data/`)

| 路径 | 作用 |
|------|------|
| `story_chapter1.json` | 第一章剧情树（对话、选项、flag、战斗触发） |
| `story/story_ch1_battle_win.json` | 战斗后剧情分支 |
| `battles/battle_001.json` | "史莱姆遭遇战" 配置（70×55棋盘、单位、胜负条件） |
| `battles/battle_002.json` | "护送逃脱战" 配置 |
| `battles/battle_terrain_001.json` | battle_001 的3D地形数据（方块层） |
| `skills/skill_attack.json` | 基础攻击技能 |
| `skills/skill_fireball.json` | 火球术技能 |
| `skills/skill_heal.json` | 治疗技能 |
| `skills/skill_push.json` | 推击技能（含动量传递） |
| `terrain_types/terrain_example_config.json` | "stone_floor" 石制地面 |
| `terrain_types/terrain_stone_wall.json` | "stone_wall" 石墙（不可通过，高3） |
| `terrain_types/terrain_metal_window.json` | "metal_window" 金属窗（可攻击） |
| `terrain_types/terrain_wooden_door_closed.json` | "wooden_door_closed" 关闭木门（可交互→打开） |
| `terrain_types/terrain_wooden_door_open.json` | "wooden_door_open" 打开木门（可交互→关闭，可通过） |

### Python 工具 (`tools/`)

| 文件 | 作用 |
|------|------|
| `terrain_editor.py` | 3D地形编辑器（pygame+OpenGL，4模式：放置/面放置/编辑/移动） |

---

## AI 阅读提示词

当用户提出问题时，**根据关键词**选择性阅读文件，避免全量加载所有代码：

### 战斗/战棋相关
```
关键词: 战斗、棋盘、单位、移动、攻击、技能、回合、行动菜单、交互、跳下
应读文件:
- scripts/tactics_board.gd      ← 核心（棋盘、菜单、状态机）
- scripts/tactics_unit.gd       ← 单位属性
- scripts/turn_manager.gd       ← 回合排序
- scripts/skill_system.gd       ← 技能执行
- data/battles/battle_001.json  ← 战斗配置
- data/battles/battle_terrain_001.json ← 地形数据
- data/skills/*.json            ← 技能定义
```

### 物理/碰撞/重力相关
```
关键词: 物理、碰撞、重力、速度、矢量、摩擦、动能、坠落、动量
应读文件:
- scripts/physics_system.gd     ← 核心物理引擎
- scripts/physics_body.gd       ← 物理数据
- scripts/tactics_board.gd      ← 物理结算调用点（_settle_velocity, _end_current_unit_turn）
```

### 地形/编辑器相关
```
关键词: 地形、方块、格子、通过、交互、门、墙、材质、编辑器
应读文件:
- scripts/terrain_manager.gd    ← 地形管理系统
- scripts/terrain_type.gd       ← 地形类型类
- data/terrain_types/*.json     ← 地形配置
- tools/terrain_editor.py       ← 编辑器代码
- data/battles/battle_terrain_001.json ← 地形实例数据
- docs/terrain_system_usage.md  ← 地形系统文档
```

### 剧情/对话相关
```
关键词: 剧情、对话、选项、立绘、章节、flag、好感度、路线
应读文件:
- scripts/dialogue_manager.gd   ← 剧情引擎
- scripts/game_screen.gd        ← 主画面
- data/story_chapter1.json      ← 剧情数据
- data/story/*.json             ← 剧情分支
- scripts/game_state.gd         ← 全局状态
```

### UI/菜单相关
```
关键词: 菜单、按钮、选择、存档、读档、设置、日志、标题
应读文件:
- scripts/main_menu.gd
- scripts/save_load_window.gd
- scripts/settings_window.gd
- scripts/log_window.gd
- scripts/save_manager.gd       ← 存档引擎
- scripts/game_screen.gd        ← 主UI
```

### 角色/单位属性相关
```
关键词: 角色、单位、属性、HP、ATK、技能、模板
应读文件:
- scripts/tactics_unit.gd       ← 单位属性
- scripts/character_roster.gd   ← 角色模板
- data/skills/*.json            ← 技能数值
```

---

## 关键代码流程

### 战斗启动流程
```
game_screen.gd → 监听 DialogueManager.battle_started 信号
               → load_battle_config("data/battles/battle_001.json")
               → tactics_board.gd:load_battle_config()
                    → _load_terrain_config() 推导 terrain_001.json
                    → _create_tiles() 生成3D方块
                    → _place_battle_units() 放置单位
                    → _init_systems() 初始化 TurnManager/SkillSystem/PhysicsSystem/TerrainManager
                    → TurnManager.start_battle() 开始回合
```

### 回合结算流程
```
玩家行动结束 → _end_current_unit_turn()
            → PhysicsSystem.settle_velocity(unit)  矢量速度结算
            → TurnManager.end_current_turn()  推到下一个单位
                 → 如果当前轮所有单位行动完
                      → round_ended 信号
                      → 所有单位 settle_velocity  统一物理结算
                      → _next_round()  下一轮
```

### 交互转换流程
```
点击"交互" → _on_action_interact()
          → _show_interact_range()  显示白色线框
          → 点击可交互地块 → _execute_interact()
               → TerrainManager.interact_terrain()  转换实例
               → 更新 _terrain_data  类型/高度
               → _clear_tiles_at() + _build_single_tile()  重建视觉方块
               → 更新单位位置（可通过性可能变化）
```

---

## 技术要点

- **`@tool`**: `tactics_board.gd` 标记为 `@tool`，在Godot编辑器中可预览棋盘（`Engine.is_editor_hint()` 检测）
- **`class_name`**: 所有核心类使用 `class_name` 实现全局类型引用
- **JSON驱动**: 战斗、技能、剧情、地形全部使用JSON配置，无需硬编码
- **BoardContext 解耦**: `PhysicsSystem` 通过 `BoardContext` 接口访问棋盘，不直接依赖 `TacticsBoard`
- **非空保护**: 地形编辑器使用 `None` 占位处理面放置产生的层空洞
