## 一条可视化规则：当【事件】发生，若【条件】全部成立，则执行【动作】。
class_name RuleDef
extends RefCounted

var id: String = ""
var name: String = ""
var enabled: bool = true
## 为空表示对所有场景生效
var scene_id: String = ""
var trigger: Dictionary = {}
var conditions: Array = []
var actions: Array = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"enabled": enabled,
		"scene_id": scene_id,
		"trigger": trigger.duplicate(true),
		"conditions": conditions.duplicate(true),
		"actions": actions.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RuleDef:
	var r := RuleDef.new()
	r.id = String(d.get("id", ""))
	r.name = String(d.get("name", ""))
	r.enabled = bool(d.get("enabled", true))
	r.scene_id = String(d.get("scene_id", ""))
	var t: Variant = d.get("trigger", {})
	r.trigger = (t as Dictionary).duplicate(true) if t is Dictionary else {}
	var c: Variant = d.get("conditions", [])
	r.conditions = (c as Array).duplicate(true) if c is Array else []
	var a: Variant = d.get("actions", [])
	r.actions = (a as Array).duplicate(true) if a is Array else []
	return r
