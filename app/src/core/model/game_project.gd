## 一个完整的游戏原型工程。整个平台的数据根对象。
class_name GameProject
extends RefCounted

## 工程文件格式版本。改动数据含义时**必须往上加一位**，并在
## from_dict 里给老文件补一次升级 —— 否则用户打开旧工程会撞上
## "东西看着对、跑起来不对"的怪事。
const SCHEMA_VERSION := "1.1"
const FILE_EXTENSION := "ai2d"

var schema_version: String = SCHEMA_VERSION
var id: String = ""
var name: String = "未命名原型"
var created_at: String = ""
var updated_at: String = ""

var config: ProjectConfig = ProjectConfig.new()
var assets: Array[AssetDef] = []
var entities: Array[EntityDef] = []
var scenes: Array[SceneDef] = []
var rules: Array[RuleDef] = []


func find_asset(asset_id: String) -> AssetDef:
	for a in assets:
		if a.id == asset_id:
			return a
	return null


func find_entity(entity_id: String) -> EntityDef:
	for e in entities:
		if e.id == entity_id:
			return e
	return null


func find_scene(scene_id: String) -> SceneDef:
	for s in scenes:
		if s.id == scene_id:
			return s
	return null


func start_scene() -> SceneDef:
	if scenes.is_empty():
		return null
	var s := find_scene(config.start_scene_id)
	return s if s != null else scenes[0]


## 返回所有具有指定标签的实体定义
func entities_with_tag(tag: String) -> Array[EntityDef]:
	var out: Array[EntityDef] = []
	for e in entities:
		if e.has_tag(tag):
			out.append(e)
	return out


func to_dict() -> Dictionary:
	var a: Array = []
	for x in assets:
		a.append(x.to_dict())
	var e: Array = []
	for x in entities:
		e.append(x.to_dict())
	var s: Array = []
	for x in scenes:
		s.append(x.to_dict())
	var r: Array = []
	for x in rules:
		r.append(x.to_dict())
	return {
		"schema_version": schema_version,
		"id": id,
		"name": name,
		"created_at": created_at,
		"updated_at": updated_at,
		"config": config.to_dict(),
		"assets": a,
		"entities": e,
		"scenes": s,
		"rules": r,
	}


static func from_dict(d: Dictionary) -> GameProject:
	var p := GameProject.new()
	p.schema_version = String(d.get("schema_version", GameProject.SCHEMA_VERSION))
	p.id = String(d.get("id", ""))
	p.name = String(d.get("name", p.name))
	p.created_at = String(d.get("created_at", ""))
	p.updated_at = String(d.get("updated_at", ""))

	var cfg: Variant = d.get("config", {})
	p.config = ProjectConfig.from_dict(cfg) if cfg is Dictionary else ProjectConfig.new()

	p.assets = []
	for raw in d.get("assets", []):
		if raw is Dictionary:
			p.assets.append(AssetDef.from_dict(raw))
	p.entities = []
	for raw in d.get("entities", []):
		if raw is Dictionary:
			p.entities.append(EntityDef.from_dict(raw))
	p.scenes = []
	for raw in d.get("scenes", []):
		if raw is Dictionary:
			p.scenes.append(SceneDef.from_dict(raw))
	p.rules = []
	for raw in d.get("rules", []):
		if raw is Dictionary:
			p.rules.append(RuleDef.from_dict(raw))
	_upgrade(p)
	return p


## 老工程升级。**改数据含义时必须在这里补一笔**，否则用户打开旧工程
## 会撞上"看着没事、跑起来不对"的怪事 —— 那种问题最难查。
static func _upgrade(p: GameProject) -> void:
	var from := p.schema_version
	if from == SCHEMA_VERSION:
		return

	# 1.0 → 1.1：那时还没有「地面」这一档碰撞组。
	# 当时所有地面都被写成 solid，而掉落物的掩码里只有"地面"那一层，
	# 于是升级之后金币会穿过一切掉出画面（用户实测报过这一条）。
	# 这里按下「ground」标签补一次 —— 示例和练习工程本来就靠这个标签认地面。
	if _version_before(from, "1.1"):
		for e in p.entities:
			if e.has_tag("ground") and e.collision_group == EntityDef.COLLISION_SOLID:
				e.collision_group = EntityDef.COLLISION_GROUND

	# 未来版本号的文件不动它：那时候的兼容问题不该由这一版猜
	if _version_before(from, SCHEMA_VERSION):
		p.schema_version = SCHEMA_VERSION


## a 是不是比 b 旧（"1.0" 比 "1.1" 旧）。按段比数字，
## 免得 "1.10" 被当成比 "1.9" 旧这种字面比较的坑。
static func _version_before(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var va := int(pa[i]) if i < pa.size() else 0
		var vb := int(pb[i]) if i < pb.size() else 0
		if va != vb:
			return va < vb
	return false
