class_name PhysicsBody
extends Resource

## =============================================================================
## 物理体组件 — 可附着于任何对象的物理属性
## =============================================================================
##
## 提供单个物理实体的核心数据与基础计算：
##   - 质量(mass)：决定惯性和碰撞动能，越大越难被推动
##   - 矢量速度(velocity)：grid坐标空间的2D速度，单位：格/回合
##   - 重力系数(gravity)：地面减速系数，影响摩擦衰减和移动消耗
##   - 空中状态(is_airborne)：滞空时无法手动移动，持续下落加速
##
## 动能计算：
##   - 总动能 KE = 0.5 * m * v²
##   - 垂直动能 KE_y = 0.5 * m * v_y²（用于坠落伤害）
##   - 碰撞伤害 = ceil(KE * 0.5)，最小为1
##
## 与 PhysicsSystem 的关系：
##   PhysicsBody 负责单体的数据与基本运算
##   PhysicsSystem 负责世界级物理逻辑（滑动、碰撞、衰减等）
##
## 使用示例：
##   var body = PhysicsBody.new()
##   body.mass = 2.0
##   body.apply_impulse(Vector2(3, 0))  # 速度增加 3/2 = 1.5
##   var ke = body.kinetic_energy()     # 计算当前动能
## =============================================================================


# =============================================================================
# 常量
# =============================================================================

## 重力常数（每回合下落加速度，单位：格/回合²）
## 空中单位每回合 vertical_velocity 增加此值
const GRAVITY_CONSTANT: float = 1.0


# =============================================================================
# 属性
# =============================================================================

## 质量（越大越难被推动，碰撞时动能越大）
## 影响：冲量响应（v = impulse / mass）、动能计算、碰撞伤害
@export var mass: float = 1.0

## 矢量速度（grid 坐标空间，单位：格/回合）
## - x 分量：水平（col 方向）速度
## - y 分量：水平（row 方向）速度
## 滑动时 magnitude 决定滑动格数，方向决定滑动方向
@export var velocity: Vector2 = Vector2.ZERO

## 垂直速度（影响 air_height，单位：格/回合）
## - 正值：下降（重力下落）
## - 负值：上升（被投掷向上）
## 此值影响 air_height 变化：height_change = -vertical_velocity
var vertical_velocity: float = 0.0

## 重力摩擦系数（地面减速系数，默认 1.0）
## 影响：移动消耗（move_points = move_speed / (gravity * friction)）
##      地面摩擦衰减（每回合额外消耗 gravity * friction 格）
@export var gravity: float = 1.0

## 是否处于空中状态
## - true：无法手动移动，每回合受到重力加速度
## - false：正常地面状态，可手动移动，有摩擦衰减
var is_airborne: bool = false

## 空中相对高度（单位在空中的高度偏移，单位：世界坐标高度）
## - 0.0：单位在地面上（实际高度=地面高度）
## - >0.0：单位在空中（实际高度=地面高度+air_height）
## 用于实现跃过障碍物的抛物线运动
var air_height: float = 0.0

## 待结算的坠落高度（格子单位），用于延迟计算坠落伤害
## 当单位从高处坠落时，先进入自由落体（air_height > 0），不立即结算伤害
## 当 air_height 归零（真正落地）时，根据此值计算坠落碰撞伤害
var fall_height: float = 0.0


# =============================================================================
# 动量与冲量
# =============================================================================

## 施加冲量：根据动量定理，velocity 变化 = impulse / mass
## 质量越大的对象获得的速度越小（动量守恒）
##
## 参数：
##   impulse: 冲量向量（grid坐标空间），方向即速度增量方向
##
## 示例：
##   body.mass = 2.0
##   body.apply_impulse(Vector2(6, 0))  # velocity 增加 (3, 0)
func apply_impulse(impulse: Vector2) -> void:
	if mass <= 0.0:
		mass = 1.0  # 防止除零，质量至少为1
	velocity += impulse / mass


# =============================================================================
# 动能计算
# =============================================================================

## 计算总动能：KE = 0.5 * m * v²
## 用于碰撞伤害计算（动能越大，碰撞伤害越高）
func kinetic_energy() -> float:
	return 0.5 * mass * velocity.length_squared()


## 计算垂直方向（下落）动能：KE_y = 0.5 * m * v_y²
## 专门用于坠落碰撞伤害，仅考虑垂直速度分量
## 水平速度不贡献坠落伤害
func vertical_kinetic_energy() -> float:
	return 0.5 * mass * vertical_velocity * vertical_velocity


## 计算两个物理体碰撞时的总动能（静态方法）
## 用于单位↔单位碰撞，总动能 = 双方动能之和
static func collision_kinetic_energy(a: PhysicsBody, b: PhysicsBody) -> float:
	return a.kinetic_energy() + b.kinetic_energy()


## 计算碰撞伤害（静态方法）
## 当前规则：伤害 = ceil(总动能 * 0.5)，最小为1
## 可根据需要调整系数（如改为 0.3 降低碰撞伤害，或引入防御减免）
static func collision_damage(ke: float) -> int:
	return maxi(1, int(ceil(ke * 0.5)))


# =============================================================================
# 重力与状态管理
# =============================================================================

## 施加重力加速度（每回合调用一次）
## a = F/m = (m * g) / m = g，即每回合下落速度增加 GRAVITY_CONSTANT
## 仅在空中时由 PhysicsSystem 调用
## 注意：重力只影响 vertical_velocity（垂直速度），不影响 velocity.y（水平row方向速度）
func apply_gravity_acceleration() -> void:
	vertical_velocity += GRAVITY_CONSTANT


## 重置速度为零，同时清除空中状态
## 用于碰撞后、落地后等需要完全停止的场景
func stop() -> void:
	velocity = Vector2.ZERO
	vertical_velocity = 0.0
	is_airborne = false
	air_height = 0.0
	fall_height = 0.0


## 计算单位的实际高度（地面高度 + 空中相对高度）
## @param ground_height: 当前格子的高度（整数层）
## @return: 单位的实际高度（浮点，考虑空中偏移）
func get_actual_height(ground_height: int) -> float:
	return float(ground_height) + air_height


## 检查是否可以跃过障碍物
## @param obstacle_height: 障碍物高度（整数层）
## @param ground_height: 当前地面高度（整数层）
## @return: true 如果单位在空中且实际高度足够跃过障碍物
func can_jump_over(obstacle_height: int, ground_height: int) -> bool:
	if not is_airborne:
		return false
	var actual_height: float = get_actual_height(ground_height)
	return actual_height >= float(obstacle_height)
