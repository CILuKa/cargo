class_name TacticsUnit
extends Node3D

## 战棋角色基础类 — 所有战棋单位继承此场景
##
## 属性说明：
##   - hp / max_hp: 生命值，决定角色是否死亡
##   - mental_speed: 思维速度，决定行动轮次先后（标准值 10）
##   - move_speed: 速度，决定单次最大移动距离
##   - skill_ids: 技能 ID 列表，引用 SkillSystem 中的技能数据

# =============================================================================
# 信号
# =============================================================================

signal died(unit: TacticsUnit)
signal hp_changed(unit: TacticsUnit, old_hp: int, new_hp: int)
signal moved(from_pos: Vector2i, to_pos: Vector2i)

# =============================================================================
# 基础属性
# =============================================================================

## 单位唯一标识符
@export var unit_id: String = ""

## 显示名称
@export var unit_name: String = ""

## 所属队伍（"player", "enemy", "neutral" 或自定义）
@export var team: String = "player"

## 最大生命值
@export var max_hp: int = 100

## 当前生命值
var current_hp: int = 100

## 思维速度 — 决定行动顺序（标准值 10）
@export var mental_speed: int = 10

## 移动速度 — 基础速度属性，实际每回合移动点数 = speed / (gravity * friction)
@export var move_speed: int = 3

## 计算本回合实际移动点数（空中时禁止移动，返回 0）
func get_move_points(tile_friction: float) -> int:
	if physics.is_airborne:
		return 0
	var denom: float = physics.gravity * tile_friction
	if denom <= 0.0:
		return 0
	return maxi(0, int(floori(float(move_speed) / denom)))

## 技能 ID 列表
@export var skill_ids: Array[String] = []

# =============================================================================
# 物理系统
# =============================================================================

## 物理体组件（质量、矢量速度、动能计算）
var physics: PhysicsBody = PhysicsBody.new()

## 本回合剩余移动点数（每移动1格消耗1点，由 move_speed 初始化）
var remaining_move_points: int = 0

## 本回合是否已使用技能/攻击（每回合只能用一个）
var has_acted: bool = false

# =============================================================================
# 战斗属性（用于技能公式计算）
# =============================================================================

## 攻击力
@export var atk: int = 10

## 防御力
@export var def: int = 5

## 魔法攻击力
@export var matk: int = 8

## 魔法防御力
@export var mdef: int = 4

# =============================================================================
# 行动计量条（内部使用，由 TurnManager 管理）
# =============================================================================

## 行动计量条累计值
var action_gauge: float = 0.0

## 当前回合剩余行动次数
var actions_this_round: int = 0

# =============================================================================
# 网格位置
# =============================================================================

## 当前所在格子坐标
var grid_pos: Vector2i = Vector2i.ZERO

# =============================================================================
# 运行时引用
# =============================================================================

## SkillSystem 引用（由 TacticsBoard 设置）
var skill_system: Node = null

## TurnManager 引用（由 TacticsBoard 设置）
var turn_manager: Node = null

# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	current_hp = max_hp


# =============================================================================
# 生命值
# =============================================================================

## 受到伤害
func take_damage(amount: int) -> int:
	# 行为脚本：受伤前（可修改伤害量）
	var behavior := _get_behavior()
	if behavior:
		amount = behavior._on_before_damage(amount)
		if amount <= 0:
			return 0

	var old_hp: int = current_hp
	current_hp = maxi(0, current_hp - amount)
	var actual_damage: int = old_hp - current_hp
	hp_changed.emit(self, old_hp, current_hp)

	# 行为脚本：受伤后
	if behavior:
		behavior._on_after_damage(amount, actual_damage)

	if current_hp <= 0:
		_on_death()
	return actual_damage


## 恢复生命值
func heal(amount: int) -> int:
	var old_hp: int = current_hp
	current_hp = mini(max_hp, current_hp + amount)
	var actual_heal: int = current_hp - old_hp
	hp_changed.emit(self, old_hp, current_hp)
	# 行为脚本：被治疗
	var behavior := _get_behavior()
	if behavior:
		behavior._on_heal(amount)
	return actual_heal


## 是否死亡
func is_dead() -> bool:
	return current_hp <= 0


## 死亡处理（可被子类覆盖）
func _on_death() -> void:
	# 行为脚本：死亡时
	var behavior := _get_behavior()
	if behavior:
		behavior._on_death()
	died.emit(self)


# =============================================================================
# 行为脚本
# =============================================================================

## 获取挂载的行为脚本（无则返回 null）
func _get_behavior() -> UnitBehavior:
	return get_node_or_null("Behavior") as UnitBehavior


# =============================================================================
# 移动
# =============================================================================

## 设置网格位置（不带动画）
func set_grid_pos(col: int, row: int) -> void:
	var old_pos: Vector2i = grid_pos
	grid_pos = Vector2i(col, row)
	moved.emit(old_pos, grid_pos)


# =============================================================================
# 技能
# =============================================================================

## 获取当前可用的技能列表
func get_skills() -> Array:
	if skill_system == null or not skill_system.has_method("get_skill"):
		return []
	var skills: Array = []
	for sid in skill_ids:
		var skill: Dictionary = skill_system.get_skill(sid)
		if not skill.is_empty():
			skills.append(skill)
	return skills


## 获取技能数据
func get_skill(skill_id: String) -> Dictionary:
	if skill_system == null or not skill_system.has_method("get_skill"):
		return {}
	return skill_system.get_skill(skill_id)


# =============================================================================
# 属性获取（用于技能公式中的变量替换）
# =============================================================================

## 获取可用于公式计算的所有属性
func get_formula_vars() -> Dictionary:
	return {
		"atk": atk,
		"def": def,
		"matk": matk,
		"mdef": mdef,
		"hp": current_hp,
		"max_hp": max_hp,
		"mental_speed": mental_speed,
		"move_speed": move_speed,
		"velocity": physics.velocity.length(),
	}
