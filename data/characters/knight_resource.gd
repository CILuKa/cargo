class_name KnightResource
extends UnitResource

## 骑士角色资源 — 差异化属性：盾牌防御加成、反击概率

@export var shield_defense_bonus: int = 0
@export var counter_attack_chance: float = 0.0

func _on_unit_created(unit: TacticsUnit) -> void:
	# 骑士：盾牌加成应用到防御力
	if shield_defense_bonus > 0:
		unit.def += shield_defense_bonus
	# 反击标记（由战斗系统读取）
	if counter_attack_chance > 0.0:
		unit.set_meta("counter_attack_chance", counter_attack_chance)

func get_type_description() -> String:
	var desc := "骑士"
	if shield_defense_bonus > 0:
		desc += " | 盾牌防御+%d" % shield_defense_bonus
	if counter_attack_chance > 0.0:
		desc += " | 反击%.0f%%" % (counter_attack_chance * 100.0)
	return desc

func _merge_extra_dict(d: Dictionary) -> void:
	d["shield_defense_bonus"] = shield_defense_bonus
	d["counter_attack_chance"] = counter_attack_chance
