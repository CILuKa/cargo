class_name UnitBehavior
extends Node

## 单位行为脚本基类 — 挂载为 TacticsUnit 子节点
## 每个角色类型一个独立行为脚本，通过 UnitResource.behavior_script 关联
##
## 生命周期钩子（覆盖需要的即可，默认空实现）：
##   _on_created()      — 单位创建后（属性已赋值）
##   _on_turn_start()   — 该单位回合开始
##   _on_turn_end()     — 该单位回合结束
##   _on_before_damage(amount) -> int  — 受伤前，可修改伤害量并返回
##   _on_after_damage(amount, actual)  — 受伤后
##   _on_heal(amount)   — 被治疗
##   _on_death()        — 死亡时
##   _on_skill_used(skill_id, target)  — 使用技能后

## 所属单位引用
var unit: TacticsUnit = null

# =============================================================================
# 初始化
# =============================================================================

## 由 TacticsBoard 调用，传入所属单位
func setup(owner_unit: TacticsUnit) -> void:
	unit = owner_unit
	_on_created()

# =============================================================================
# 生命周期钩子 — 子脚本覆盖需要的即可
# =============================================================================

## 单位创建后（属性已赋值，可做额外初始化）
func _on_created() -> void:
	pass

## 该单位回合开始
func _on_turn_start() -> void:
	pass

## 该单位回合结束
func _on_turn_end() -> void:
	pass

## 受伤前 → 返回实际伤害量（可增减，返回 0 则完全免疫）
func _on_before_damage(amount: int) -> int:
	return amount

## 受伤后
func _on_after_damage(_amount: int, _actual: int) -> void:
	pass

## 被治疗
func _on_heal(_amount: int) -> void:
	pass

## 死亡时
func _on_death() -> void:
	pass

## 使用技能后
func _on_skill_used(_skill_id: String, _target) -> void:
	pass
