## 实体定义（相当于「预制体」）：一个角色、道具或地块长什么样、怎么动。
class_name EntityDef
extends RefCounted

const SHAPE_NONE := "none"
const SHAPE_RECT := "rect"
const SHAPE_CIRCLE := "circle"

const PHYSICS_NONE := "none"
const PHYSICS_STATIC := "static"
const PHYSICS_KINEMATIC := "kinematic"
const PHYSICS_RIGID := "rigid"

## 碰撞组。决定"这个东西会挡住谁、又会被谁挡住"。
##
##   ground —— 地面：挡得住会动的东西，**也接得住掉落物**
##   solid  —— 普通障碍：挡得住会动的东西，但掉落物会穿过去（尖刺、静止的怪）
##   pickup —— 拾取物（金币这类）：不挡任何人，只落在"地面"上
##
## 这三档都是用户推着加出来的，按顺序：
##   1. 金币落地后互相踩着往上堆，堆成一根柱子 → 加了 pickup
##   2. 金币粘在会动的小怪身上跟着走（Godot 把脚下的东西当移动平台）
##      → 会动的对象单独一层
##   3. "金币只能跟地面碰撞吧""尖刺不碰吧" → 把"地面"从普通障碍里分出来
const COLLISION_GROUND := "ground"
const COLLISION_SOLID := "solid"
const COLLISION_PICKUP := "pickup"
const VALID_COLLISION_GROUPS: PackedStringArray = [
	COLLISION_GROUND, COLLISION_SOLID, COLLISION_PICKUP,
]

const VALID_SHAPES: PackedStringArray = [SHAPE_NONE, SHAPE_RECT, SHAPE_CIRCLE]
const VALID_PHYSICS: PackedStringArray = [PHYSICS_NONE, PHYSICS_STATIC, PHYSICS_KINEMATIC, PHYSICS_RIGID]

var id: String = ""
var name: String = ""
var asset_id: String = ""
var tags: PackedStringArray = PackedStringArray()
## 无素材时的占位颜色，保证零美术资源也能跑起来。
var color: String = "#4ade80"

var collider_shape: String = SHAPE_NONE
var collider_width: float = 48.0
var collider_height: float = 48.0
var collider_radius: float = 24.0
var collider_offset_x: float = 0.0
var collider_offset_y: float = 0.0

var physics_mode: String = PHYSICS_NONE
var gravity_scale: float = 1.0
var bounce: float = 0.0
var friction: float = 0.6
## 见上面的 COLLISION_* 说明。默认是普通对象。
var collision_group: String = COLLISION_SOLID

## 动画名 -> { "frames": [int], "fps": float, "loop": bool }
var animations: Dictionary = {}
var default_animation: String = ""
## 实体创建时获得的初始属性，例如 { "score": 0, "speed": 260 }
var initial_properties: Dictionary = {}
## 屏幕按键：绑定到一个输入动作，例如 "ui_left"。
##
## 非空就表示这个实体是个「屏幕按键」——它不放进游戏世界，
## 而是固定在屏幕上层。按住它等于按着那个输入动作，
## 松开等于松开。于是键盘和触屏走同一条路：
## 「按住 ui_left 就向左移动」这条规则，两种设备都能用，不用改。
##
## 按键的位置和大小复用实例的 x/y 与碰撞尺寸，只是坐标系换成屏幕像素。
var button_action: String = ""


func is_button() -> bool:
	return not button_action.is_empty()


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## 拾取物：不挡玩家、也不互相挡，但仍然能落在地面上、也仍然吃得到。
func is_pickup() -> bool:
	return collision_group == COLLISION_PICKUP


## 地面：会动的东西（玩家、会动的小怪）站在上面，掉落物也落在上面。
func is_ground() -> bool:
	return collision_group == COLLISION_GROUND


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"asset_id": asset_id,
		"tags": Array(tags),
		"color": color,
		"collider": {
			"shape": collider_shape,
			"width": collider_width,
			"height": collider_height,
			"radius": collider_radius,
			"offset_x": collider_offset_x,
			"offset_y": collider_offset_y,
		},
		"physics": {
			"mode": physics_mode,
			"gravity_scale": gravity_scale,
			"bounce": bounce,
			"friction": friction,
		},
		"collision_group": collision_group,
		"animations": animations.duplicate(true),
		"default_animation": default_animation,
		"initial_properties": initial_properties.duplicate(true),
		"button_action": button_action,
	}


static func from_dict(d: Dictionary) -> EntityDef:
	var e := EntityDef.new()
	e.id = String(d.get("id", ""))
	e.name = String(d.get("name", ""))
	e.asset_id = String(d.get("asset_id", ""))
	e.tags = PackedStringArray(d.get("tags", []))
	e.color = String(d.get("color", e.color))

	var col: Dictionary = d.get("collider", {})
	e.collider_shape = String(col.get("shape", EntityDef.SHAPE_NONE))
	e.collider_width = float(col.get("width", e.collider_width))
	e.collider_height = float(col.get("height", e.collider_height))
	e.collider_radius = float(col.get("radius", e.collider_radius))
	e.collider_offset_x = float(col.get("offset_x", 0.0))
	e.collider_offset_y = float(col.get("offset_y", 0.0))

	var phy: Dictionary = d.get("physics", {})
	e.physics_mode = String(phy.get("mode", EntityDef.PHYSICS_NONE))
	e.gravity_scale = float(phy.get("gravity_scale", 1.0))
	e.bounce = float(phy.get("bounce", 0.0))
	e.friction = float(phy.get("friction", 0.6))
	e.collision_group = String(d.get("collision_group", EntityDef.COLLISION_SOLID))

	var anims: Variant = d.get("animations", {})
	e.animations = (anims as Dictionary).duplicate(true) if anims is Dictionary else {}
	e.default_animation = String(d.get("default_animation", ""))
	var props: Variant = d.get("initial_properties", {})
	e.initial_properties = (props as Dictionary).duplicate(true) if props is Dictionary else {}
	e.button_action = String(d.get("button_action", ""))
	return e
