## 摆放在场景里的一个实体实例。
class_name PlacedEntity
extends RefCounted

## 「会不会动、会不会掉」的可选档位。空串表示跟随实体定义。
##
## 只给三个档位、而不是把物理模式原样摆出来，是因为用户要回答的是两个问题：
## 它会不会动？它会不会往下掉？——"静止""会飞""会掉"正好覆盖做原型要的三种。
const MOTION_FOLLOW := ""
## "不参与物理"：不会被挡住、也不挡住别人、更不会掉（金币那种能穿过去的）
const MOTION_NONE := "none"
const MOTION_STATIC := "static"
const MOTION_FLOAT := "float"
const MOTION_FALL := "fall"

## 实例面板上的档位：多一档"跟随类型"
const MOTION_OPTIONS: Array[Dictionary] = [
	{"value": MOTION_FOLLOW, "label": "跟随类型"},
	{"value": MOTION_NONE, "label": "不参与物理（能穿过去、也不会掉）"},
	{"value": MOTION_STATIC, "label": "静止不动"},
	{"value": MOTION_FLOAT, "label": "会动 · 不受重力（会飞的）"},
	{"value": MOTION_FALL, "label": "会动 · 受重力（会掉的）"},
]

## 类型面板上的档位：类型是源头，没有"跟随类型"这一项
const MOTION_TYPE_OPTIONS: Array[Dictionary] = [
	{"value": MOTION_NONE, "label": "不参与物理（能穿过去、也不会掉）"},
	{"value": MOTION_STATIC, "label": "静止不动（会挡住别的对象）"},
	{"value": MOTION_FLOAT, "label": "会动 · 不受重力（会飞的）"},
	{"value": MOTION_FALL, "label": "会动 · 受重力（会掉的）"},
]


## 档位 → 物理模式与重力。类型面板、实例覆盖、运行器都读这一张表，
## 免得出现"面板上选的是会飞、跑起来却是静止"这种事。
static func motion_of_preset(preset: String) -> Dictionary:
	if preset == MOTION_NONE:
		return {"mode": EntityDef.PHYSICS_NONE, "gravity_scale": 0.0}
	if preset == MOTION_STATIC:
		return {"mode": EntityDef.PHYSICS_STATIC, "gravity_scale": 0.0}
	if preset == MOTION_FLOAT:
		return {"mode": EntityDef.PHYSICS_KINEMATIC, "gravity_scale": 0.0}
	if preset == MOTION_FALL:
		return {"mode": EntityDef.PHYSICS_KINEMATIC, "gravity_scale": 1.0}
	return {}


## 反过来：从类型上写的物理模式与重力，反推它属于哪一档。
## 类型面板要用它回显"现在选的是哪一档"。
static func motion_preset_of(mode: String, gravity_scale: float) -> String:
	if mode == EntityDef.PHYSICS_NONE:
		return MOTION_NONE
	if mode == EntityDef.PHYSICS_KINEMATIC:
		return MOTION_FALL if gravity_scale > 0.0 else MOTION_FLOAT
	return MOTION_STATIC

## 「会挡住谁、又会被谁挡住」的可选档位。空串表示跟随实体定义。
##
## 和「会动吗」是同一个套路：这些身份本来只写在类型上，
## 而类型在界面上改不了，于是用户想把某块平台标成"地面"、或者
## 想让某个对象变成拾取物，就只能去手改 JSON。这里给一条实例级的通道。
const COLLISION_OPTIONS: Array[Dictionary] = [
	{"value": "", "label": "跟随类型"},
	{"value": EntityDef.COLLISION_GROUND, "label": "地面（接得住掉落的东西）"},
	{"value": EntityDef.COLLISION_SOLID, "label": "普通障碍（挡得住人，掉落物会穿过去）"},
	{"value": EntityDef.COLLISION_PICKUP, "label": "拾取物（不挡人，只落在地面上）"},
]

## 类型面板上的碰撞档位：类型是源头，没有"跟随类型"这一项
const COLLISION_TYPE_OPTIONS: Array[Dictionary] = [
	{"value": EntityDef.COLLISION_GROUND, "label": "地面（接得住掉落的东西）"},
	{"value": EntityDef.COLLISION_SOLID, "label": "普通障碍（挡得住人，掉落物会穿过去）"},
	{"value": EntityDef.COLLISION_PICKUP, "label": "拾取物（不挡人，只落在地面上）"},
]


## 这个对象最终属于哪一组碰撞。实例自己设了就听它的，否则跟随类型。
static func resolve_collision_group(def: EntityDef, placed: PlacedEntity) -> String:
	if placed != null and not placed.collision_group.is_empty():
		return placed.collision_group
	if def == null:
		return EntityDef.COLLISION_SOLID
	return def.collision_group


## 这个对象最终"用哪种物理模式、受多少重力"。
##
## 实例自己设了档位就听它的，否则跟随类型 —— 和颜色、按键绑定一个道理。
## 运行器和属性面板都读这一个函数，免得两边各算各的、算出不一样的结果。
static func resolve_motion(def: EntityDef, placed: PlacedEntity) -> Dictionary:
	if placed != null:
		var preset := motion_of_preset(placed.motion)
		if not preset.is_empty():
			return preset
	if def == null:
		return {"mode": EntityDef.PHYSICS_NONE, "gravity_scale": 0.0}
	return {"mode": def.physics_mode, "gravity_scale": def.gravity_scale}


var instance_id: String = ""
var entity_id: String = ""
var x: float = 0.0
var y: float = 0.0
var rotation: float = 0.0
var scale_x: float = 1.0
var scale_y: float = 1.0
var flip_h: bool = false
## 只改这一个对象的颜色。留空表示跟随所属实体定义的颜色。
##
## 之所以要这个字段：颜色原本只存在实体定义（类型）上，
## 于是"把这个金币改成红色"在数据层面根本无法表达 —— 一改就是所有金币一起变。
var color: String = ""
## 只改这一个按键绑定的输入动作。留空表示跟随实体定义。
##
## 和颜色同一个道理：绑定写在类型上，一改就是所有同类按键一起变。
## 但用户心里想的是"我改的是这一个键" —— 尤其是复制出一个新键之后。
var button_action: String = ""
## 只改这一个对象"会不会动、会不会往下掉"。留空表示跟随实体定义。
##
## 为什么不是把 Godot 的物理模式直接摆给用户看：那是一个单词
## （none/static/kinematic/rigid），用户要的是两个问题——
## "它会不会动" 和 "它会不会往下掉"。所以这里存的是三个能看懂的档位。
##
## 这件事是用户逼出来的：他用规则给 AI 生成的小怪设了速度，小怪纹丝不动。
## 根因是那只小怪的物理类型是"静止"，而静止对象根本不参与物理步进 ——
## 速度写进去了，没有任何东西去用它。
var motion: String = ""
## 只改这一个对象的碰撞身份（地面 / 普通障碍 / 拾取物）。留空表示跟随类型。
var collision_group: String = ""
## 覆盖实体定义里的初始属性
var properties: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"entity_id": entity_id,
		"x": x,
		"y": y,
		"rotation": rotation,
		"scale_x": scale_x,
		"scale_y": scale_y,
		"flip_h": flip_h,
		"color": color,
		"button_action": button_action,
		"motion": motion,
		"collision_group": collision_group,
		"properties": properties.duplicate(true),
	}


static func from_dict(d: Dictionary) -> PlacedEntity:
	var p := PlacedEntity.new()
	p.instance_id = String(d.get("instance_id", ""))
	p.entity_id = String(d.get("entity_id", ""))
	p.x = float(d.get("x", 0.0))
	p.y = float(d.get("y", 0.0))
	p.rotation = float(d.get("rotation", 0.0))
	p.scale_x = float(d.get("scale_x", 1.0))
	p.scale_y = float(d.get("scale_y", 1.0))
	p.flip_h = bool(d.get("flip_h", false))
	p.color = String(d.get("color", ""))
	p.button_action = String(d.get("button_action", ""))
	p.motion = String(d.get("motion", ""))
	p.collision_group = String(d.get("collision_group", ""))
	var props: Variant = d.get("properties", {})
	p.properties = (props as Dictionary).duplicate(true) if props is Dictionary else {}
	return p
