extends Node

## 存档管理器 Autoload：负责存档文件的读写与元数据管理

const SAVE_DIR = "user://saves/"
const SAVE_PREFIX = "slot_%d.json"
const MAX_SLOTS = 10

## 存档数据结构
## {
##   "timestamp": String,
##   "preview": String,
##   "current_node_id": String,
##   "flags": Dictionary,
##   "dialogue_history": Array,
##   "choice_nodes_log": Array
## }

func _ready():
	# 确保存档目录存在
	DirAccess.make_dir_absolute("user://saves")

## 保存存档到指定槽位
func save_to_slot(slot_index: int, data: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false

	var path = SAVE_DIR + SAVE_PREFIX % slot_index
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: 无法写入存档: " + path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

## 从指定槽位读取存档
func load_from_slot(slot_index: int) -> Dictionary:
	var path = SAVE_DIR + SAVE_PREFIX % slot_index
	if not FileAccess.file_exists(path):
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("SaveManager: JSON 解析失败: " + json.get_error_message())
		return {}

	return json.data

## 删除指定槽位的存档
func delete_slot(slot_index: int) -> bool:
	var path = SAVE_DIR + SAVE_PREFIX % slot_index
	if not FileAccess.file_exists(path):
		return false

	var dir = DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	return dir.remove(SAVE_PREFIX % slot_index)

## 获取槽位信息（用于 UI 显示），返回 {"isEmpty": bool, "timestamp": str, "preview": str}
func get_slot_info(slot_index: int) -> Dictionary:
	var path = SAVE_DIR + SAVE_PREFIX % slot_index
	if not FileAccess.file_exists(path):
		return {"isEmpty": true, "timestamp": "", "preview": "空存档"}

	var data = load_from_slot(slot_index)
	if data.is_empty():
		return {"isEmpty": true, "timestamp": "", "preview": "空存档"}

	return {
		"isEmpty": false,
		"timestamp": data.get("timestamp", ""),
		"preview": data.get("preview", "无预览")
	}

## 获取所有槽位信息
func get_all_slots() -> Array:
	var slots = []
	for i in range(MAX_SLOTS):
		slots.append(get_slot_info(i))
	return slots

## 检查槽位是否有存档
func has_save(slot_index: int) -> bool:
	return FileAccess.file_exists(SAVE_DIR + SAVE_PREFIX % slot_index)

## 获取所有非空存档槽位
func get_non_empty_slots() -> Array:
	var result = []
	for i in range(MAX_SLOTS):
		if has_save(i):
			result.append({
				"index": i,
				"info": get_slot_info(i)
			})
	return result
