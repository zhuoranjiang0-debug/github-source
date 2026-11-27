## 场景定义（相当于「关卡」）：背景、相机、摆放了哪些实体。
class_name SceneDef
extends RefCounted

const CAMERA_FIXED := "fixed"
const CAMERA_FOLLOW := "follow"

var id: String = ""
var name: String = ""
var background_color: String = ""
var background_asset_id: String = ""

var camera_mode: String = CAMERA_FIXED
## 相机跟随目标，用选择器语法，例如 "tag:player"
var camera_target: String = ""
var camera_zoom: float = 1.0

## 可选的地块层：tile_grid 的每个数字是图集里的瓦片索引，-1 表示空。
var tile_size: int = 64
var tilemap_asset_id: String = ""
var tile_grid: Array = []

var instances: Array[PlacedEntity] = []


func to_dict() -> Dictionary:
	var inst: Array = []
	for i in instances:
		inst.append(i.to_dict())
	return {
		"id": id,
		"name": name,
		"background_color": background_color,
		"background_asset_id": background_asset_id,
		"camera": {
			"mode": camera_mode,
			"target": camera_target,
			"zoom": camera_zoom,
		},
		"tilemap": {
			"tile_size": tile_size,
			"asset_id": tilemap_asset_id,
			"grid": tile_grid.duplicate(true),
		},
		"instances": inst,
	}


static func from_dict(d: Dictionary) -> SceneDef:
	var s := SceneDef.new()
	s.id = String(d.get("id", ""))
	s.name = String(d.get("name", ""))
	s.background_color = String(d.get("background_color", ""))
	s.background_asset_id = String(d.get("background_asset_id", ""))

	var cam: Dictionary = d.get("camera", {})
	s.camera_mode = String(cam.get("mode", SceneDef.CAMERA_FIXED))
	s.camera_target = String(cam.get("target", ""))
	s.camera_zoom = float(cam.get("zoom", 1.0))

	var tm: Dictionary = d.get("tilemap", {})
	s.tile_size = int(tm.get("tile_size", 64))
	s.tilemap_asset_id = String(tm.get("asset_id", ""))
	var grid: Variant = tm.get("grid", [])
	s.tile_grid = (grid as Array).duplicate(true) if grid is Array else []

	s.instances = []
	for raw in d.get("instances", []):
		if raw is Dictionary:
			s.instances.append(PlacedEntity.from_dict(raw))
	return s
