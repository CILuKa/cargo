class_name PhysicsSystem
extends RefCounted

## =============================================================================
## 战棋物理系统 — 统一管理矢量速度、碰撞、摩擦、重力等物理逻辑
## =============================================================================
##
## 职责：
##   - 矢量速度结算（回合结束时滑动 + 方向匹配 + 衰减）
##   - 碰撞检测与分辨率（单位↔单位、单位↔地形、坠地碰撞）
##   - 重力加速度与空中状态管理
##   - 摩擦衰减与地块物理属性查询
##   - 动能伤害计算
##   - 技能推击/冲量方向处理
##
## 设计原则：
##   - 所有物理逻辑集中于此，棋盘(TacticsBoard)只负责委托调用
##   - 通过 BoardContext 接口解耦对棋盘的依赖，方便单元测试
##   - PhysicsBody 只负责单个物理体的数据（质量、速度、动能），不做世界级计算
##
## 使用方式：
##   var ctx = PhysicsSystem.BoardContext.new()
##   ctx.configure(board)
##   var physics = PhysicsSystem.new(ctx)
##   physics.settle_velocity(unit)
## =============================================================================


# =============================================================================
# 方向常量
# =============================================================================

## 8个方向向量（grid坐标），用于矢量速度匹配最接近的滑动方向
const SLIDE_DIRECTIONS: Array[Vector2] = [
	Vector2(0, -1),   Vector2(1, -1),   # 北, 东北
	Vector2(1, 0),    Vector2(1, 1),    # 东, 东南
	Vector2(0, 1),    Vector2(-1, 1),   # 南, 西南
	Vector2(-1, 0),   Vector2(-1, -1)   # 西, 西北
]

## 8个方向偏移（grid坐标），用于方向选择UI
const DIRECTION_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),  Vector2i(1, -1),   # 北, 东北
	Vector2i(1, 0),   Vector2i(1, 1),    # 东, 东南
	Vector2i(0, 1),   Vector2i(-1, 1),   # 南, 西南
	Vector2i(-1, 0),  Vector2i(-1, -1)   # 西, 西北
]


# =============================================================================
# BoardContext — 棋盘数据接口（解耦对 TacticsBoard 的直接依赖）
# =============================================================================

## 棋盘上下文接口：提供物理系统所需的棋盘数据查询能力
## 物理系统不直接依赖 TacticsBoard，而是通过此接口访问数据
class BoardContext:
	extends RefCounted

	## 棋盘引用（实际使用时的 TacticsBoard 实例）
	var _board = null

	## 配置接口：绑定到实际的棋盘实例
	func configure(board) -> void:
		_board = board

	# ---- 地形查询 ----

	## 获取地块高度
	func get_tile_height(col: int, row: int) -> int:
		return _board._get_tile_height(col, row)

	## 检查地块是否有效（在棋盘范围内）
	func is_valid_tile(col: int, row: int) -> bool:
		return _board._is_valid_tile(col, row)

	## 获取该格子的单位（无则返回 null）
	func get_unit_at(col: int, row: int):
		return _board._get_unit_at(col, row)

	# ---- 坐标转换 ----

	## 网格坐标 → 世界坐标（地形顶部 + 空中高度）
	## @param air_height_offset: 空中相对高度偏移（用于跃过障碍物时的空中位置）
	func grid_to_world_top(col: int, row: int, air_height_offset: float = 0.0) -> Vector3:
		return _board._grid_to_world_top(col, row, -1, air_height_offset)

	# ---- 单位数据更新 ----

	## 更新单位在 _unit_data 中的位置记录
	func update_unit_data(unit_id: String, col: int, row: int) -> void:
		if _board._unit_data.has(unit_id):
			_board._unit_data[unit_id]["col"] = col
			_board._unit_data[unit_id]["row"] = row

	# ---- 地形物理数据 ----

	## 获取地形物理属性（质量、速度）
	func get_terrain_physics(col: int, row: int) -> Dictionary:
		var key := Vector2i(col, row)
		var terrain: Dictionary = _board._terrain_data.get(key, {})
		return {
			"mass": terrain.get("mass", 10.0),
			"velocity": terrain.get("velocity", Vector2.ZERO)
		}

	## 设置地形物理属性
	func set_terrain_physics(col: int, row: int, mass_val: float, vel: Vector2) -> void:
		var key := Vector2i(col, row)
		if not _board._terrain_data.has(key):
			_board._terrain_data[key] = {"height": 0, "type": "flat"}
		_board._terrain_data[key]["mass"] = mass_val
		_board._terrain_data[key]["velocity"] = vel

	# ---- TerrainManager集成（新增） ----

	## 获取地形摩擦系数（从TerrainManager查询）
	func get_terrain_friction(col: int, row: int) -> float:
		if _board._terrain_manager != null:
			return _board._terrain_manager.get_terrain_friction(Vector2i(col, row))
		return 1.0  # 默认摩擦系数

	## 获取地形动能抗性（从TerrainManager查询）
	func get_terrain_kinetic_resistance(col: int, row: int) -> float:
		if _board._terrain_manager != null:
			return _board._terrain_manager.get_terrain_kinetic_resistance(Vector2i(col, row))
		return 0.7  # 默认动能抗性

	## 检查地形是否可经过（从TerrainManager查询）
	func is_terrain_passable(col: int, row: int) -> bool:
		if _board._terrain_manager != null:
			return _board._terrain_manager.is_terrain_passable(Vector2i(col, row))
		return true  # 默认可经过

	## 应用动能伤害到地形（委托给TerrainManager）
	func apply_kinetic_damage_to_terrain(col: int, row: int, impact_velocity: Vector3, impact_mass: float) -> int:
		if _board._terrain_manager != null:
			return _board._terrain_manager.apply_kinetic_damage_to_terrain(
				Vector2i(col, row), impact_velocity, impact_mass
			)
		return 0  # 未集成TerrainManager时返回0


# =============================================================================
# 物理系统主体
# =============================================================================

## 棋盘上下文引用
var _ctx: BoardContext

## 日志标签（用于调试输出）
var _log_tag: String = "PhysicsSystem"


func _init(ctx: BoardContext) -> void:
	_ctx = ctx


# =============================================================================
# 矢量速度结算 — 回合结束时调用
# =============================================================================

## 结算单位的矢量速度：重力加速度 → 空中高度更新 → 8方向匹配 → 逐格滑动 → 碰撞检测 → 衰减
## 这是每个回合结束时对单个单位执行的完整物理管线
func settle_velocity(unit: TacticsUnit) -> void:
	# ---- 阶段0：检查是否真正在空中 ----
	# 只有下方有空格才算真正的空中状态
	_check_airborne_status(unit)

	# ---- 阶段1：空中高度更新和重力加速度 ----
	# 仅在真正空中时生效（地面单位有法向力抵消重力）
	if unit.physics.is_airborne:
		# 物理正确的顺序：先应用重力加速度，再用新速度更新位置（半隐式欧拉积分）
		# 这确保本回合的重力增量立即体现在位置变化中
		# 1. 应用重力加速度（velocity.y += GRAVITY_CONSTANT）
		unit.physics.apply_gravity_acceleration()
		_log("重力加速度(先于位移): unit=%s velocity.y=%.2f air_height=%.2f" % [
			unit.unit_id, unit.physics.velocity.y, unit.physics.air_height
		])

		# 2. 用更新后的velocity.y更新空中高度
		#    注意：_update_air_height 可能将 is_airborne 设为 false（air_height 归零时）
		_update_air_height(unit)

		# 3. 同步视觉位置到新的 air_height（关键：自由落体单位不滑动，必须在此更新位置）
		#    否则单位视觉上永远停留在原始高度，即使 air_height 已减小
		if unit.physics.is_airborne:
			unit.position = _ctx.grid_to_world_top(unit.grid_pos.x, unit.grid_pos.y, unit.physics.air_height)
		else:
			# _update_air_height 已归零落地，落回地面
			unit.position = _ctx.grid_to_world_top(unit.grid_pos.x, unit.grid_pos.y)

	var mag: float = unit.physics.velocity.length()
	if mag < 0.01:
		# 没有速度，检查落地状态
		_check_landing(unit)
		return

	# ---- 阶段2：方向匹配 ----
	# 自由落体中的单位（fall_height > 0）的 velocity.y 由重力产生，只影响 air_height，
	# 不应参与水平网格滑动。排除 y 分量后再做方向匹配。
	var slide_vel: Vector2 = unit.physics.velocity
	if unit.physics.is_airborne and unit.physics.fall_height > 0.0:
		slide_vel.y = 0.0

	if slide_vel.length() < 0.01:
		# 无有效水平速度，检查落地状态
		_check_landing(unit)
		return

	var v_dir: Vector2 = slide_vel.normalized()
	var best_dir := _find_best_slide_direction(v_dir)

	# ---- 阶段3：滑动距离计算 ----
	var tile_count: int = floori(slide_vel.length())
	if tile_count <= 0:
		# 幅度太小（< 1格），不滑动，直接衰减
		_apply_velocity_decay(unit, v_dir, slide_vel.length())
		_check_landing(unit)
		return

	_log("矢量速度结算: unit=%s 幅度=%.2f 滑动=%d 方向=%s 空中=%s velocity=(%.2f, %.2f) air_height=%.2f" % [
		unit.unit_id, slide_vel.length(), tile_count, best_dir, unit.physics.is_airborne,
		unit.physics.velocity.x, unit.physics.velocity.y, unit.physics.air_height
	])

	# ---- 阶段4：逐格滑动 ----

	for i in range(tile_count):
		var next_pos := unit.grid_pos + Vector2i(int(best_dir.x), int(best_dir.y))

		# 4a. 边界检查 → 碰撞（水平方向）
		if not _ctx.is_valid_tile(next_pos.x, next_pos.y):
			# 撞墙：检查是否可以跃过（边界外视为高度=-∞）
			# 无法跃过边界，传递动量，清除碰撞方向速度
			_handle_horizontal_collision(unit, best_dir, next_pos, "terrain", 0)
			return

		# 4b. 单位碰撞 → 检查是否可穿过（可通过地形）或跃过
		var blocker: TacticsUnit = _ctx.get_unit_at(next_pos.x, next_pos.y)
		if blocker != null and blocker != unit:
			# 可通过地形：无障碍穿过，单位不构成阻挡
			if _ctx.is_terrain_passable(next_pos.x, next_pos.y):
				_log("穿过可通过地形(有单位): unit=%s pos=(%d,%d)" % [
					unit.unit_id, next_pos.x, next_pos.y
				])
				# 不碰撞，继续移动到下一格
			else:
				# 获取障碍物高度（单位所在格子的高度）
				var blocker_height := _ctx.get_tile_height(next_pos.x, next_pos.y)
				var current_ground_height := _ctx.get_tile_height(unit.grid_pos.x, unit.grid_pos.y)

				# 检查是否可以跃过障碍物单位
				if unit.physics.can_jump_over(blocker_height, current_ground_height):
					_log("跃过障碍物单位: unit=%s 实际高度=%.2f 障碍物高度=%d" % [
						unit.unit_id, unit.physics.get_actual_height(current_ground_height), blocker_height
					])
					# 允许跃过，继续移动
				else:
					# 无法跃过，撞单位：传递动量，清除碰撞方向速度
					_handle_horizontal_collision(unit, best_dir, next_pos, "unit", 0, blocker)
					return

		# 4c. 高度差碰撞（地形）
		var current_height := _ctx.get_tile_height(unit.grid_pos.x, unit.grid_pos.y)
		var next_height := _ctx.get_tile_height(next_pos.x, next_pos.y)
		var height_diff := next_height - current_height

		if height_diff > 0:
			# 上坡/障碍物：检查是否可以跃过
			if unit.physics.can_jump_over(next_height, current_height):
				_log("跃过障碍物地形: unit=%s 实际高度=%.2f 障碍物高度=%d" % [
					unit.unit_id, unit.physics.get_actual_height(current_height), next_height
				])
				# 允许跃过，继续移动（不碰撞）
			else:
				# 无法跃过，碰撞伤害 + 传递动量 + 清除碰撞方向速度
				_log("碰撞(上坡): unit=%s diff=%d" % [unit.unit_id, height_diff])
				_handle_horizontal_collision(unit, best_dir, next_pos, "terrain", 0)
				return

		if height_diff < 0:
			# 下坡/坠落：移动到低处格子，进入自由落体状态（分多回合完成）
			# 之前的行为是瞬间落地+伤害，现在改为：先进入空中，air_height 表示离地高度，
			# 后续回合通过重力 + _update_air_height 逐步下降，真正落地时才结算伤害
			var drop := absi(height_diff)
			unit.set_grid_pos(next_pos.x, next_pos.y)
			unit.physics.air_height = float(drop)
			unit.physics.fall_height = float(drop)
			unit.physics.is_airborne = true
			unit.position = _ctx.grid_to_world_top(next_pos.x, next_pos.y, float(drop))
			_ctx.update_unit_data(unit.unit_id, next_pos.x, next_pos.y)
			_log("坠落: unit=%s 下落=%d格 进入自由落体 air_height=%.2f" % [
				unit.unit_id, drop, unit.physics.air_height
			])
			# 停止滑动：已经滑动了 i+1 步，衰减剩余速度后退出
			var steps_taken: int = i + 1
			var remaining_mag: float = maxf(0.0, mag - float(steps_taken))
			unit.physics.velocity = v_dir * remaining_mag
			_log("坠落中断滑动: unit=%s 已滑动=%d步 剩余幅度=%.2f" % [unit.unit_id, steps_taken, remaining_mag])
			return

		# 4d. 移动单位到新格子（考虑空中高度）
		unit.set_grid_pos(next_pos.x, next_pos.y)
		# 计算实际视觉位置：地面高度 + air_height
		unit.position = _ctx.grid_to_world_top(next_pos.x, next_pos.y, unit.physics.air_height)
		_ctx.update_unit_data(unit.unit_id, next_pos.x, next_pos.y)

	# ---- 阶段5：滑动完成 ----
	# 检查落地状态并清除垂直速度和空中高度（延迟坠落伤害由 _check_landing 内部处理）
	_check_landing(unit)

	# ---- 阶段6：速度衰减 ----
	_apply_velocity_decay(unit, v_dir, mag)


# =============================================================================
# 方向匹配
# =============================================================================

## 找到与矢量速度最接近的8方向（通过点积比较）
func _find_best_slide_direction(v_dir: Vector2) -> Vector2:
	var best_dir := Vector2.ZERO
	var best_dot: float = -999.0
	for d in SLIDE_DIRECTIONS:
		var dot_val := v_dir.dot(d.normalized())
		if dot_val > best_dot:
			best_dot = dot_val
			best_dir = d
	return best_dir


# =============================================================================
# 落地与空中状态管理（支持抛物线跃过障碍物）
# =============================================================================

## 更新空中相对高度（实现抛物线运动的上升和下降）
## 仅在空中时调用，处理velocity.y对air_height的影响
func _update_air_height(unit: TacticsUnit) -> void:
	# velocity.y < 0：上升阶段（向上跃起）
	# velocity.y > 0：下降阶段（重力下落）
	# air_height变化 = -velocity.y（负号：向上为正，向下为负）

	var height_change: float = -unit.physics.velocity.y
	unit.physics.air_height += height_change

	# 空中高度不能为负（不能钻入地下）
	if unit.physics.air_height < 0.0:
		unit.physics.air_height = 0.0
		# 如果空中高度降为0且velocity.y > 0（下降），立即落地
		if unit.physics.velocity.y > 0:
			_log("空中高度归零（下降阶段）: unit=%s 强制落地" % unit.unit_id)
			# 如果有待结算的坠落高度，先计算伤害
			if unit.physics.fall_height > 0.0:
				_apply_deferred_fall_damage(unit)
			unit.physics.is_airborne = false
			unit.physics.velocity.y = 0.0

	_log("空中高度更新: unit=%s height_change=%.2f air_height=%.2f velocity.y=%.2f" % [
		unit.unit_id, height_change, unit.physics.air_height, unit.physics.velocity.y
	])


## 检查单位是否真正在空中
## 判断依据：air_height > 0 表示单位确实离地
## 修复：不再检查相邻格子的高度差来判断悬空。
##   单位站在自己的格子上即有地面支撑（位置由 _grid_to_world_top 正确计算）。
##   站在高柱上的单位不应因相邻格子较低而被误判为"悬空"。
func _check_airborne_status(unit: TacticsUnit) -> void:
	# air_height > 0：单位确实离地（被击飞/跃起/坠落途中）
	if unit.physics.air_height > 0.0:
		unit.physics.is_airborne = true
		_log("空中状态检测: unit=%s air_height=%.2f 在空中=true" % [
			unit.unit_id, unit.physics.air_height
		])
		return

	# air_height=0：单位站在当前格子上，有地面支撑
	# 如果之前标记为空中（如坠落途中 air_height 刚好归零），清除空中状态
	if unit.physics.is_airborne:
		_log("空中状态检测: unit=%s air_height=0 已落地（清除空中标记）" % unit.unit_id)
		unit.physics.velocity.y = 0.0
		unit.physics.is_airborne = false


## 检查落地状态：如果单位在地面上，清除垂直速度和空中标记
func _check_landing(unit: TacticsUnit) -> void:
	if not unit.physics.is_airborne:
		return

	# 检查空中高度是否降为0（自由落体落地）
	if unit.physics.air_height <= 0.0:
		unit.physics.air_height = 0.0
		# 如果有待结算的坠落高度，先计算坠落伤害再清除状态
		if unit.physics.fall_height > 0.0:
			_apply_deferred_fall_damage(unit)
		unit.physics.velocity.y = 0.0
		unit.physics.is_airborne = false
		_log("落地（抛物线）: unit=%s air_height=0 清除垂直速度 velocity.y=0" % unit.unit_id)
		return

	# 自由落体中的单位（fall_height > 0）：只能通过 air_height 归零落地
	# 不检查下方格子支撑，因为它们已经站在目标格子上，只是还在空中高度
	if unit.physics.fall_height > 0.0:
		_log("仍在自由落体中: unit=%s air_height=%.2f velocity.y=%.2f" % [
			unit.unit_id, unit.physics.air_height, unit.physics.velocity.y
		])
		return

	# 检查当前是否有地面支撑（跃过障碍物时落到高处）
	var current_height := _ctx.get_tile_height(unit.grid_pos.x, unit.grid_pos.y)
	var below_pos := Vector2i(unit.grid_pos.x, unit.grid_pos.y + 1)
	var below_height := current_height

	if _ctx.is_valid_tile(below_pos.x, below_pos.y):
		below_height = _ctx.get_tile_height(below_pos.x, below_pos.y)

	# 如果当前高度 <= 下方高度，说明已落地
	if current_height <= below_height:
		# 落地：如果有待结算的坠落高度，先计算伤害
		if unit.physics.fall_height > 0.0:
			_apply_deferred_fall_damage(unit)
		unit.physics.velocity.y = 0.0
		unit.physics.air_height = 0.0
		unit.physics.is_airborne = false
		_log("落地（下坡）: unit=%s 清除垂直速度和空中高度 velocity.y=0 air_height=0" % unit.unit_id)
	else:
		_log("仍在空中: unit=%s 当前高度=%d 下方高度=%d air_height=%.2f" % [
			unit.unit_id, current_height, below_height, unit.physics.air_height
		])


## 结算延迟的坠落伤害
## 当 unit.physics.fall_height > 0 且 air_height 归零时调用
## 使用动能公式：KE = m * g * h = m * h（g=1），再通过 collision_damage 转换为伤害
func _apply_deferred_fall_damage(unit: TacticsUnit) -> void:
	var h: float = unit.physics.fall_height
	var ke: float = unit.physics.mass * h
	var damage: int = PhysicsBody.collision_damage(ke)
	if damage > 0:
		unit.take_damage(damage)
		_log("坠落碰撞（延迟结算）: unit=%s 下落高度=%.0f 质量=%.1f 动能=%.2f 伤害=%d" % [
			unit.unit_id, h, unit.physics.mass, ke, damage
		])
	unit.physics.fall_height = 0.0


## 处理水平方向碰撞（撞墙/撞单位/撞上坡）
## 流程：先传递动量 → 计算碰撞伤害 → 清除碰撞方向速度
## @param unit: 碰撞单位
## @param collision_dir: 碰撞方向（8方向向量）
## @param hit_pos: 碰撞位置（格子坐标）
## @param collision_type: "unit"或"terrain"
## @param fall_height: 累计下落高度
## @param blocker: 如果是单位碰撞，被碰撞的单位（可选）
func _handle_horizontal_collision(
	unit: TacticsUnit,
	collision_dir: Vector2,
	hit_pos: Vector2i,
	collision_type: String,
	fall_height: int,
	blocker: TacticsUnit = null
) -> void:
	# 先结算坠落伤害（如果有）
	_handle_fall_collision(unit, fall_height)

	# 在清除速度前，保存碰撞方向的速度分量，用于计算动量传递
	var collision_vel_component := unit.physics.velocity.dot(collision_dir)
	var collision_vel := collision_vel_component * collision_dir

	# 计算碰撞伤害和动量传递
	if collision_type == "unit" and blocker != null:
		_resolve_unit_collision_with_momentum(unit, blocker, collision_vel)
	elif collision_type == "terrain":
		_resolve_terrain_collision_with_momentum(unit, hit_pos, collision_vel)

	# 清除碰撞方向的速度分量
	if collision_vel_component > 0:
		unit.physics.velocity = unit.physics.velocity - collision_vel_component * collision_dir
		_log("碰撞清除速度分量: unit=%s 碰撞方向=%s 清除分量=%.2f 剩余速度=(%.2f, %.2f)" % [
			unit.unit_id, collision_dir, collision_vel_component,
			unit.physics.velocity.x, unit.physics.velocity.y
		])

	# 检查落地状态
	_check_landing(unit)


## 处理坠落碰撞伤害（仅使用垂直方向动能）
func _handle_fall_collision(unit: TacticsUnit, fall_height: int) -> void:
	if fall_height <= 0:
		return
	var vert_ke: float = unit.physics.vertical_kinetic_energy()
	var damage: int = PhysicsBody.collision_damage(vert_ke)
	if damage > 0:
		unit.take_damage(damage)
		_log("坠落碰撞: unit=%s 下落高度=%d 垂直KE=%.2f 伤害=%d" % [
			unit.unit_id, fall_height, vert_ke, damage
		])


# =============================================================================
# 速度衰减
# =============================================================================

## 速度衰减：根据摩擦系数和空中状态减少速度幅度
## - 空中：无摩擦衰减，仅减去已滑动的格数
## - 地面：摩擦衰减 = gravity * tile_friction（每格额外消耗）
func _apply_velocity_decay(unit: TacticsUnit, v_dir: Vector2, mag: float) -> void:
	if unit.physics.is_airborne:
		# 空中无摩擦，仅减去已滑动的整数部分
		var tile_count: int = floori(mag)
		mag = maxf(0.0, mag - float(tile_count))
		# 自由落体单位（fall_height > 0）的 velocity.y 由重力管理，不应被水平衰减清零
		var saved_vy: float = unit.physics.velocity.y
		unit.physics.velocity = v_dir * mag
		if unit.physics.fall_height > 0.0:
			unit.physics.velocity.y = saved_vy
	else:
		# 地面：摩擦衰减 = 已滑动格数 + 重力系数 * 地块摩擦
		var friction: float = get_tile_friction(unit.grid_pos.x, unit.grid_pos.y)
		var tile_count: int = floori(mag)
		mag = maxf(0.0, mag - float(tile_count) - unit.physics.gravity * friction)
		unit.physics.velocity = v_dir * mag

	_log("速度衰减后: unit=%s 剩余幅度=%.2f 空中=%s" % [
		unit.unit_id, mag, unit.physics.is_airborne
	])


# =============================================================================
# 地块摩擦
# =============================================================================

## 获取地块摩擦系数
## 当前所有地块统一为 1.0，后续可通过 terrain_data 扩展（如冰面 0.3、沼泽 1.5）
func get_tile_friction(col: int, row: int) -> float:
	return 1.0


# =============================================================================
# 碰撞系统（支持动量传递）
# =============================================================================

## 单位与单位的碰撞分辨率（带动量传递）
## 流程：计算伤害 → 传递50%碰撞方向动量给被碰撞单位 → 合力
func _resolve_unit_collision_with_momentum(
	unit_a: TacticsUnit,
	unit_b: TacticsUnit,
	collision_vel: Vector2
) -> void:
	# 计算双方总动能（用于伤害）
	var ke_a: float = unit_a.physics.kinetic_energy()
	var ke_b: float = unit_b.physics.kinetic_energy()
	var total_ke: float = ke_a + ke_b
	var damage: int = PhysicsBody.collision_damage(total_ke)

	_log("碰撞(unit↔unit): %s → %s KE=%.2f 伤害各=%d 碰撞速度=(%.2f, %.2f)" % [
		unit_a.unit_id, unit_b.unit_id, total_ke, damage,
		collision_vel.x, collision_vel.y
	])

	# 双方受到动能伤害
	if damage > 0:
		unit_a.take_damage(damage)
		unit_b.take_damage(damage)

	# 动量传递：碰撞方向的50%动量传递给被碰撞单位
	# 碰撞者动量 = mass_a × collision_vel
	var momentum_a: Vector2 = unit_a.physics.mass * collision_vel

	# 传递的动量 = 50% × 碰撞者动量
	var transferred_momentum: Vector2 = momentum_a * 0.5

	# 被碰撞者获得的速度增量 = 传递动量 / mass_b
	var velocity_gain: Vector2 = transferred_momentum / unit_b.physics.mass

	# 四舍五入速度增量（每个分量单独四舍五入）
	var rounded_vel_gain := Vector2(
		roundf(velocity_gain.x),
		roundf(velocity_gain.y)
	)

	# 合力：被碰撞者新速度 = 原速度 + 速度增量
	var new_vel_b: Vector2 = unit_b.physics.velocity + rounded_vel_gain
	unit_b.physics.velocity = new_vel_b

	_log("动量传递(unit→unit): %s → %s 传递动量=(%.2f, %.2f) 速度增量=(%.2f, %.2f) 新速度=(%.2f, %.2f)" % [
		unit_a.unit_id, unit_b.unit_id,
		transferred_momentum.x, transferred_momentum.y,
		rounded_vel_gain.x, rounded_vel_gain.y,
		new_vel_b.x, new_vel_b.y
	])


## 单位与地形的碰撞分辨率（带动量传递）
## 流程：计算伤害 → 传递50%碰撞方向动量给地形 → 合力
func _resolve_terrain_collision_with_momentum(
	unit: TacticsUnit,
	hit_pos: Vector2i,
	collision_vel: Vector2
) -> void:
	# 获取地形物理属性
	var terrain_phys: Dictionary = _ctx.get_terrain_physics(hit_pos.x, hit_pos.y)
	var terrain_mass: float = terrain_phys.get("mass", 10.0)
	var terrain_vel: Vector2 = terrain_phys.get("velocity", Vector2.ZERO)

	# 计算碰撞总动能（用于伤害）
	var ke_unit: float = unit.physics.kinetic_energy()
	var ke_terrain: float = 0.5 * terrain_mass * terrain_vel.length_squared()
	var total_ke: float = ke_unit + ke_terrain
	var damage: int = PhysicsBody.collision_damage(total_ke)

	_log("碰撞(unit↔terrain): %s → (%d,%d) KE=%.2f 伤害=%d 碰撞速度=(%.2f, %.2f)" % [
		unit.unit_id, hit_pos.x, hit_pos.y, total_ke, damage,
		collision_vel.x, collision_vel.y
	])

	# 单位受到伤害
	if damage > 0:
		unit.take_damage(damage)

	# 动量传递：碰撞方向的50%动量传递给地形
	# 碰撞者动量 = mass_unit × collision_vel
	var momentum_unit: Vector2 = unit.physics.mass * collision_vel

	# 传递的动量 = 50% × 碰撞者动量
	var transferred_momentum: Vector2 = momentum_unit * 0.5

	# 地形获得的速度增量 = 传递动量 / terrain_mass
	var velocity_gain: Vector2 = transferred_momentum / terrain_mass

	# 四舍五入速度增量（每个分量单独四舍五入）
	var rounded_vel_gain := Vector2(
		roundf(velocity_gain.x),
		roundf(velocity_gain.y)
	)

	# 合力：地形新速度 = 原速度 + 速度增量
	var new_terrain_vel: Vector2 = terrain_vel + rounded_vel_gain

	# 更新地形速度（通过BoardContext）
	_ctx.set_terrain_physics(hit_pos.x, hit_pos.y, terrain_mass, new_terrain_vel)

	_log("动量传递(unit→terrain): %s → (%d,%d) 传递动量=(%.2f, %.2f) 速度增量=(%.2f, %.2f) 新速度=(%.2f, %.2f)" % [
		unit.unit_id, hit_pos.x, hit_pos.y,
		transferred_momentum.x, transferred_momentum.y,
		rounded_vel_gain.x, rounded_vel_gain.y,
		new_terrain_vel.x, new_terrain_vel.y
	])


## （旧版本，已废弃）单位与单位的碰撞分辨率
## 双方受到总动能伤害，碰撞后速度归零（完全非弹性碰撞模型）
func _resolve_unit_collision(unit_a: TacticsUnit, unit_b: TacticsUnit, _mag_a: float) -> void:
	# 计算双方总动能
	var ke_a: float = unit_a.physics.kinetic_energy()
	var ke_b: float = unit_b.physics.kinetic_energy()
	var total_ke: float = ke_a + ke_b
	var damage: int = PhysicsBody.collision_damage(total_ke)

	_log("碰撞(unit↔unit): %s → %s KE=%.2f 伤害各=%d" % [
		unit_a.unit_id, unit_b.unit_id, total_ke, damage
	])

	# 双方受到动能伤害
	if damage > 0:
		unit_a.take_damage(damage)
		unit_b.take_damage(damage)

	# 碰撞后双方速度归零（完全非弹性碰撞）
	unit_a.physics.stop()
	unit_b.physics.stop()


## （旧版本，已废弃）单位与地形的碰撞分辨率
## 单位受到总动能伤害（地形质量远大于单位，视为固定墙）
func _resolve_terrain_collision(unit: TacticsUnit, hit_pos: Vector2i, _hit_mag: float) -> void:
	var terrain_phys: Dictionary = _ctx.get_terrain_physics(hit_pos.x, hit_pos.y)
	var terrain_mass: float = terrain_phys.get("mass", 10.0)
	var terrain_vel: Vector2 = terrain_phys.get("velocity", Vector2.ZERO)

	# 计算碰撞总动能
	var ke_unit: float = unit.physics.kinetic_energy()
	var ke_terrain: float = 0.5 * terrain_mass * terrain_vel.length_squared()
	var total_ke: float = ke_unit + ke_terrain
	var damage: int = PhysicsBody.collision_damage(total_ke)

	_log("碰撞(unit↔terrain): %s → (%d,%d) KE=%.2f 伤害=%d" % [
		unit.unit_id, hit_pos.x, hit_pos.y, total_ke, damage
	])

	# 单位受到伤害
	if damage > 0:
		unit.take_damage(damage)

	# 单位速度归零
	unit.physics.stop()


# =============================================================================
# 技能推击 / 冲量方向处理
# =============================================================================

## 应用技能推击方向（由方向选择UI触发）
## 支持两种效果类型：
##   - add_velocity：直接加固定速度（旧版）
##   - apply_momentum：通过冲量施加（新版，v = impulse / mass）
##
## @param target: 被推击的目标单位
## @param center: 目标当前所在格子
## @param col: 玩家选择的方向格子 col
## @param row: 玩家选择的方向格子 row
## @param skill_data: 技能数据（包含 effects 列表）
func apply_velocity_direction(target: TacticsUnit, center: Vector2i, col: int, row: int, skill_data: Dictionary) -> void:
	# 计算方向向量并归一化到8方向
	var dir := Vector2(col - center.x, row - center.y)
	var velocity_dir := _snap_to_8dir(dir)

	for effect in skill_data.get("effects", []):
		var effect_type: String = effect.get("type", "")

		match effect_type:
			"add_velocity":
				# 旧版：直接加固定速度量
				var amount: float = effect.get("amount", 2.0)
				target.physics.velocity += velocity_dir * amount
				_log("推击(add_velocity): 目标=%s 方向=%s 数量=%.1f 新速度=%s" % [
					target.unit_id, velocity_dir, amount, target.physics.velocity
				])

			"apply_momentum":
				# 新版：冲量 = 质量 × 速度增量，速度增量 = 冲量 / 质量
				# 质量越大的单位获得的速度越小（动量守恒）
				var impulse: float = effect.get("impulse", 6.0)
				target.physics.apply_impulse(velocity_dir * impulse)
				_log("推击(apply_momentum): 目标=%s 方向=%s 冲量=%.1f 质量=%.1f 新速度=%s" % [
					target.unit_id, velocity_dir, impulse, target.physics.mass, target.physics.velocity
				])


## 将任意方向向量 snaps 到最近的8方向之一
func _snap_to_8dir(dir: Vector2) -> Vector2:
	var best_dir := Vector2.ZERO
	var best_dist: float = 999.0
	for d in DIRECTION_OFFSETS:
		var dv := Vector2(d.x, d.y)
		var dist := dir.distance_to(dv)
		if dist < best_dist:
			best_dist = dist
			best_dir = dv
	return best_dir.normalized()


# =============================================================================
# 工具方法
# =============================================================================

## 内部日志输出（可通过覆盖 _log_tag 定制前缀）
func _log(msg: String) -> void:
	print("[%s] %s" % [_log_tag, msg])