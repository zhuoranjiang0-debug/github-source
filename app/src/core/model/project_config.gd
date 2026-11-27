## 工程级配置：画布尺寸、重力、起始场景等。
class_name ProjectConfig
extends RefCounted

const ORIENTATION_LANDSCAPE := "landscape"
const ORIENTATION_PORTRAIT := "portrait"

var canvas_width: int = 1280
var canvas_height: int = 720
var orientation: String = ORIENTATION_LANDSCAPE
var gravity: float = 1600.0
var background_color: String = "#12161f"
var start_scene_id: String = ""


func to_dict() -> Dictionary:
	return {
		"canvas": {
			"width": canvas_width,
			"height": canvas_height,
		},
		"orientation": orientation,
		"gravity": gravity,
		"background_color": background_color,
		"start_scene_id": start_scene_id,
	}


static func from_dict(d: Dictionary) -> ProjectConfig:
	var c := ProjectConfig.new()
	var canvas: Dictionary = d.get("canvas", {})
	c.canvas_width = int(canvas.get("width", c.canvas_width))
	c.canvas_height = int(canvas.get("height", c.canvas_height))
	c.orientation = String(d.get("orientation", c.orientation))
	c.gravity = float(d.get("gravity", c.gravity))
	c.background_color = String(d.get("background_color", c.background_color))
	c.start_scene_id = String(d.get("start_scene_id", ""))
	return c
