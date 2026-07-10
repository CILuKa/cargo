class_name SlimeBehavior
extends UnitBehavior

## 史莱姆行为 — 死亡分裂 + 元素吸收
## 差异化参数从所属 UnitResource (SlimeResource) 读取

var _split_on_death: bool = false
var _split_count: int = 2
var _absorbs_elements: Array[String] = []


func _on_created() -> void:
	# 从 unit 的 meta 或 Resource 读取差异化参数
	_split_on_death = unit.get_meta("split_on_death", false)
	_split_count = unit.get_meta("split_count", 2)
	var absorbs = unit.get_meta("absorbs_elements", [])
	_absorbs_elements = Array(absorbs, TYPE_STRING, &"", null) if absorbs is Array else []


func _on_before_damage(amount: int) -> int:
	# 元素吸收：如果伤害元素在吸收列表中，免疫伤害
	# 注意：当前 take_damage 不传元素，未来扩展时在此处理
	return amount


func _on_death() -> void:
	if not _split_on_death:
		return
	# 死亡分裂逻辑：向 TacticsBoard 请求生成子史莱姆
	print("[SlimeBehavior] %s 死亡分裂！生成 %d 个子体" % [unit.unit_id, _split_count])
	# 实际分裂由 TacticsBoard 处理（需要知道地图边界和空位）
	# 通过信号或方法调用通知 board
	if unit.has_meta("board_ref"):
		var board = unit.get_meta("board_ref")
		if board and board.has_method("spawn_split_units"):
			board.spawn_split_units(unit, _split_count)
