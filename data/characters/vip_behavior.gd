class_name VipBehavior
extends UnitBehavior

## VIP保护目标行为 — 自动回避 + 受伤通知

var _auto_dodge_chance: float = 0.0


func _on_created() -> void:
	_auto_dodge_chance = unit.get_meta("auto_dodge_chance", 0.0) if unit.has_meta("auto_dodge_chance") else 0.0


func _on_before_damage(amount: int) -> int:
	# 自动回避：有概率完全免疫伤害
	if _auto_dodge_chance > 0.0 and randf() < _auto_dodge_chance:
		print("[VipBehavior] %s 自动回避！" % unit.unit_id)
		return 0
	return amount


func _on_after_damage(_amount: int, _actual: int) -> void:
	# 受伤后可触发剧情通知（如保护目标受伤提示）
	if _actual > 0:
		print("[VipBehavior] 保护目标 %s 受到 %d 伤害！剩余 HP: %d" % [unit.unit_id, _actual, unit.current_hp])
