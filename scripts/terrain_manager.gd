class_name TerrainManager
extends RefCounted

## =============================================================================
## 地形管理系统 — 管理地形类型定义和地形实例数据
## =============================================================================
##
## 职责：
##   - 加载和管理TerrainType资源（地形类型定义）
##   - 创建和管理地形实例（运行时数据）
##   - 提供地形查询接口（类型、实例、物理属性）
##   - 处理地形交互和状态转变
##   - 集成PhysicsSystem进行物理计算
##
## 数据结构设计：
##   - _terrain_types: Dictionary {type_id: TerrainType} - 地形类型资源
##   - _terrain_instances: Dictionary {grid_key: TerrainInstance} - 地形实例
##
## 性能优化：
##   - TerrainType使用Resource预加载，类型安全且性能高
##   - TerrainInstance使用Dictionary，灵活且可序列化到JSON
##   - 物理属性查询通过缓存优化，避免重复计算
##
## 使用方式：
##   var terrain_mgr = TerrainManager.new()
##   terrain_mgr.load_terrain_types_from_dir("res://data/terrain_types/")
##   terrain_mgr.create_terrain_instance("stone_floor", Vector2i(5, 5))
## =============================================================================


# =============================================================================
# 数据结构
# =============================================================================

## 地形类型字典：{terrain_type_id: TerrainType}
var _terrain_types: Dictionary = {}

## 地形实例字典：{Vector2i(grid_col, grid_row): TerrainInstance}
var _terrain_instances: Dictionary = {}

## 物理系统引用（用于调用物理计算方法）
var _physics_system: PhysicsSystem = null


# =============================================================================
# TerrainInstance - 运行时地形实例数据
# =============================================================================

## 地形实例类：存储单个地块的运行时状态
class TerrainInstance:
	extends RefCounted

	## 地形类型ID（引用TerrainType）
	var terrain_type_id: String = ""

	## 格子坐标
	var grid_pos: Vector2i = Vector2i(-1, -1)

	## 当前生命值
	var current_health: int = 0

	## 最大生命值（缓存，避免重复计算）
	var max_health: int = 0

	## 当前高度（可能会因为地形交互而改变）
	var current_height: int = 0

	## 是否已交互（用于交互型地形的状态记录）
	var has_interacted: bool = false

	## 物理属性缓存（避免重复查询TerrainType）
	var cached_mass: float = 0.0
	var cached_friction: float = 0.0
	var cached_material_coefficient: int = 0
	var cached_kinetic_resistance: float = 0.0


	## 初始化地形实例
	func initialize(terrain_type: TerrainType, grid: Vector2i) -> void:
		terrain_type_id = terrain_type.terrain_type_id
		grid_pos = grid

		# 计算并缓存物理属性
		max_health = terrain_type.get_max_health()
		current_health = max_health
		current_height = terrain_type.base_height

		cached_mass = terrain_type.mass
		cached_friction = terrain_type.get_friction()
		cached_material_coefficient = terrain_type.get_material_coefficient()
		cached_kinetic_resistance = terrain_type.get_kinetic_resistance()


	## 应用伤害（返回是否存活）
	func apply_damage(damage: int) -> bool:
		if current_health <= 0:
			return false  # 已死亡

		current_health -= damage
		return current_health > 0


	## 转换为字典（用于序列化到JSON）
	func to_dict() -> Dictionary:
		return {
			"terrain_type_id": terrain_type_id,
			"grid_pos": {"x": grid_pos.x, "y": grid_pos.y},
			"current_health": current_health,
			"max_health": max_health,
			"current_height": current_height,
			"has_interacted": has_interacted
		}


	## 从字典加载（用于从JSON反序列化）
	static func from_dict(data: Dictionary) -> TerrainInstance:
		var instance := TerrainInstance.new()
		instance.terrain_type_id = data.get("terrain_type_id", "")
		var pos_data: Dictionary = data.get("grid_pos", {"x": -1, "y": -1})
		instance.grid_pos = Vector2i(pos_data.get("x", -1), pos_data.get("y", -1))
		instance.current_health = data.get("current_health", 0)
		instance.max_health = data.get("max_health", 0)
		instance.current_height = data.get("current_height", 0)
		instance.has_interacted = data.get("has_interacted", false)
		return instance


# =============================================================================
# 初始化方法
# =============================================================================

## 设置物理系统引用
func set_physics_system(physics: PhysicsSystem) -> void:
	_physics_system = physics


# =============================================================================
# 地形类型管理
# =============================================================================

## 从目录加载所有地形类型资源
## 目录结构：res://data/terrain_types/stone_floor.tres, wood_door.tres, ...
func load_terrain_types_from_dir(directory_path: String) -> void:
	var dir := DirAccess.open(directory_path)
	if dir == null:
		print("[TerrainManager] 无法打开目录: ", directory_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".tres"):
				var resource_path := directory_path + file_name
				var terrain_type := load(resource_path) as TerrainType
				if terrain_type != null and terrain_type.terrain_type_id != "":
					register_terrain_type(terrain_type)
					print("[TerrainManager] 加载地形类型: ", terrain_type.terrain_type_id,
						" 名称: ", terrain_type.display_name)
			elif file_name.ends_with(".json"):
				# 从JSON配置文件创建TerrainType资源
				_load_terrain_type_from_json(directory_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


## 注册单个地形类型
func register_terrain_type(terrain_type: TerrainType) -> void:
	if terrain_type.terrain_type_id == "":
		print("[TerrainManager] 地形类型ID为空，无法注册")
		return

	_terrain_types[terrain_type.terrain_type_id] = terrain_type


## 从JSON文件加载地形类型并注册
func _load_terrain_type_from_json(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("[TerrainManager] 无法打开JSON文件: ", file_path)
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		print("[TerrainManager] JSON解析失败: ", file_path, " error=", error)
		return

	var data: Dictionary = json.get_data()
	if not data is Dictionary:
		return

	var terrain_type := TerrainType.new()
	terrain_type.terrain_type_id = data.get("terrain_type_id", "")
	terrain_type.display_name = data.get("display_name", "")
	terrain_type.mass = data.get("mass", 100.0)
	terrain_type.friction_coefficient = data.get("friction_coefficient", 1.0)
	terrain_type.has_health = data.get("has_health", true)
	terrain_type.custom_max_health = data.get("custom_max_health", -1)
	terrain_type.is_attackable = data.get("is_attackable", false)
	terrain_type.is_interactive = data.get("is_interactive", false)
	terrain_type.transform_to_id = data.get("transform_to_id", "")
	terrain_type.is_passable = data.get("is_passable", true)
	terrain_type.base_height = data.get("base_height", 0)

	# usage_type: 字符串 → 枚举
	var usage_str: String = data.get("usage_type", "WALKABLE")
	match usage_str:
		"SOLID":
			terrain_type.usage_type = TerrainType.TerrainUsage.SOLID
		"WALKABLE":
			terrain_type.usage_type = TerrainType.TerrainUsage.WALKABLE
		"INTERACTIVE":
			terrain_type.usage_type = TerrainType.TerrainUsage.INTERACTIVE
		"HAZARD":
			terrain_type.usage_type = TerrainType.TerrainUsage.HAZARD
		_:
			terrain_type.usage_type = TerrainType.TerrainUsage.WALKABLE

	# material_type: 字符串 → 枚举
	var mat_str: String = data.get("material_type", "STONE")
	match mat_str:
		"PLASTIC":
			terrain_type.material_type = TerrainType.MaterialType.PLASTIC
		"WOOD":
			terrain_type.material_type = TerrainType.MaterialType.WOOD
		"STONE":
			terrain_type.material_type = TerrainType.MaterialType.STONE
		"METAL":
			terrain_type.material_type = TerrainType.MaterialType.METAL
		_:
			terrain_type.material_type = TerrainType.MaterialType.STONE

	# texture_paths
	var texture_paths_raw: Array = data.get("texture_paths", [])
	var tex_paths: Array[String] = []
	for tp in texture_paths_raw:
		tex_paths.append(str(tp))
	if tex_paths.size() == 6:
		terrain_type.texture_paths = tex_paths

	if terrain_type.terrain_type_id != "":
		register_terrain_type(terrain_type)
		print("[TerrainManager] 从JSON加载地形类型: ", terrain_type.terrain_type_id,
			" 名称: ", terrain_type.display_name, " 可通过: ", terrain_type.is_passable,
			" 可交互: ", terrain_type.is_interactive, " 转换: ", terrain_type.transform_to_id)


## 获取地形类型
func get_terrain_type(type_id: String) -> TerrainType:
	return _terrain_types.get(type_id, null)


## 获取所有已注册的地形类型ID列表
func get_all_terrain_type_ids() -> Array:
	return _terrain_types.keys()


# =============================================================================
# 地形实例管理
# =============================================================================

## 创建地形实例（在指定格子位置创建地形）
func create_terrain_instance(type_id: String, grid: Vector2i) -> TerrainInstance:
	var terrain_type := get_terrain_type(type_id)
	if terrain_type == null:
		print("[TerrainManager] 地形类型不存在: ", type_id)
		return null

	var instance := TerrainInstance.new()
	instance.initialize(terrain_type, grid)

	var key := grid
	_terrain_instances[key] = instance

	return instance


## 从字典批量创建地形实例（用于从JSON加载）
func load_terrain_instances_from_dict(instances_data: Array) -> void:
	for instance_data in instances_data:
		var instance := TerrainInstance.from_dict(instance_data)
		if instance.terrain_type_id != "" and instance.grid_pos != Vector2i(-1, -1):
			# 重新计算缓存属性（从TerrainType）
			var terrain_type := get_terrain_type(instance.terrain_type_id)
			if terrain_type != null:
				instance.cached_mass = terrain_type.mass
				instance.cached_friction = terrain_type.get_friction()
				instance.cached_material_coefficient = terrain_type.get_material_coefficient()
				instance.cached_kinetic_resistance = terrain_type.get_kinetic_resistance()

				var key := instance.grid_pos
				_terrain_instances[key] = instance


## 获取地形实例
func get_terrain_instance(grid: Vector2i) -> TerrainInstance:
	return _terrain_instances.get(grid, null)


## 删除地形实例
func remove_terrain_instance(grid: Vector2i) -> void:
	_terrain_instances.erase(grid)


## 获取所有地形实例（用于序列化）
func get_all_terrain_instances() -> Array:
	var instances: Array = []
	for instance in _terrain_instances.values():
		instances.append(instance.to_dict())
	return instances


# =============================================================================
# 地形查询接口（集成物理系统）
# =============================================================================

## 获取地形高度
func get_terrain_height(grid: Vector2i) -> int:
	var instance := get_terrain_instance(grid)
	if instance != null:
		return instance.current_height
	return 0  # 默认高度


## 获取指定格子的地形类型ID（支持默认类型查询）
## @param col: 列索引
## @param row: 行索引
## @param board: 棋盘引用（用于获取default_type配置）
func get_terrain_type_at(col: int, row: int, board) -> String:
	var key := Vector2i(col, row)

	# 1. 检查地形实例
	var instance := get_terrain_instance(key)
	if instance != null:
		return instance.terrain_type_id

	# 2. 检查是否被排除（不规则棋盘）
	if board != null and board._excluded_tiles.has(key):
		return ""  # 无地块

	# 3. 返回默认类型（从地形配置读取）
	if board != null:
		var terrain_config: Dictionary = board._terrain_config.get("terrain_config", {})
		return terrain_config.get("default_type", "stone_floor")

	return "stone_floor"  # 兜底默认类型


## 获取地形摩擦系数
func get_terrain_friction(grid: Vector2i) -> float:
	var instance := get_terrain_instance(grid)
	if instance != null:
		return instance.cached_friction
	return 1.0  # 默认摩擦系数


## 获取地形质量
func get_terrain_mass(grid: Vector2i) -> float:
	var instance := get_terrain_instance(grid)
	if instance != null:
		return instance.cached_mass
	return 100.0  # 默认质量


## 获取地形动能抗性
func get_terrain_kinetic_resistance(grid: Vector2i) -> float:
	var instance := get_terrain_instance(grid)
	if instance != null:
		return instance.cached_kinetic_resistance
	return 0.7  # 默认抗性


## 检查地形是否可经过
func is_terrain_passable(grid: Vector2i) -> bool:
	var instance := get_terrain_instance(grid)
	if instance != null:
		var terrain_type := get_terrain_type(instance.terrain_type_id)
		if terrain_type != null:
			return terrain_type.is_passable
	return true  # 默认可经过


## 检查地形是否可被攻击
func is_terrain_attackable(grid: Vector2i) -> bool:
	var instance := get_terrain_instance(grid)
	if instance != null:
		var terrain_type := get_terrain_type(instance.terrain_type_id)
		if terrain_type != null:
			return terrain_type.is_attackable
	return false  # 默认不可被攻击


## 检查地形是否可交互
func is_terrain_interactive(grid: Vector2i) -> bool:
	var instance := get_terrain_instance(grid)
	if instance != null:
		var terrain_type := get_terrain_type(instance.terrain_type_id)
		if terrain_type != null:
			return terrain_type.is_interactive
	return false  # 默认不可交互


## 获取地形生命值状态
func get_terrain_health_status(grid: Vector2i) -> Dictionary:
	var instance := get_terrain_instance(grid)
	if instance != null:
		return {
			"current": instance.current_health,
			"max": instance.max_health,
			"is_alive": instance.current_health > 0
		}
	return {"current": 0, "max": 0, "is_alive": false}


# =============================================================================
# 地形交互系统
# =============================================================================

## 交互地形（返回是否成功，以及新的地形类型ID）
func interact_terrain(grid: Vector2i) -> Dictionary:
	var instance := get_terrain_instance(grid)
	if instance == null:
		return {"success": false, "new_type_id": ""}

	var terrain_type := get_terrain_type(instance.terrain_type_id)
	if terrain_type == null or not terrain_type.is_interactive:
		return {"success": false, "new_type_id": ""}

	# 执行交互逻辑
	instance.has_interacted = not instance.has_interacted

	# 转换为新的地形类型（如门开关）
	var new_type_id := ""
	if terrain_type.transform_to_id != "":
		new_type_id = terrain_type.transform_to_id
		# 创建新的地形实例替换当前实例
		var new_instance := create_terrain_instance(new_type_id, grid)
		if new_instance != null:
			new_instance.has_interacted = instance.has_interacted
			# 保留生命值（如果新地形也有生命值）
			if new_instance.max_health > 0:
				new_instance.current_health = min(instance.current_health, new_instance.max_health)

	return {"success": true, "new_type_id": new_type_id}


# =============================================================================
# 地形伤害系统（集成物理系统）
# =============================================================================

## 应用动能伤害到地形（调用物理系统计算）
func apply_kinetic_damage_to_terrain(grid: Vector2i, impact_velocity: Vector3, impact_mass: float) -> int:
	if _physics_system == null:
		print("[TerrainManager] 物理系统未设置，无法计算动能伤害")
		return 0

	var instance := get_terrain_instance(grid)
	if instance == null or instance.current_health <= 0:
		return 0  # 地形不存在或已死亡

	# 调用物理系统计算动能伤害
	# 动能伤害 = (冲击速度 * 冲击质量) * 地形动能抗性
	var kinetic_damage := int(abs(impact_velocity.length() * impact_mass) * instance.cached_kinetic_resistance)

	# 应用伤害
	var is_alive := instance.apply_damage(kinetic_damage)

	print("[TerrainManager] 地形动能伤害: grid=", grid,
		" damage=", kinetic_damage,
		" health=", instance.current_health, "/", instance.max_health,
		" alive=", is_alive)

	# 如果地形死亡，可能触发坍塌等效果
	if not is_alive:
		handle_terrain_death(grid)

	return kinetic_damage


## 处理地形死亡（坍塌、消失等）
func handle_terrain_death(grid: Vector2i) -> void:
	var instance := get_terrain_instance(grid)
	if instance == null:
		return

	print("[TerrainManager] 地形死亡: grid=", grid, " type=", instance.terrain_type_id)

	# 移除地形实例（简化处理，实际可能需要坍塌动画等）
	remove_terrain_instance(grid)


# =============================================================================
# 辅助方法
# =============================================================================

## 统计地形类型数量
func get_terrain_type_count() -> int:
	return _terrain_types.size()


## 统计地形实例数量
func get_terrain_instance_count() -> int:
	return _terrain_instances.size()


## 清空所有数据
func clear_all() -> void:
	_terrain_types.clear()
	_terrain_instances.clear()
