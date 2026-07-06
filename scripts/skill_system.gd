class_name SkillSystem
extends Node

## 技能系统 — 加载技能 JSON、解析公式、执行效果
##
## 技能 JSON 格式：
## {
##   "id": "fireball",
##   "name": "火球术",
##   "description": "对单个敌人造成火焰伤害",
##   "type": "active",              // active | passive | reaction
##   "target_type": "enemy_single",  // self | ally_single | ally_all | enemy_single | enemy_all | tile
##   "range": 3,                     // 施法距离（格子数）
##   "area": "single",               // single | cross | square | line
##   "area_size": 1,                 // 范围大小（cross/square 的半径）
##   "effects": [ ... ],             // 效果列表
##   "cost": {"mp": 15},            // 消耗（可选）
##   "cooldown": 0                   // 冷却回合数（可选）
## }
##
## 效果对象格式：
## {
##   "type": "damage",               // damage | heal | buff | debuff | push | teleport | condition
##   "formula": "atk * 1.5 - def * 0.5",
##   "element": "fire",              // 可选，元素类型
##   "stat": "atk",                  // buff/debuff 时修改的属性
##   "value": 5,                     // buff/debuff 时的固定值
##   "duration": 3,                  // buff/debuff 持续回合数
##   "condition": { ... }            // 条件效果时的条件
## }
##
## 公式变量：
##   atk, def, matk, mdef — 攻防属性
##   hp, max_hp — 当前/最大生命值
##   mental_speed, move_speed — 思维速度/移动速度

# =============================================================================
# 信号
# =============================================================================

signal skill_executed(skill_id: String, caster: TacticsUnit, target: TacticsUnit, result: Dictionary)

# =============================================================================
# 内部存储
# =============================================================================

## 已加载的技能缓存 {skill_id: skill_data}
var _skill_cache: Dictionary = {}


# =============================================================================
# 技能加载
# =============================================================================

## 加载单个技能 JSON 文件
func load_skill(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("SkillSystem: 无法加载技能文件: " + file_path)
		return false

	var json_text = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("SkillSystem: JSON 解析失败: " + json.get_error_message())
		return false

	var data = json.data
	var skill_id: String = data.get("id", "")
	if skill_id.is_empty():
		push_error("SkillSystem: 技能缺少 id 字段")
		return false

	_skill_cache[skill_id] = data
	return true


## 批量加载技能（从目录或列表）
func load_skills(paths: Array[String]) -> void:
	for p in paths:
		load_skill(p)


## 获取技能数据
func get_skill(skill_id: String) -> Dictionary:
	return _skill_cache.get(skill_id, {})


## 获取所有已加载的技能 ID
func get_all_skill_ids() -> Array:
	return _skill_cache.keys()


# =============================================================================
# 技能执行
# =============================================================================

## 执行技能
## @param skill_id: 技能 ID
## @param caster: 施法者
## @param target: 目标（单位或格子坐标）
## @return: 执行结果字典
func execute_skill(skill_id: String, caster: TacticsUnit, target) -> Dictionary:
	var skill_data: Dictionary = _skill_cache.get(skill_id, {})
	if skill_data.is_empty():
		return {"success": false, "error": "技能不存在: " + skill_id}

	var result: Dictionary = {
		"success": true,
		"skill_id": skill_id,
		"skill_name": skill_data.get("name", skill_id),
		"caster": caster,
		"effects": []
	}

	# 获取施法者属性
	var caster_vars: Dictionary = caster.get_formula_vars()

	for effect in skill_data.get("effects", []):
		var effect_result := _execute_effect(effect, caster, target, caster_vars)
		result["effects"].append(effect_result)

	skill_executed.emit(skill_id, caster, target, result)
	return result


# =============================================================================
# 效果执行
# =============================================================================

func _execute_effect(effect: Dictionary, caster: TacticsUnit, target, caster_vars: Dictionary) -> Dictionary:
	var effect_type: String = effect.get("type", "")

	match effect_type:
		"damage":
			return _effect_damage(effect, caster, target, caster_vars)
		"heal":
			return _effect_heal(effect, caster, target, caster_vars)
		"buff":
			return _effect_buff(effect, target)
		"debuff":
			return _effect_debuff(effect, target)
		"push":
			return _effect_push(effect, caster, target)
		"teleport":
			return _effect_teleport(effect, target)
		"condition":
			return _effect_condition(effect, caster, target, caster_vars)
		"add_velocity":
			return _effect_add_velocity(effect, target)
		"apply_momentum":
			return _effect_apply_momentum(effect, target)
		_:
			return {"type": effect_type, "success": false, "error": "未知效果类型"}


## 伤害效果
func _effect_damage(effect: Dictionary, caster: TacticsUnit, target: TacticsUnit, caster_vars: Dictionary) -> Dictionary:
	if not target is TacticsUnit or target.is_dead():
		return {"type": "damage", "success": false, "error": "目标无效"}

	var target_vars := target.get_formula_vars()
	var vars := _merge_vars(caster_vars, target_vars)
	var formula: String = effect.get("formula", "10")
	var raw_damage := _evaluate_formula(formula, vars)
	var damage: int = maxi(1, int(raw_damage))

	var actual := target.take_damage(damage)
	return {
		"type": "damage",
		"success": true,
		"target": target,
		"raw_damage": damage,
		"actual_damage": actual,
		"element": effect.get("element", ""),
		"target_killed": target.is_dead()
	}


## 治疗效果
func _effect_heal(effect: Dictionary, caster: TacticsUnit, target: TacticsUnit, caster_vars: Dictionary) -> Dictionary:
	if not target is TacticsUnit or target.is_dead():
		return {"type": "heal", "success": false, "error": "目标无效"}

	var target_vars := target.get_formula_vars()
	var vars := _merge_vars(caster_vars, target_vars)
	var formula: String = effect.get("formula", "10")
	var raw_heal := _evaluate_formula(formula, vars)
	var heal_amount: int = maxi(1, int(raw_heal))

	var actual := target.heal(heal_amount)
	return {
		"type": "heal",
		"success": true,
		"target": target,
		"raw_heal": heal_amount,
		"actual_heal": actual
	}


## 增益效果
func _effect_buff(effect: Dictionary, target: TacticsUnit) -> Dictionary:
	var stat: String = effect.get("stat", "")
	var value: int = effect.get("value", 0)
	var duration: int = effect.get("duration", 3)

	if stat.is_empty() or not target is TacticsUnit:
		return {"type": "buff", "success": false, "error": "参数无效"}

	# 通过 set() 修改属性
	if stat in target:
		var current = target.get(stat)
		if current is int:
			target.set(stat, current + value)

	return {
		"type": "buff",
		"success": true,
		"target": target,
		"stat": stat,
		"value": value,
		"duration": duration
	}


## 减益效果
func _effect_debuff(effect: Dictionary, target: TacticsUnit) -> Dictionary:
	# 与 buff 相同逻辑，value 为负数即可
	var stat: String = effect.get("stat", "")
	var value: int = effect.get("value", 0)
	var duration: int = effect.get("duration", 3)

	if stat.is_empty() or not target is TacticsUnit:
		return {"type": "debuff", "success": false, "error": "参数无效"}

	if stat in target:
		var current = target.get(stat)
		if current is int:
			target.set(stat, current - value)

	return {
		"type": "debuff",
		"success": true,
		"target": target,
		"stat": stat,
		"value": value,
		"duration": duration
	}


## 击退效果
func _effect_push(effect: Dictionary, caster: TacticsUnit, target: TacticsUnit) -> Dictionary:
	var distance: int = effect.get("distance", 1)
	# 击退逻辑由 TacticsBoard 处理（需要知道地图边界）
	return {
		"type": "push",
		"success": true,
		"target": target,
		"caster": caster,
		"distance": distance,
		"needs_board_processing": true
	}


## 传送效果
func _effect_teleport(effect: Dictionary, target: TacticsUnit) -> Dictionary:
	var col: int = effect.get("col", -1)
	var row: int = effect.get("row", -1)
	return {
		"type": "teleport",
		"success": true,
		"target": target,
		"col": col,
		"row": row,
		"needs_board_processing": true
	}


## 矢量速度效果 — 由 TacticsBoard 处理方向选择后应用
func _effect_add_velocity(effect: Dictionary, target: TacticsUnit) -> Dictionary:
	var amount: int = effect.get("amount", 0)
	var direction_select: bool = effect.get("direction_select", false)
	return {
		"type": "add_velocity",
		"success": true,
		"target": target,
		"amount": amount,
		"direction_select": direction_select,
		"needs_board_processing": true
	}


## 动量冲量效果 — 施加冲量，速度由目标质量决定（v = impulse / mass）
func _effect_apply_momentum(effect: Dictionary, target: TacticsUnit) -> Dictionary:
	var impulse: float = effect.get("impulse", 0.0)
	var direction_select: bool = effect.get("direction_select", false)
	return {
		"type": "apply_momentum",
		"success": true,
		"target": target,
		"impulse": impulse,
		"direction_select": direction_select,
		"needs_board_processing": true
	}


## 条件效果：先检查条件，满足才执行子效果
func _effect_condition(effect: Dictionary, caster: TacticsUnit, target, caster_vars: Dictionary) -> Dictionary:
	var condition: Dictionary = effect.get("condition", {})
	var cond_type: String = condition.get("type", "")

	var cond_met: bool = false
	match cond_type:
		"hp_below":
			if target is TacticsUnit:
				var threshold: float = condition.get("value", 0.5)
				cond_met = float(target.current_hp) / float(target.max_hp) < threshold
		"hp_above":
			if target is TacticsUnit:
				var threshold: float = condition.get("value", 0.5)
				cond_met = float(target.current_hp) / float(target.max_hp) > threshold
		"has_flag":
			var flag_key: String = condition.get("key", "")
			cond_met = GameState.get_flag(flag_key, false)
		"random":
			var chance: float = condition.get("chance", 0.5)
			cond_met = randf() < chance
		_:
			cond_met = true

	var results: Array = []
	if cond_met:
		for sub_effect in effect.get("effects", []):
			results.append(_execute_effect(sub_effect, caster, target, caster_vars))

	return {
		"type": "condition",
		"success": true,
		"condition_met": cond_met,
		"condition_type": cond_type,
		"sub_effects": results
	}


# =============================================================================
# 公式解析
# =============================================================================

## 解析并计算公式（支持 + - * / 和括号，变量替换）
## 例："atk * 1.5 + 10 - def * 0.5" → 数值
func _evaluate_formula(formula: String, vars: Dictionary) -> float:
	var expr: String = formula.strip_edges()

	# 按 key 长度降序替换，避免短 key 破坏长 key（如 atk 破坏 matk）
	var sorted_keys := vars.keys()
	sorted_keys.sort_custom(func(a: String, b: String): return a.length() > b.length())
	for key in sorted_keys:
		expr = expr.replace(key, str(vars[key]))

	# 计算表达式
	return _eval_expr(expr)


## 简单表达式求值（四则运算 + 括号）
func _eval_expr(expr: String) -> float:
	var expression := Expression.new()
	var error := expression.parse(expr)
	if error != OK:
		push_error("SkillSystem: 公式解析失败: " + expr + " (" + expression.get_error_text() + ")")
		return 0.0

	var result = expression.execute()
	if expression.has_execute_failed():
		push_error("SkillSystem: 公式计算失败: " + expr)
		return 0.0

	return float(result)


# =============================================================================
# 工具方法
# =============================================================================

## 合并施法者和目标属性（目标属性优先，用于公式中的 defender 变量）
func _merge_vars(caster_vars: Dictionary, target_vars: Dictionary) -> Dictionary:
	var merged := caster_vars.duplicate()
	for key in target_vars:
		merged[key] = target_vars[key]
	return merged


## 获取技能的目标类型
func get_skill_target_type(skill_id: String) -> String:
	var skill = _skill_cache.get(skill_id, {})
	return skill.get("target_type", "enemy_single")


## 获取技能的施法范围
func get_skill_range(skill_id: String) -> int:
	var skill = _skill_cache.get(skill_id, {})
	return skill.get("range", 1)


## 获取技能的范围类型
func get_skill_area(skill_id: String) -> String:
	var skill = _skill_cache.get(skill_id, {})
	return skill.get("area", "single")


## 获取技能的范围大小
func get_skill_area_size(skill_id: String) -> int:
	var skill = _skill_cache.get(skill_id, {})
	return skill.get("area_size", 1)
