# Godot 4.x 游戏引擎完全指南 —— AI 驱动游戏创作参考手册

> **文档目的**：本文档面向 AI 辅助游戏开发场景，从零开始系统介绍 Godot 4.x 引擎的每一个核心概念、节点类型、场景创建与使用方法。适合作为 AI 生成 Godot 游戏代码时的知识参考。

---

## 目录

1. [第一章：Godot 引擎概述与核心理念](#第一章godot-引擎概述与核心理念)
2. [第二章：节点系统详解](#第二章节点系统详解)
3. [第三章：场景系统与场景树](#第三章场景系统与场景树)
4. [第四章：GDScript 脚本编程](#第四章gdscript-脚本编程)
5. [第五章：信号系统](#第五章信号系统)
6. [第六章：2D 游戏开发完整指南](#第六章2d-游戏开发完整指南)
7. [第七章：3D 游戏开发完整指南](#第七章3d-游戏开发完整指南)
8. [第八章：UI 系统与 Control 节点](#第八章ui-系统与-control-节点)
9. [第九章：物理系统](#第九章物理系统)
10. [第十章：动画系统](#第十章动画系统)
11. [第十一章：音频系统](#第十一章音频系统)
12. [第十二章：着色器与视觉特效](#第十二章着色器与视觉特效)
13. [第十三章：输入系统](#第十三章输入系统)
14. [第十四章：资源管理与文件系统](#第十四章资源管理与文件系统)
15. [第十五章：场景切换与游戏流程](#第十五章场景切换与游戏流程)
16. [第十六章：性能优化与最佳实践](#第十六章性能优化与最佳实践)

---

## 第一章：Godot 引擎概述与核心理念

### 1.1 什么是 Godot

Godot 是一款**开源、免费、跨平台**的游戏引擎，采用 MIT 许可证，无版税。Godot 4.x 是最新主版本，引入了 Vulkan 渲染器、改进的 3D 系统、全新的 GDScript 2.0 等重大更新。

**核心特点：**
- 体积小巧（<100MB），无需安装，下载即用
- 内置完整的 2D 和 3D 工具链
- 专属脚本语言 GDScript（语法接近 Python）
- 支持 C#、C++（GDExtension）等多语言
- 跨平台导出：Windows、macOS、Linux、Android、iOS、Web

### 1.2 核心理念：一切皆节点

Godot 的架构基于一个核心设计哲学：**一切皆节点（Node）**。每个游戏对象都是一个节点，节点可以组合成场景，场景可以嵌套实例化。

```
游戏世界 = 场景树（Scene Tree）
场景树 = 多个场景（Scene）的嵌套组合
场景   = 一个根节点 + 若干子节点形成的树状结构
节点   = 具有特定功能的最小单元
```

### 1.3 Godot 4.x 项目结构

```
my_project/
├── project.godot          # 项目配置文件
├── scenes/                # 场景文件 (.tscn)
│   ├── player.tscn
│   ├── enemy.tscn
│   └── level.tscn
├── scripts/               # 脚本文件 (.gd)
│   ├── player.gd
│   └── enemy.gd
├── assets/                # 资源文件
│   ├── textures/          # 纹理/图片
│   ├── audio/             # 音频
│   ├── models/            # 3D 模型
│   └── fonts/             # 字体
├── shaders/               # 着色器 (.gdshader)
└── resources/             # 自定义资源 (.tres)
```

---

## 第二章：节点系统详解

### 2.1 节点基类：Node

**Node** 是所有节点的基类。其他所有节点都继承自 Node。它提供了最基本的生命周期和树管理功能。

**核心生命周期方法：**

| 方法 | 调用时机 | 用途 |
|------|---------|------|
| `_enter_tree()` | 节点进入场景树时 | 初始化逻辑 |
| `_ready()` | 节点及其所有子节点进入场景树后 | 初始化依赖子节点的逻辑 |
| `_process(delta)` | 每帧调用（渲染帧率） | 视觉更新、非物理逻辑 |
| `_physics_process(delta)` | 每物理帧调用（固定 60Hz） | 物理相关逻辑、移动 |
| `_exit_tree()` | 节点离开场景树时 | 清理资源 |

```gdscript
# 节点生命周期示例
extends Node

func _enter_tree():
	print("节点进入场景树")

func _ready():
	print("节点及子节点都已就绪")

func _process(delta):
	# delta: 上一帧到当前帧的时间间隔(秒)
	pass

func _physics_process(delta):
	# 固定频率调用，用于物理计算
	pass

func _exit_tree():
	print("节点即将离开场景树")
```

### 2.2 Node 的一级子节点分类

| 节点 | 功能说明 |
|------|----------|
| **Node** | 基础节点，用于组织和管理其他节点 |
| **Viewport** | 视口，决定画面显示区域和方式 |
| **CanvasItem** | 2D 图形绘制和 UI 元素的基类 |
| **Node3D** | 3D 场景中所有对象的基类 |
| **AnimationMixer** | 动画混合器，管理多个动画的混合 |
| **AudioStreamPlayer** | 音频流播放器 |
| **CanvasLayer** | 画布层，管理 2D 界面层级 |
| **HTTPRequest** | HTTP 请求节点 |
| **Timer** | 定时器，指定时间间隔后触发事件 |
| **WorldEnvironment** | 世界环境，设置天空盒、环境光等 |
| **NavigationAgent2D/3D** | 导航代理，自动寻路 |
| **ResourcePreloader** | 资源预加载器 |

### 2.3 节点操作核心 API

```gdscript
# 获取节点引用
@onready var child_node = $ChildNode          # 获取直接子节点
@onready var deep_node = $Path/To/Node        # 通过路径获取
@onready var sibling = $"../SiblingNode"      # 获取兄弟节点
@onready var root = get_tree().root           # 获取场景树根节点
@onready var node = get_node("Child/Path")    # 通过路径获取

# 添加/移除节点
var new_node = Node.new()
add_child(new_node)                           # 添加子节点
remove_child(new_node)                        # 移除子节点（不释放）
new_node.queue_free()                         # 排队释放节点（安全）

# 节点属性
node.name = "NewName"                         # 节点名称
node.process_mode = Node.PROCESS_MODE_DISABLED # 禁用处理
node.owner                                    # 场景所有者
node.is_inside_tree()                         # 是否在场景树中

# 遍历子节点
for child in get_children():
	print(child.name)
```

---

## 第三章：场景系统与场景树

### 3.1 场景的概念

场景（Scene）是一个或多个节点的树状组合，保存为 `.tscn` 文件。场景既可以代表整个游戏关卡，也可以代表可复用的组件（如玩家角色、敌人、UI 面板）。

**场景的核心理念：**
- 每个场景有一个**根节点**
- 根节点下可以有任意多层的子节点
- 场景可以**实例化**到其他场景中（类似"预制体"）

### 3.2 场景实例化

```gdscript
extends Node2D

# 方法一：使用 @export 在编辑器中赋值
@export var player_scene: PackedScene

# 方法二：使用 preload 预加载（编译时）
var bullet_scene = preload("res://scenes/bullet.tscn")

# 方法三：使用 load 动态加载（运行时）
func _ready():
	var enemy_scene = load("res://scenes/enemy.tscn")

# 实例化场景
func spawn_player():
	var player = player_scene.instantiate()  # 创建实例
	player.position = Vector2(100, 200)
	add_child(player)                        # 添加到场景树
```

### 3.3 场景树结构

```
Root (Window)
├── MainScene (Node2D)
│   ├── Player (CharacterBody2D)
│   │   ├── Sprite2D
│   │   ├── CollisionShape2D
│   │   └── Camera2D
│   ├── Enemy1 (实例化自 enemy.tscn)
│   ├── Enemy2 (实例化自 enemy.tscn)
│   └── TileMapLayer (地形)
└── UI (CanvasLayer)
	├── ScoreLabel (Label)
	└── HealthBar (ProgressBar)
```

### 3.4 场景切换

```gdscript
# 切换场景
get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# 使用 PackedScene 切换
get_tree().change_scene_to_packed(level_scene)

# 重新加载当前场景
get_tree().reload_current_scene()
```

### 3.5 场景设计最佳实践

- **拆分为小型专用场景**：玩家、敌人、子弹、UI 各自独立为场景
- **松耦合**：使用信号通信，避免硬编码节点路径
- **使用 `@onready` 缓存节点引用**：避免在 `_process` 中频繁调用 `get_node()`

---

## 第四章：GDScript 脚本编程

### 4.1 基础语法

```gdscript
# 变量声明
var health: int = 100
var speed: float = 200.0
var player_name: String = "Hero"
var is_alive: bool = true
var direction: Vector2 = Vector2.ZERO
var color: Color = Color.WHITE

# 常量
const MAX_HEALTH: int = 100
const GRAVITY: float = 980.0

# 导出变量（在编辑器中可见）
@export var jump_force: float = 400.0
@export_range(0, 100) var power: int = 50
@export var player_scene: PackedScene
@export var sprite: Texture2D

# 延迟初始化（在 _ready 前赋值）
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# 函数定义
func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		die()

# 函数返回值
func get_health_percent() -> float:
	return float(health) / float(MAX_HEALTH)
```

### 4.2 控制流

```gdscript
# 条件判断
if health <= 0:
	die()
elif health < 30:
	show_low_health_warning()
else:
	pass

# match 语句（类似 switch）
match state:
	"idle":
		play_idle_animation()
	"run":
		play_run_animation()
	"jump", "fall":
		play_air_animation()
	_:
		print("未知状态")

# for 循环
for i in range(10):
	print(i)

for enemy in get_tree().get_nodes_in_group("enemies"):
	enemy.take_damage(10)

# while 循环
while health > 0:
	await get_tree().create_timer(1.0).timeout
	health -= 5
```

### 4.3 信号基础

```gdscript
# 定义自定义信号
signal player_died
signal health_changed(new_health: int, max_health: int)

# 发出信号
func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0:
		player_died.emit()

# 连接信号（代码方式）
func _ready():
	$Timer.timeout.connect(_on_timer_timeout)
	$Area2D.body_entered.connect(_on_body_entered)

func _on_timer_timeout():
	print("定时器触发")

func _on_body_entered(body: Node2D):
	print("物体进入区域:", body.name)
```

### 4.4 协程与异步

```gdscript
# 使用 await 等待
func delayed_action():
	await get_tree().create_timer(2.0).timeout  # 等待 2 秒
	print("2 秒后执行")

# 等待信号
func wait_for_player():
	await player_died  # 等待 player_died 信号
	show_game_over()

# 等待动画结束
func play_and_wait(anim_name: String):
	$AnimationPlayer.play(anim_name)
	await $AnimationPlayer.animation_finished
	print("动画播放完毕")
```

### 4.5 类与继承

```gdscript
# 定义类
class_name Enemy
extends CharacterBody2D

@export var health: int = 50
@export var move_speed: float = 100.0

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()

# 继承
class_name SlimeEnemy
extends Enemy

func _ready():
	health = 30          # 覆盖父类属性
	move_speed = 50.0    # 覆盖父类属性
```

---

## 第五章：信号系统

### 5.1 信号分类

| 信号类型 | 实现方式 | 传播范围 | 核心用途 |
|----------|---------|---------|---------|
| **局部信号** | 脚本内定义 `signal` | 点对点 | 组件内部通信 |
| **全局信号** | Autoload 单例定义 | 全场广播 | 跨系统通知 |
| **内置信号** | 引擎节点自带 | 特定事件 | 碰撞、定时器、输入 |

### 5.2 局部信号

```gdscript
# 定义与发出信号
signal damage_taken(amount: int, source: Node)

func take_damage(amount: int, attacker: Node):
	health -= amount
	damage_taken.emit(amount, attacker)

# 连接与接收信号
func _ready():
	$DamageComponent.damage_taken.connect(_on_damage_taken)

func _on_damage_taken(amount: int, source: Node):
	print("受到 %d 点伤害，来源: %s" % [amount, source.name])
```

### 5.3 全局信号总线（Autoload）

```gdscript
# SignalBus.gd - 设为 Autoload
extends Node

signal player_scored(points: int)
signal game_paused
signal game_resumed
signal level_completed(level_id: int)

# 在任何脚本中使用
func collect_coin():
	score += 10
	SignalBus.player_scored.emit(10)

# UI 脚本中监听
func _ready():
	SignalBus.player_scored.connect(_on_score_update)

func _on_score_update(points: int):
	total_score += points
	$ScoreLabel.text = str(total_score)
```

### 5.4 常用内置信号

| 节点 | 信号 | 触发时机 |
|------|------|----------|
| `Timer` | `timeout` | 定时器到期 |
| `Button` | `pressed` | 按钮被按下 |
| `Area2D/3D` | `body_entered` | 物理体进入区域 |
| `Area2D/3D` | `body_exited` | 物理体离开区域 |
| `Area2D/3D` | `area_entered` | 另一区域进入 |
| `AnimationPlayer` | `animation_finished` | 动画播放完毕 |
| `CharacterBody2D` | `velocity_computed` | 速度计算完成 |
| `HTTPRequest` | `request_completed` | HTTP 请求完成 |

---

## 第六章：2D 游戏开发完整指南

### 6.1 2D 节点继承体系

```
CanvasItem
├── Node2D                   # 2D 节点基类
│   ├── AnimatedSprite2D     # 逐帧动画精灵
│   ├── AudioListener2D      # 2D 音频监听器
│   ├── AudioStreamPlayer2D  # 2D 音频播放器
│   ├── Bone2D               # 2D 骨骼
│   ├── Camera2D             # 2D 相机
│   ├── CanvasGroup          # 画布组
│   ├── CollisionObject2D    # 2D 碰撞对象基类
│   │   ├── Area2D           # 2D 区域检测
│   │   └── PhysicsBody2D    # 2D 物理体基类
│   │       ├── CharacterBody2D  # 角色控制器
│   │       ├── RigidBody2D      # 刚体
│   │       └── StaticBody2D     # 静态体
│   ├── CPUParticles2D       # CPU 粒子系统
│   ├── GPUParticles2D       # GPU 粒子系统
│   ├── Light2D              # 2D 光源
│   ├── Line2D               # 2D 线条
│   ├── Path2D               # 2D 路径
│   ├── RayCast2D            # 2D 射线检测
│   ├── RemoteTransform2D    # 远程变换
│   ├── Sprite2D             # 2D 精灵（显示图片）
│   ├── TileMapLayer         # 瓦片地图层
│   └── TouchScreenButton    # 触屏按钮
```

### 6.2 Sprite2D - 精灵显示

```gdscript
# 创建精灵
var sprite = Sprite2D.new()
sprite.texture = preload("res://assets/player.png")
sprite.position = Vector2(100, 200)
sprite.scale = Vector2(2, 2)
sprite.modulate = Color(1, 0.5, 0.5)  # 颜色调制
sprite.visible = true
sprite.z_index = 1                     # 绘制层级
sprite.centered = true                 # 居中锚点
add_child(sprite)

# 翻转
sprite.flip_h = true   # 水平翻转
sprite.flip_v = false  # 垂直翻转

# 旋转（弧度）
sprite.rotation = deg_to_rad(45)
```

### 6.3 AnimatedSprite2D - 逐帧动画

```gdscript
extends Node2D

@onready var anim_sprite = $AnimatedSprite2D

func _ready():
	# 创建 SpriteFrames 资源
	var frames = SpriteFrames.new()

	# 添加动画（需要先加载纹理）
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 5.0)
	frames.add_frame("idle", preload("res://idle_1.png"))
	frames.add_frame("idle", preload("res://idle_2.png"))

	frames.add_animation("run")
	frames.set_animation_speed("run", 10.0)
	frames.add_frame("run", preload("res://run_1.png"))
	frames.add_frame("run", preload("res://run_2.png"))

	anim_sprite.sprite_frames = frames
	anim_sprite.play("idle")

func update_animation(velocity: Vector2):
	if velocity.length() > 0:
		anim_sprite.play("run")
		anim_sprite.flip_h = velocity.x < 0
	else:
		anim_sprite.play("idle")
```

### 6.4 Camera2D - 2D 相机

```gdscript
extends Camera2D

func _ready():
	# 设置相机限制范围
	limit_left = 0
	limit_top = 0
	limit_right = 2000
	limit_bottom = 1000

	# 使相机平滑
	position_smoothing_enabled = true
	position_smoothing_speed = 5.0

	# 缩放
	zoom = Vector2(1.5, 1.5)

	# 使相机成为当前视口的活动相机
	make_current()

# 相机震动效果
func shake(intensity: float, duration: float):
	var original_pos = position
	var elapsed = 0.0
	while elapsed < duration:
		position = original_pos + Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	position = original_pos
```

### 6.5 TileMapLayer - 瓦片地图

```gdscript
extends Node2D

@onready var tile_map = $TileMapLayer

func _ready():
	# 设置单个瓦片
	tile_map.set_cell(Vector2i(5, 5), 0, Vector2i(0, 0))

	# 批量设置瓦片（生成平台）
	for x in range(0, 20):
		tile_map.set_cell(Vector2i(x, 10), 0, Vector2i(1, 0))

	# 获取瓦片数据
	var tile_data = tile_map.get_cell_tile_data(Vector2i(5, 5))

	# 清除瓦片
	tile_map.erase_cell(Vector2i(5, 5))
```

### 6.6 完整的 2D 角色控制器

```gdscript
extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_velocity: float = -400.0
@export var gravity: float = 980.0

@onready var sprite = $Sprite2D
@onready var anim_player = $AnimationPlayer

func _physics_process(delta):
	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# 跳跃
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 水平移动
	var direction = Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * speed
		sprite.flip_h = direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()

	# 更新动画
	if not is_on_floor():
		anim_player.play("jump")
	elif direction != 0:
		anim_player.play("run")
	else:
		anim_player.play("idle")
```

---

## 第七章：3D 游戏开发完整指南

### 7.1 3D 节点继承体系

```
Node3D                              # 3D 节点基类
├── AudioListener3D                 # 3D 音频监听器
├── AudioStreamPlayer3D             # 3D 音频播放器
├── BoneAttachment3D                # 骨骼附着点
├── Camera3D                        # 3D 相机
├── CollisionObject3D               # 3D 碰撞对象基类
│   ├── Area3D                      # 3D 区域检测
│   └── PhysicsBody3D               # 3D 物理体基类
│       ├── CharacterBody3D         # 3D 角色控制器
│       ├── RigidBody3D             # 3D 刚体
│       └── StaticBody3D            # 3D 静态体
├── CollisionShape3D                # 3D 碰撞形状
├── GridMap                         # 3D 网格地图
├── Light3D                         # 3D 光源基类
│   ├── DirectionalLight3D          # 平行光（太阳光）
│   ├── OmniLight3D                 # 点光源
│   └── SpotLight3D                 # 聚光灯
├── Marker3D                        # 3D 标记点
├── MeshInstance3D                  # 网格实例（显示 3D 模型）
├── NavigationRegion3D              # 3D 导航区域
├── Path3D                          # 3D 路径
├── RayCast3D                       # 3D 射线检测
├── SpringArm3D                     # 弹簧臂（相机跟随）
├── Skeleton3D                      # 3D 骨骼
├── SoftBody3D                      # 3D 软体
└── VehicleBody3D                   # 3D 载具体
```

### 7.2 基础 3D 场景搭建

```gdscript
extends Node3D

func _ready():
	# 创建世界环境
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_color = Color(0.3, 0.3, 0.4)
	world_env.environment = env
	add_child(world_env)

	# 创建平行光
	var sun = DirectionalLight3D.new()
	sun.position = Vector3(0, 10, 0)
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	# 创建相机
	var camera = Camera3D.new()
	camera.position = Vector3(0, 5, 10)
	camera.look_at(Vector3.ZERO)
	add_child(camera)

	# 创建地面
	var ground = StaticBody3D.new()
	var ground_mesh = MeshInstance3D.new()
	ground_mesh.mesh = PlaneMesh.new()
	ground_mesh.mesh.size = Vector2(20, 20)
	var ground_collision = CollisionShape3D.new()
	ground_collision.shape = BoxShape3D.new()
	ground_collision.shape.size = Vector3(20, 0.1, 20)
	ground.add_child(ground_mesh)
	ground.add_child(ground_collision)
	add_child(ground)
```

### 7.3 MeshInstance3D - 3D 模型显示

```gdscript
# 创建基础网格
var mesh_instance = MeshInstance3D.new()

# 使用内置网格类型
mesh_instance.mesh = BoxMesh.new()       # 立方体
mesh_instance.mesh = SphereMesh.new()    # 球体
mesh_instance.mesh = CylinderMesh.new()  # 圆柱体
mesh_instance.mesh = PlaneMesh.new()     # 平面

# 加载外部模型
mesh_instance.mesh = preload("res://models/character.glb")

# 材质设置
var material = StandardMaterial3D.new()
material.albedo_color = Color.RED
material.metallic = 0.5
material.roughness = 0.3
mesh_instance.material_override = material

# 变换
mesh_instance.position = Vector3(0, 1, 0)
mesh_instance.rotation_degrees = Vector3(0, 45, 0)
mesh_instance.scale = Vector3(2, 2, 2)

add_child(mesh_instance)
```

### 7.4 Camera3D - 3D 相机

```gdscript
extends Camera3D

func _ready():
	# 设置投影模式
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = 75.0  # 视场角
	near = 0.1  # 近裁剪面
	far = 1000.0  # 远裁剪面

	make_current()

# 第三人称相机跟随
@export var target: Node3D
@export var follow_distance: float = 5.0
@export var follow_height: float = 2.0

func _process(delta):
	if target:
		var target_pos = target.global_position
		position = position.lerp(
			target_pos + Vector3(0, follow_height, follow_distance),
			5.0 * delta
		)
		look_at(target_pos)
```

### 7.5 SpringArm3D - 弹簧臂

```gdscript
extends SpringArm3D

func _ready():
	spring_length = 5.0           # 弹簧长度
	position = Vector3(0, 2, 0)   # 相对于父节点的位置

	# 碰撞检测
	add_excluded_object(get_parent())

func _input(event):
	if event is InputEventMouseMotion:
		# 水平旋转
		rotate_y(-event.relative.x * 0.005)
		# 垂直旋转（限制范围）
		rotation.x = clamp(
			rotation.x - event.relative.y * 0.005,
			deg_to_rad(-60),
			deg_to_rad(30)
		)
```

### 7.6 完整的 3D 角色控制器

```gdscript
extends CharacterBody3D

@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var jump_velocity: float = 5.0
@export var gravity: float = 20.0
@export var mouse_sensitivity: float = 0.002

@onready var camera_pivot = $CameraPivot
@onready var spring_arm = $CameraPivot/SpringArm3D
@onready var anim_player = $AnimationPlayer

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	# 重力
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 跳跃
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 获取输入
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = _get_camera_relative_direction(input_dir)

	# 判断是否冲刺
	var is_sprinting = Input.is_action_pressed("sprint")
	var current_speed = run_speed if is_sprinting else walk_speed

	# 应用移动
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	# 旋转角色朝向移动方向
	if direction.length() > 0.1:
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)

	move_and_slide()

func _get_camera_relative_direction(input: Vector2) -> Vector3:
	var cam_basis = camera_pivot.global_transform.basis
	var forward = -cam_basis.z
	var right = cam_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	return (forward * -input.y + right * input.x).normalized()

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(
			spring_arm.rotation.x,
			deg_to_rad(-60),
			deg_to_rad(40)
		)
```

---

## 第八章：UI 系统与 Control 节点

### 8.1 Control 节点继承体系

```
Control                              # UI 基类
├── Button                           # 按钮
├── Label                            # 文本标签
├── RichTextLabel                    # 富文本标签
├── LineEdit                         # 单行文本输入
├── TextEdit                         # 多行文本输入
├── TextureRect                      # 纹理矩形
├── TextureButton                    # 纹理按钮
├── TextureProgressBar               # 纹理进度条
├── ProgressBar                      # 进度条
├── ColorRect                        # 纯色矩形
├── ColorPicker / ColorPickerButton  # 颜色选择器
├── Panel / PanelContainer           # 面板
├── CheckBox / CheckButton           # 复选框
├── HSlider / VSlider                # 滑动条
├── SpinBox                          # 数值输入框
├── OptionButton                     # 下拉选择框
├── MenuButton                       # 菜单按钮
├── LinkButton                       # 超链接按钮
├── ItemList                         # 列表
├── Tree                             # 树形结构
├── TabBar / TabContainer            # 标签页
├── NinePatchRect                    # 九宫格
├── VideoStreamPlayer                # 视频播放器
├── Window / Popup / PopupPanel      # 窗口/弹窗
├── AcceptDialog / ConfirmationDialog # 确认对话框
├── FileDialog                       # 文件选择对话框
├── GraphEdit / GraphNode            # 图表编辑器
├── Separator                        # 分隔线
├── ScrollBar / ScrollContainer      # 滚动条/滚动容器
├── SubViewportContainer             # 子视口容器
└── Container                        # 容器基类
	├── BoxContainer
	│   ├── HBoxContainer            # 横向排列
	│   └── VBoxContainer            # 纵向排列
	├── GridContainer                # 网格排列
	├── MarginContainer              # 内边距
	├── CenterContainer              # 居中
	├── PanelContainer               # 面板容器
	├── ScrollContainer              # 滚动容器
	├── TabContainer                 # 标签容器
	└── AspectRatioContainer         # 宽高比容器
```

### 8.2 锚点（Anchor）与布局

```gdscript
# Control 节点的锚点属性
# anchor_left: 0.0 (左边缘) ~ 1.0 (右边缘)
# anchor_top: 0.0 (上边缘) ~ 1.0 (下边缘)
# anchor_right: 0.0 ~ 1.0
# anchor_bottom: 0.0 ~ 1.0

# 全屏填充
control.anchor_left = 0.0
control.anchor_top = 0.0
control.anchor_right = 1.0
control.anchor_bottom = 1.0

# 居中
control.anchor_left = 0.5
control.anchor_top = 0.5
control.anchor_right = 0.5
control.anchor_bottom = 0.5

# 偏移量（像素）
control.offset_left = -100   # 锚点向左偏移
control.offset_top = -50     # 锚点向上偏移
control.offset_right = 100   # 锚点向右偏移
control.offset_bottom = 50   # 锚点向下偏移
```

### 8.3 常用 UI 示例

```gdscript
# 创建文本标签
var label = Label.new()
label.text = "Hello, Godot!"
label.add_theme_font_size_override("font_size", 24)
label.add_theme_color_override("font_color", Color.WHITE)
label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
add_child(label)

# 创建按钮
var button = Button.new()
button.text = "开始游戏"
button.pressed.connect(_on_start_button_pressed)
add_child(button)

# 创建进度条（血条）
var health_bar = ProgressBar.new()
health_bar.min_value = 0
health_bar.max_value = 100
health_bar.value = 75
add_child(health_bar)

# 创建输入框
var input = LineEdit.new()
input.placeholder_text = "请输入名称..."
input.text_changed.connect(_on_name_changed)
add_child(input)

# 定时器
var timer = Timer.new()
timer.wait_time = 1.0
timer.one_shot = false
timer.timeout.connect(_on_timer_timeout)
add_child(timer)
timer.start()
```

### 8.4 容器布局示例

```gdscript
# 使用 VBoxContainer 纵向排列
var vbox = VBoxContainer.new()
vbox.add_theme_constant_override("separation", 10)  # 间距

var label = Label.new()
label.text = "标题"
vbox.add_child(label)

var button1 = Button.new()
button1.text = "选项 1"
vbox.add_child(button1)

var button2 = Button.new()
button2.text = "选项 2"
vbox.add_child(button2)

add_child(vbox)

# 使用 HBoxContainer 横向排列
var hbox = HBoxContainer.new()
for i in range(3):
	var btn = Button.new()
	btn.text = "按钮 %d" % i
	hbox.add_child(btn)
add_child(hbox)
```

### 8.5 CanvasLayer - UI 层级管理

```gdscript
# CanvasLayer 用于独立于游戏世界的 UI（HUD、菜单等）
# layer 值越大，显示越靠前
var hud_layer = CanvasLayer.new()
hud_layer.layer = 10  # 最顶层

var score_label = Label.new()
score_label.text = "Score: 0"
hud_layer.add_child(score_label)
add_child(hud_layer)
```

---

## 第九章：物理系统

### 9.1 物理体类型对比

| 物理体 | 运动方式 | 碰撞检测 | 适用场景 |
|--------|---------|---------|---------|
| **CharacterBody2D/3D** | 代码控制 | 滑动碰撞 | 玩家、敌人 |
| **RigidBody2D/3D** | 物理模拟 | 完整碰撞响应 | 可推动的物体、弹射物 |
| **StaticBody2D/3D** | 不移动 | 阻挡其他物体 | 墙壁、地面、平台 |
| **Area2D/3D** | 不参与物理 | 进入/离开检测 | 触发器、拾取区域、伤害区域 |

### 9.2 CharacterBody2D 完整示例

```gdscript
extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_velocity: float = -400.0
@export var gravity: float = 980.0
@export var acceleration: float = 1000.0
@export var friction: float = 800.0

func _physics_process(delta):
	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# 跳跃（包含跳跃缓冲）
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 水平移动（带加速度）
	var direction = Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)

	move_and_slide()

	# 碰撞后处理
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		print("碰撞到: ", collision.get_collider().name)
```

### 9.3 RigidBody2D 示例

```gdscript
extends RigidBody2D

func _ready():
	# 物理属性
	mass = 1.0
	gravity_scale = 1.0
	linear_damp = 0.1      # 线性阻尼
	angular_damp = 1.0     # 角阻尼

	# 施加力
	apply_central_force(Vector2(500, 0))
	# 施加冲量
	apply_central_impulse(Vector2(0, -300))
	# 施加力矩
	apply_torque(1000)

# 碰撞响应
func _on_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(10)
```

### 9.4 Area2D 触发器

```gdscript
extends Area2D

func _ready():
	# 连接信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)

func _on_body_entered(body: Node2D):
	if body.is_in_group("player"):
		print("玩家进入区域")
		# 收集金币
		if is_in_group("coin"):
			body.add_score(10)
			queue_free()

func _on_body_exited(body: Node2D):
	print("物体离开区域")

func _on_area_entered(area: Area2D):
	print("另一区域进入")
```

### 9.5 碰撞层与掩码

```gdscript
# 碰撞层（Layer）：定义"我是什么"
# 碰撞掩码（Mask）：定义"我能检测到什么"

# 设置碰撞层（第 1 层）
collision_layer = 1
set_collision_layer_value(1, true)

# 设置碰撞掩码（检测第 2 层和第 3 层）
collision_mask = 6  # 0b110 = 第2层 | 第3层
set_collision_mask_value(2, true)
set_collision_mask_value(3, true)

# 推荐的层级划分
# Layer 1:  平台/地形
# Layer 2:  玩家
# Layer 3:  敌人
# Layer 4:  弹射物
# Layer 5:  可拾取物品
# Layer 6:  触发器/传感器

# 碰撞规则：A 的 mask 包含 B 的 layer 或 B 的 mask 包含 A 的 layer
```

### 9.6 RayCast2D 射线检测

```gdscript
extends RayCast2D

func _ready():
	enabled = true
	target_position = Vector2(0, 50)  # 向下检测 50 像素
	exclude_parent = true

func _physics_process(delta):
	if is_colliding():
		var collider = get_collider()
		var collision_point = get_collision_point()
		var collision_normal = get_collision_normal()
		print("检测到碰撞: ", collider.name)

# 强制更新射线
func check_ground():
	force_raycast_update()
	return is_colliding()
```

---

## 第十章：动画系统

### 10.1 AnimationPlayer - 动画播放器

```gdscript
extends Node2D

@onready var anim_player = $AnimationPlayer

func _ready():
	# 播放动画
	anim_player.play("idle")

	# 动画属性
	anim_player.speed_scale = 1.5       # 播放速度
	anim_player.play("attack", -1, 2.0) # 从第 1 秒开始，2 倍速

	# 连接信号
	anim_player.animation_finished.connect(_on_animation_finished)

func _on_animation_finished(anim_name: String):
	match anim_name:
		"attack":
			print("攻击动画结束")
			anim_player.play("idle")
		"die":
			queue_free()

func play_animation(anim_name: String):
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

# 程序化控制动画
func seek_animation():
	anim_player.seek(0.5)          # 跳转到 0.5 秒
	anim_player.stop()             # 停止
	anim_player.pause()            # 暂停
	var is_playing = anim_player.is_playing()
	var current = anim_player.current_animation
```

### 10.2 AnimationPlayer 创建动画轨道（代码方式）

```gdscript
# 创建 AnimationPlayer 和动画
var anim_player = AnimationPlayer.new()
add_child(anim_player)

# 创建动画资源
var animation = Animation.new()
animation.length = 1.0
animation.loop_mode = Animation.LOOP_LINEAR

# 添加轨道：位置
var track_idx = animation.add_track(Animation.TYPE_VALUE)
animation.track_set_path(track_idx, ".:position")
animation.track_insert_key(track_idx, 0.0, Vector2(0, 0))
animation.track_insert_key(track_idx, 0.5, Vector2(100, -50))
animation.track_insert_key(track_idx, 1.0, Vector2(0, 0))

# 添加轨道：旋转
var rot_track = animation.add_track(Animation.TYPE_VALUE)
animation.track_set_path(rot_track, ".:rotation")
animation.track_insert_key(rot_track, 0.0, 0.0)
animation.track_insert_key(rot_track, 1.0, deg_to_rad(360))

# 将动画添加到 AnimationPlayer
var anim_lib = AnimationLibrary.new()
anim_lib.add_animation("spin", animation)
anim_player.add_animation_library("main", anim_lib)
anim_player.play("main/spin")
```

### 10.3 Tween - 补间动画

```gdscript
func create_tween_animation():
	# 创建 Tween
	var tween = create_tween()
	# 或手动创建
	var tween = get_tree().create_tween()

	# 基础属性动画
	tween.tween_property(self, "position", Vector2(200, 100), 1.0)
	tween.tween_property(self, "scale", Vector2(2, 2), 0.5)

	# 链式动画
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "position:x", 300, 1.0)

	# 并行动画
	tween.parallel().tween_property(self, "position:y", 200, 0.5)
	tween.parallel().tween_property(self, "rotation", deg_to_rad(360), 0.5)

	# 设置过渡类型和缓动
	tween.tween_property(self, "position", Vector2(500, 0), 1.0) \
		.set_trans(Tween.TRANS_ELASTIC) \
		.set_ease(Tween.EASE_OUT)

	# 常用过渡类型
	# Tween.TRANS_LINEAR    - 线性
	# Tween.TRANS_QUAD      - 二次
	# Tween.TRANS_CUBIC     - 三次
	# Tween.TRANS_ELASTIC   - 弹性
	# Tween.TRANS_BOUNCE    - 弹跳
	# Tween.TRANS_BACK      - 回弹

	# 常用缓动类型
	# Tween.EASE_IN    - 缓入
	# Tween.EASE_OUT   - 缓出
	# Tween.EASE_IN_OUT - 缓入缓出

	# 回调
	tween.tween_callback(_on_tween_finished)

	# 间隔
	tween.tween_interval(0.5)

	# 设置循环
	tween.set_loops(3)

func _on_tween_finished():
	print("Tween 动画完成")
```

### 10.4 AnimationTree - 动画树（状态机）

```gdscript
extends CharacterBody2D

@onready var anim_tree = $AnimationTree
@onready var state_machine = anim_tree["parameters/playback"]

func _ready():
	anim_tree.active = true

func _physics_process(delta):
	# 根据状态切换动画
	if not is_on_floor():
		if velocity.y < 0:
			state_machine.travel("jump")
		else:
			state_machine.travel("fall")
	elif velocity.length() > 0:
		state_machine.travel("run")
	else:
		state_machine.travel("idle")

	# 设置混合参数
	anim_tree.set("parameters/idle/blend_position", velocity)
	anim_tree.set("parameters/run/blend_position", velocity)

# 触发一次性动画
func attack():
	anim_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
```

---

## 第十一章：音频系统

### 11.1 音频节点

```gdscript
# AudioStreamPlayer - 全局音频
var music_player = AudioStreamPlayer.new()
music_player.stream = preload("res://assets/bgm.ogg")
music_player.volume_db = -10.0   # 音量（分贝）
music_player.pitch_scale = 1.0   # 音调
music_player.autoplay = true
music_player.bus = "Music"       # 音频总线
add_child(music_player)
music_player.play()

# AudioStreamPlayer2D - 2D 空间音频
var sfx_2d = AudioStreamPlayer2D.new()
sfx_2d.stream = preload("res://assets/explosion.wav")
sfx_2d.max_distance = 500.0      # 最大听觉距离
sfx_2d.attenuation = 1.0         # 衰减系数
sfx_2d.position = Vector2(100, 100)
add_child(sfx_2d)
sfx_2d.play()

# AudioStreamPlayer3D - 3D 空间音频
var sfx_3d = AudioStreamPlayer3D.new()
sfx_3d.stream = preload("res://assets/footstep.wav")
sfx_3d.unit_size = 1.0           # 距离单位
sfx_3d.max_db = 0.0              # 最大音量
sfx_3d.position = Vector3(0, 1, 0)
add_child(sfx_3d)
sfx_3d.play()
```

### 11.2 音频总线（Audio Bus）

```gdscript
# 在编辑器中设置音频总线（Audio Bus Layout）
# 默认总线：Master
# 可以添加：Music、SFX、Voice 等

# 代码中设置总线
var audio_player = AudioStreamPlayer.new()
audio_player.bus = "SFX"  # 路由到 SFX 总线

# 获取总线索引和设置音量
var bus_idx = AudioServer.get_bus_index("Master")
AudioServer.set_bus_volume_db(bus_idx, -6.0)
AudioServer.set_bus_mute(bus_idx, false)

# 添加总线效果
var effect = AudioEffectReverb.new()
AudioServer.add_bus_effect(bus_idx, effect)
```

### 11.3 音效池模式

```gdscript
# 音效池 - 避免频繁创建销毁 AudioStreamPlayer
class_name SoundPool
extends Node

var pool: Array[AudioStreamPlayer] = []
var pool_size: int = 10

func _ready():
	for i in range(pool_size):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		pool.append(player)

func play(sound: AudioStream, volume_db: float = 0.0):
	for player in pool:
		if not player.playing:
			player.stream = sound
			player.volume_db = volume_db
			player.play()
			return player
	# 池已满，尝试回收最旧的
	var oldest = pool[0]
	oldest.stop()
	oldest.stream = sound
	oldest.play()
	return oldest
```

---

## 第十二章：着色器与视觉特效

### 12.1 着色器类型

| 类型 | 声明 | 适用场景 |
|------|------|---------|
| **Canvas Item** | `shader_type canvas_item;` | 2D 精灵、UI 元素 |
| **Spatial** | `shader_type spatial;` | 3D 模型材质 |
| **Particles** | `shader_type particles;` | 粒子系统 |
| **Sky** | `shader_type sky;` | 天空着色器 |
| **Fog** | `shader_type fog;` | 体积雾效果 |

### 12.2 2D Canvas Item 着色器

```glsl
// dissolve.gdshader - 溶解效果
shader_type canvas_item;

uniform float dissolve_amount: hint_range(0.0, 1.0) = 0.0;
uniform sampler2D noise_texture: hint_default_white;
uniform vec4 edge_color: source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float edge_width: hint_range(0.0, 0.2) = 0.05;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float noise = texture(noise_texture, UV).r;

	float edge = step(dissolve_amount, noise);
	float edge_glow = smoothstep(dissolve_amount, dissolve_amount + edge_width, noise);

	COLOR = tex_color * edge;
	COLOR = mix(edge_color * tex_color.a, COLOR, edge_glow);
}
```

```glsl
// pulse.gdshader - 脉冲发光效果
shader_type canvas_item;

uniform float speed: hint_range(0.0, 5.0) = 2.0;
uniform float strength: hint_range(0.0, 1.0) = 0.5;
uniform vec4 glow_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float pulse = sin(TIME * speed) * 0.5 + 0.5;
	COLOR = tex * mix(vec4(1.0), glow_color, pulse * strength);
}
```

```glsl
// outline.gdshader - 描边效果
shader_type canvas_item;

uniform vec4 outline_color: source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width: hint_range(0.0, 5.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 texel_size = TEXTURE_PIXEL_SIZE * outline_width;

	float alpha = tex.a;
	alpha += texture(TEXTURE, UV + vec2(texel_size.x, 0.0)).a;
	alpha += texture(TEXTURE, UV + vec2(-texel_size.x, 0.0)).a;
	alpha += texture(TEXTURE, UV + vec2(0.0, texel_size.y)).a;
	alpha += texture(TEXTURE, UV + vec2(0.0, -texel_size.y)).a;

	COLOR = mix(outline_color, tex, tex.a);
	COLOR.a = max(alpha, tex.a);
}
```

### 12.3 3D Spatial 着色器

```glsl
// hologram.gdshader - 全息投影效果
shader_type spatial;

uniform float scan_speed: hint_range(0.0, 10.0) = 2.0;
uniform vec3 hologram_color: source_color = vec3(0.2, 0.8, 1.0);

void fragment() {
	float scanline = step(0.5, fract((UV.y + UV.x * 0.2) * 20.0 - TIME * scan_speed));
	float alpha = scanline * 0.8 + 0.2;

	ALBEDO = hologram_color * (scanline * 0.7 + 0.3);
	EMISSION = hologram_color * 0.5;
	ALPHA = alpha;
	ROUGHNESS = 0.0;
	METALLIC = 1.0;
}
```

### 12.4 将着色器应用到材质

```gdscript
# 2D 着色器
var shader_material = ShaderMaterial.new()
shader_material.shader = preload("res://shaders/dissolve.gdshader")
shader_material.set_shader_parameter("dissolve_amount", 0.5)
$Sprite2D.material = shader_material

# 3D 着色器
var spatial_material = ShaderMaterial.new()
spatial_material.shader = preload("res://shaders/hologram.gdshader")
$MeshInstance3D.material_override = spatial_material

# 动态修改参数
func update_dissolve(amount: float):
	$Sprite2D.material.set_shader_parameter("dissolve_amount", amount)
```

### 12.5 GPUParticles2D - GPU 粒子

```gdscript
extends GPUParticles2D

func _ready():
	# 粒子属性
	amount = 50                     # 粒子数量
	lifetime = 1.0                  # 生命周期
	one_shot = true                 # 单次发射
	explosiveness = 1.0             # 爆发性
	preprocess = 0.0                # 预处理时间

	# 设置粒子材质
	var process_material = ParticleProcessMaterial.new()
	process_material.direction = Vector3(0, -1, 0)   # 方向
	process_material.spread = 45.0                     # 扩散角度
	process_material.gravity = Vector3(0, 98, 0)      # 重力
	process_material.initial_velocity_min = 100.0      # 最小速度
	process_material.initial_velocity_max = 200.0      # 最大速度
	process_material.scale_min = 0.5
	process_material.scale_max = 1.0

	process_material.color = GradientTexture1D.new()
	# 在编辑器中设置颜色渐变...

	process_material = process_material

# 发射粒子
func emit_particles():
	restart()  # 重新开始发射
	emitting = true  # 持续发射
```

---

## 第十三章：输入系统

### 13.1 Input Map 配置

```gdscript
# 在 Project Settings > Input Map 中配置动作
# 或在代码中动态创建

func _ready():
	# 创建输入动作
	InputMap.add_action("jump")
	InputMap.action_add_event("jump", create_key_event(KEY_SPACE))
	InputMap.action_add_event("jump", create_key_event(KEY_W))
	InputMap.action_add_event("jump", create_joy_button_event(0, JOY_BUTTON_A))

	InputMap.add_action("move_left")
	InputMap.action_add_event("move_left", create_key_event(KEY_A))
	InputMap.action_add_event("move_left", create_key_event(KEY_LEFT))

	InputMap.add_action("move_right")
	InputMap.action_add_event("move_right", create_key_event(KEY_D))
	InputMap.action_add_event("move_right", create_key_event(KEY_RIGHT))

func create_key_event(keycode) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = keycode
	return event

func create_joy_button_event(device, button) -> InputEventJoypadButton:
	var event = InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	return event
```

### 13.2 输入检测

```gdscript
func _input(event):
	# 检测按键按下
	if event.is_action_pressed("jump"):
		print("跳跃按下")

	if event.is_action_released("jump"):
		print("跳跃释放")

	# 鼠标事件
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("鼠标左键按下, 位置: ", event.position)

	if event is InputEventMouseMotion:
		print("鼠标移动: ", event.relative)

	# 手柄事件
	if event is InputEventJoypadMotion:
		print("手柄摇杆: ", event.axis, " = ", event.axis_value)

func _process(delta):
	# 持续检测
	if Input.is_action_pressed("move_right"):
		position.x += speed * delta

	# 获取轴向输入（-1 到 1）
	var horizontal = Input.get_axis("move_left", "move_right")
	var vertical = Input.get_axis("move_up", "move_down")

	# 获取二维输入向量
	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# 检测按键按住
	if Input.is_key_pressed(KEY_SHIFT):
		is_sprinting = true

	# 鼠标位置
	var mouse_pos = get_global_mouse_position()
```

### 13.3 手柄支持

```gdscript
func _ready():
	# 检测连接的手柄
	var joypads = Input.get_connected_joypads()
	for joypad in joypads:
		print("检测到手柄: ", Input.get_joy_name(joypad))

	# 手柄振动
	Input.start_joy_vibration(0, 0.5, 0.5, 0.5)  # 设备0, 弱电机, 强电机, 持续秒数
	Input.stop_joy_vibration(0)
```

### 13.4 触屏与虚拟摇杆

```gdscript
# 触屏按钮
extends TouchScreenButton

func _ready():
	pressed.connect(_on_pressed)
	released.connect(_on_released)

# 多点触控
func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			print("触摸按下: ", event.position)
		else:
			print("触摸释放: ", event.position)

	if event is InputEventScreenDrag:
		print("触摸拖动: ", event.relative)
```

---

## 第十四章：资源管理与文件系统

### 14.1 资源加载

```gdscript
# preload - 编译时加载（推荐）
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const BULLET_TEXTURE = preload("res://assets/bullet.png")

# load - 运行时加载
var enemy_scene = load("res://scenes/enemy.tscn")
var level_path = "res://scenes/level_%d.tscn" % level_id
var level_scene = load(level_path)

# 资源预加载器
@onready var preloader = $ResourcePreloader
# preloader.add_resource("enemy", preload("res://enemy.tscn"))
# var enemy = preloader.get_resource("enemy").instantiate()
```

### 14.2 文件读写

```gdscript
# 用户数据目录
var user_dir = OS.get_user_data_dir()  # 用户数据目录
var save_path = "user://savegame.json"

# 保存 JSON
func save_game():
	var data = {
		"player_name": player_name,
		"score": score,
		"level": current_level,
		"position": {
			"x": player.position.x,
			"y": player.position.y
		}
	}
	var json_string = JSON.stringify(data, "\t")
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(json_string)
	file.close()

# 读取 JSON
func load_game():
	if not FileAccess.file_exists(save_path):
		return false

	var file = FileAccess.open(save_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error == OK:
		var data = json.data
		player_name = data["player_name"]
		score = data["score"]
		current_level = data["level"]
		player.position = Vector2(data["position"]["x"], data["position"]["y"])
		return true
	return false

# ConfigFile 方式（INI 格式）
func save_config():
	var config = ConfigFile.new()
	config.set_value("Player", "name", player_name)
	config.set_value("Player", "level", current_level)
	config.set_value("Audio", "music_volume", music_volume)
	config.set_value("Audio", "sfx_volume", sfx_volume)
	config.save("user://settings.cfg")

func load_config():
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err == OK:
		player_name = config.get_value("Player", "name", "Default")
		music_volume = config.get_value("Audio", "music_volume", 1.0)
```

### 14.3 自定义 Resource

```gdscript
# ItemData.gd - 自定义资源类
class_name ItemData
extends Resource

@export var item_name: String = "Item"
@export var description: String = ""
@export var icon: Texture2D
@export var max_stack: int = 99
@export var item_type: String = "consumable"
@export var value: int = 0
@export var effect_value: int = 0

# CharacterStats.gd - 角色属性资源
class_name CharacterStats
extends Resource

@export var max_health: float = 100.0
@export var move_speed: float = 300.0
@export var jump_force: float = 400.0
@export var attack_power: float = 10.0
@export var defense: float = 5.0
```

---

## 第十五章：场景切换与游戏流程

### 15.1 场景切换

```gdscript
# 基本场景切换
func change_to_level(level_path: String):
	get_tree().change_scene_to_file(level_path)

# 带加载画面
func change_scene_with_loading(scene_path: String):
	# 先切换到加载画面
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")

	# 使用 ResourceLoader 异步加载
	ResourceLoader.load_threaded_request(scene_path)
	var progress = []
	while true:
		var status = ResourceLoader.load_threaded_get_status(scene_path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				# 更新加载进度条
				print("加载中: ", progress[0] * 100, "%")
			ResourceLoader.THREAD_LOAD_LOADED:
				var scene = ResourceLoader.load_threaded_get(scene_path)
				get_tree().change_scene_to_packed(scene)
				break
			ResourceLoader.THREAD_LOAD_FAILED:
				print("加载失败")
				break
		await get_tree().process_frame
```

### 15.2 游戏状态管理（Autoload）

```gdscript
# GameManager.gd - 设为 Autoload
extends Node

var score: int = 0
var current_level: int = 1
var is_paused: bool = false
var player_health: int = 100

signal score_changed(new_score: int)
signal game_paused
signal game_resumed
signal game_over

func add_score(amount: int):
	score += amount
	score_changed.emit(score)

func pause_game():
	is_paused = true
	get_tree().paused = true
	game_paused.emit()

func resume_game():
	is_paused = false
	get_tree().paused = false
	game_resumed.emit()

func trigger_game_over():
	game_over.emit()
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func restart_level():
	score = 0
	get_tree().paused = false
	get_tree().reload_current_scene()
```

### 15.3 组（Groups）管理

```gdscript
# 将节点添加到组
func _ready():
	add_to_group("enemies")
	add_to_group("damageable")

# 获取组中的所有节点
func find_all_enemies():
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.activate()

# 调用组中所有节点的方法
func damage_all_enemies(amount: int):
	get_tree().call_group("enemies", "take_damage", amount)

# 检查节点是否在组中
if node.is_in_group("player"):
	print("找到玩家")

# 从组中移除
remove_from_group("enemies")
```

---

## 第十六章：性能优化与最佳实践

### 16.1 节点引用缓存

```gdscript
# 好的做法：使用 @onready 缓存引用
@onready var sprite = $Sprite2D
@onready var anim_player = $AnimationPlayer
@onready var collision = $CollisionShape2D

# 避免！在 _process 中频繁调用 get_node()
func _process(delta):
	# 错误：每帧获取节点引用
	var sprite = get_node("Sprite2D")  # 不要这样做
	sprite.position.x += 1
```

### 16.2 对象池模式

```gdscript
# ObjectPool.gd - 通用对象池
class_name ObjectPool
extends Node

var pool: Array = []
var scene: PackedScene
var initial_size: int = 10

func _init(p_scene: PackedScene, p_size: int = 10):
	scene = p_scene
	initial_size = p_size
	_fill_pool()

func _fill_pool():
	for i in range(initial_size):
		var obj = scene.instantiate()
		obj.visible = false
		obj.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(obj)
		pool.append(obj)

func get_object() -> Node:
	for obj in pool:
		if not obj.visible:
			obj.visible = true
			obj.process_mode = Node.PROCESS_MODE_INHERIT
			return obj
	# 池已空，创建新对象
	var obj = scene.instantiate()
	add_child(obj)
	pool.append(obj)
	return obj

func return_object(obj: Node):
	obj.visible = false
	obj.process_mode = Node.PROCESS_MODE_DISABLED
```

### 16.3 减少 _process 中的计算

```gdscript
# 使用信号驱动而非轮询
func _ready():
	# 好的做法：使用信号
	$Area2D.body_entered.connect(_on_body_entered)

# 避免在 _process 中做不必要的检查
func _process(delta):
	# 错误：每帧检查
	# if player_in_range():
	#     do_something()

	# 好的做法：只在需要时更新
	pass

# 使用 Timer 替代持续 _process 检查
func _ready():
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = false
	timer.timeout.connect(_check_player_range)
	add_child(timer)
	timer.start()

func _check_player_range():
	# 每 0.5 秒检查一次，而非每帧
	if player_in_range():
		do_something()
```

### 16.4 场景优化

```gdscript
# 使用 VisibleOnScreenNotifier2D 优化
extends VisibleOnScreenNotifier2D

func _ready():
	screen_entered.connect(_on_screen_entered)
	screen_exited.connect(_on_screen_exited)

func _on_screen_entered():
	# 进入屏幕时激活
	process_mode = Node.PROCESS_MODE_INHERIT
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_INHERIT

func _on_screen_exited():
	# 离开屏幕时休眠
	process_mode = Node.PROCESS_MODE_DISABLED
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
```

### 16.5 代码规范与目录结构

```gdscript
# 推荐的目录结构
# res://
# ├── scenes/          # 场景文件
# │   ├── levels/      # 关卡场景
# │   ├── characters/  # 角色场景
# │   └── ui/          # UI 场景
# ├── scripts/         # 脚本文件
# │   ├── player/      # 玩家相关脚本
# │   ├── enemies/     # 敌人相关脚本
# │   └── systems/     # 系统脚本
# ├── assets/          # 资源文件
# │   ├── sprites/     # 精灵图
# │   ├── audio/       # 音频
# │   ├── fonts/       # 字体
# │   └── models/      # 3D 模型
# ├── shaders/         # 着色器
# ├── resources/       # 自定义资源 (.tres)
# └── autoload/        # Autoload 单例脚本
```

### 16.6 常用调试技巧

```gdscript
# 打印调试信息
print("调试信息: ", variable)
print_debug("仅调试模式显示")
push_warning("警告信息")
push_error("错误信息")

# 断言
assert(health >= 0, "生命值不能为负数")
assert(speed > 0, "速度必须大于 0")

# 断点（在编辑器中点击行号左侧设置断点）
# 使用调试器面板查看变量值

# 性能监控
func _ready():
	# 显示性能监视器（FPS、内存等）
	pass
	# 在编辑器中：调试器 > 性能监视器

# 远程场景树调试
# 运行游戏后，在编辑器中切换到"远程"标签查看实时场景树
```

---

## 附录 A：Godot 4.x 常用快捷键

| 快捷键 | 功能 |
|--------|------|
| `Ctrl + N` | 新建场景 |
| `Ctrl + S` | 保存场景 |
| `Ctrl + Shift + S` | 另存为场景 |
| `Ctrl + A` | 添加子节点 |
| `F5` | 运行项目 |
| `F8` | 运行当前场景 |
| `F6` | 运行特定场景 |
| `Ctrl + K` | 切换注释 |
| `Ctrl + D` | 复制节点 |
| `Ctrl + G` | 将选中节点编组 |
| `F2` | 重命名节点 |
| `Q / W / E / R` | 切换工具（选择/移动/旋转/缩放） |
| `Ctrl + Scroll` | 缩放视图 |
| `Middle Mouse Drag` | 平移视图 |

---

## 附录 B：Godot 4.x 常用类参考速查

| 类名 | 用途 | 关键方法 |
|------|------|---------|
| `Node` | 所有节点基类 | `add_child()`, `queue_free()`, `get_node()` |
| `Node2D` | 2D 节点基类 | `position`, `rotation`, `scale` |
| `Node3D` | 3D 节点基类 | `position`, `rotation`, `scale`, `global_transform` |
| `Sprite2D` | 显示 2D 图片 | `texture`, `flip_h`, `flip_v`, `modulate` |
| `CharacterBody2D` | 2D 角色控制器 | `move_and_slide()`, `velocity`, `is_on_floor()` |
| `CharacterBody3D` | 3D 角色控制器 | `move_and_slide()`, `velocity`, `is_on_floor()` |
| `Area2D` / `Area3D` | 区域检测 | `body_entered`, `body_exited`, `area_entered` |
| `RigidBody2D` / `RigidBody3D` | 刚体物理 | `apply_force()`, `apply_impulse()` |
| `StaticBody2D` / `StaticBody3D` | 静态物理体 | 碰撞阻挡 |
| `Camera2D` | 2D 相机 | `make_current()`, `zoom`, `limit_*` |
| `Camera3D` | 3D 相机 | `make_current()`, `fov`, `look_at()` |
| `AnimationPlayer` | 动画播放器 | `play()`, `stop()`, `animation_finished` |
| `Tween` | 补间动画 | `tween_property()`, `set_trans()`, `set_ease()` |
| `Timer` | 定时器 | `start()`, `stop()`, `timeout` |
| `AudioStreamPlayer` | 音频播放 | `play()`, `stop()`, `stream` |
| `Label` | 文本标签 | `text`, `add_theme_font_size_override()` |
| `Button` | 按钮 | `pressed`, `text` |
| `Control` | UI 基类 | `anchor_*`, `offset_*` |
| `PackedScene` | 打包场景 | `instantiate()` |
| `Input` | 输入系统 | `is_action_pressed()`, `get_axis()`, `get_vector()` |
| `FileAccess` | 文件访问 | `open()`, `store_string()`, `get_as_text()` |
| `JSON` | JSON 处理 | `stringify()`, `parse()` |
| `ConfigFile` | 配置文件 | `set_value()`, `get_value()`, `save()`, `load()` |
| `ResourceLoader` | 资源加载 | `load()`, `load_threaded_request()` |

---

## 附录 C：AI 生成代码时的核心原则

在 AI 驱动游戏创作时，请遵循以下 Godot 4.x 核心原则：

1. **一切皆节点**：每个游戏对象都是一个节点，通过组合节点构建功能
2. **场景 = 可复用组件**：将角色、道具、UI 面板都做成独立场景
3. **信号向上，调用向下**：子节点通过信号通知父节点，父节点通过方法调用控制子节点
4. **使用 @onready 缓存引用**：避免在 `_process` 中频繁调用 `get_node()`
5. **物理逻辑放在 `_physics_process` 中**：确保帧率无关的物理行为
6. **使用 `move_and_slide()` 而非手动位置更新**：让引擎处理碰撞
7. **碰撞层和掩码必须正确配置**：Layer 定义"我是谁"，Mask 定义"我能检测谁"
8. **优先使用信号而非轮询**：减少 `_process` 中的不必要检查
9. **使用 Autoload 管理全局状态**：游戏管理器、信号总线、配置数据
10. **场景文件 (.tscn) 和脚本文件 (.gd) 分离**：保持项目结构清晰

---

> 文档版本：v1.0
> 适用引擎：Godot 4.x（4.0 - 4.5）
> 脚本语言：GDScript 2.0
