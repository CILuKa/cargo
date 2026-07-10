class_name KnightBehavior
extends UnitBehavior

## 骑士行为 — 盾牌格挡 + 反击

var _shield_defense_bonus: int = 0
var _counter_attack_chance: float = 0.0


func _on_created() -> void:
	_shield_defense_bonus = unit.get_meta("shield_defense_bonus", 0) if unit.has_meta("shield_defense_bonus") else 0
	_counter_attack_chance = unit.get_meta("counter_attack_chance", 0.0) if unit.has_meta("counter_attack_chance") else 0.0
	# 盾牌加成已在 SlimeResource._on_unit_created 中应用到 unit.def


func _on_after_damage(_amount: int, _actual: int) -> void:
	# 反击：受伤后有概率自动反击攻击者
	if _counter_attack_chance <= 0.0:
		return
	if unit.is_dead():
		return
	if randf() > _counter_attack_chance:
		return

	# 获取攻击者（当前回合行动单位）
	if unit.turn_manager == null:
		return
	var attacker = unit.turn_manager.get_current_unit()
	if attacker == null or attacker == unit or attacker.is_dead():
		return

	# 反击伤害 = 骑士攻击力的一半
	var counter_damage = maxi(1, unit.atk / 2)
	var actual = attacker.take_damage(counter_damage)
	print("[KnightBehavior] %s 反击 %s！造成 %d 伤害" % [unit.unit_id, attacker.unit_id, actual])
