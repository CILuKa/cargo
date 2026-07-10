class_name VipStudentResource
extends UnitResource

## VIP保护目标角色资源 — 差异化属性：保护优先级、自动回避概率

@export var is_protected_target: bool = true
@export var protection_priority: int = 1
@export var auto_dodge_chance: float = 0.0

func _on_unit_created(unit: TacticsUnit) -> void:
	# VIP：保护目标标记（由胜负条件系统读取）
	if is_protected_target:
		unit.set_meta("is_protected_target", true)
		unit.set_meta("protection_priority", protection_priority)
	# 自动回避
	if auto_dodge_chance > 0.0:
		unit.set_meta("auto_dodge_chance", auto_dodge_chance)

func get_type_description() -> String:
	var desc := "保护目标"
	if is_protected_target:
		desc += " | 优先级%d" % protection_priority
	if auto_dodge_chance > 0.0:
		desc += " | 回避%.0f%%" % (auto_dodge_chance * 100.0)
	return desc

func _merge_extra_dict(d: Dictionary) -> void:
	d["is_protected_target"] = is_protected_target
	d["protection_priority"] = protection_priority
	d["auto_dodge_chance"] = auto_dodge_chance
