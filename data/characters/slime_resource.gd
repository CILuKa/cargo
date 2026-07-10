class_name SlimeResource
extends UnitResource

## 史莱姆角色资源 — 差异化属性：死亡分裂、元素吸收

@export var split_on_death: bool = false
@export var split_count: int = 2
@export var absorbs_elements: Array[String] = []

func _on_unit_created(unit: TacticsUnit) -> void:
	# 史莱姆：死亡分裂标记
	if split_on_death:
		unit.set_meta("split_on_death", true)
		unit.set_meta("split_count", split_count)
	# 元素吸收标记
	if not absorbs_elements.is_empty():
		unit.set_meta("absorbs_elements", absorbs_elements)

func get_type_description() -> String:
	var desc := "史莱姆"
	if split_on_death:
		desc += " | 死亡分裂×%d" % split_count
	if not absorbs_elements.is_empty():
		desc += " | 吸收: " + ", ".join(absorbs_elements)
	return desc

func _merge_extra_dict(d: Dictionary) -> void:
	d["split_on_death"] = split_on_death
	d["split_count"] = split_count
	d["absorbs_elements"] = absorbs_elements
