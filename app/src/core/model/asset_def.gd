## 素材定义：图片、图集、音频、字体。
class_name AssetDef
extends RefCounted

const TYPE_SPRITE := "sprite"
const TYPE_TILESET := "tileset"
const TYPE_AUDIO := "audio"
const TYPE_FONT := "font"

const SOURCE_BUILTIN := "builtin"
const SOURCE_GENERATED := "generated"
const SOURCE_UPLOADED := "uploaded"

const VALID_TYPES: PackedStringArray = [TYPE_SPRITE, TYPE_TILESET, TYPE_AUDIO, TYPE_FONT]
const VALID_SOURCES: PackedStringArray = [SOURCE_BUILTIN, SOURCE_GENERATED, SOURCE_UPLOADED]

var id: String = ""
var name: String = ""
var type: String = TYPE_SPRITE
var source: String = SOURCE_BUILTIN
## 相对工程资源目录的路径；为空表示尚无实体文件，运行时用占位图形渲染。
var path: String = ""
## 类型相关的附加信息：帧尺寸、帧数、生成参数等。
var meta: Dictionary = {}


func is_visual() -> bool:
	return type == TYPE_SPRITE or type == TYPE_TILESET


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"type": type,
		"source": source,
		"path": path,
		"meta": meta.duplicate(true),
	}


static func from_dict(d: Dictionary) -> AssetDef:
	var a := AssetDef.new()
	a.id = String(d.get("id", ""))
	a.name = String(d.get("name", ""))
	a.type = String(d.get("type", AssetDef.TYPE_SPRITE))
	a.source = String(d.get("source", AssetDef.SOURCE_BUILTIN))
	a.path = String(d.get("path", ""))
	var m: Variant = d.get("meta", {})
	a.meta = (m as Dictionary).duplicate(true) if m is Dictionary else {}
	return a
