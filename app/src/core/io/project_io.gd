## 工程文件的读写与 JSON 序列化。
##
## 所有落盘格式都是 UTF-8 的 JSON，扩展名 .ai2d。
## 这样做的直接好处：文件可读、可 diff、可手工修，出问题时肉眼就能定位，
## 并且 AI 模块可以直接产出这个格式而不需要理解引擎。
class_name ProjectIO
extends RefCounted


class LoadResult:
	extends RefCounted
	var ok: bool = false
	var error: String = ""
	var project: GameProject = null


## 生成一个短 ID，形如 "ent_3f9a2c1b"。
static func new_id(prefix: String) -> String:
	var bytes := PackedByteArray()
	bytes.resize(4)
	for i in 4:
		bytes[i] = randi() & 0xFF
	var hex := ""
	for b in bytes:
		hex += "%02x" % b
	return "%s_%s" % [prefix, hex]


static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true, true)


static func create_empty(project_name: String) -> GameProject:
	var p := GameProject.new()
	p.id = new_id("prj")
	p.name = project_name
	p.created_at = now_iso()
	p.updated_at = p.created_at
	var s := SceneDef.new()
	s.id = new_id("scn")
	s.name = "关卡 1"
	p.scenes = [s]
	p.config.start_scene_id = s.id
	return p


# --------------------------------------------------------------------------
# 序列化
# --------------------------------------------------------------------------

static func to_json_string(project: GameProject, pretty: bool = true) -> String:
	var indent := "\t" if pretty else ""
	return JSON.stringify(project.to_dict(), indent, false)


static func from_json_string(text: String) -> LoadResult:
	var res := LoadResult.new()
	# 用 JSON 对象而不是 JSON.parse_string，是为了拿到出错的行号：
	# 用户手改工程文件时括号或逗号写错是最常见的情况，
	# 只说「解析失败」而不指出第几行，等于没说。
	var parser := JSON.new()
	if parser.parse(text) != OK:
		res.ok = false
		res.error = "第 %d 行写错了：%s" % [parser.get_error_line(), parser.get_error_message()]
		return res
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		res.ok = false
		res.error = "工程文件的顶层必须是一个对象（{ ... }）"
		return res
	res.project = GameProject.from_dict(parsed)
	res.ok = true
	return res


# --------------------------------------------------------------------------
# 文件读写
# --------------------------------------------------------------------------

static func save_to_file(project: GameProject, path: String) -> String:
	project.updated_at = now_iso()
	var text := to_json_string(project, true)
	# 目录不存在就建出来，免得用户第一次保存时报"写不进去"却不知道为什么
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return "无法创建目录：%s（错误码 %d）" % [dir, err]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "无法写入文件：%s（错误码 %d）" % [path, FileAccess.get_open_error()]
	f.store_string(text)
	f.close()
	return ""


static func load_from_file(path: String) -> LoadResult:
	var res := LoadResult.new()
	if not FileAccess.file_exists(path):
		res.error = "找不到工程文件：%s" % path
		return res
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		res.error = "文件是空的：%s" % path
		return res

	# 先做字节级体检。不这么做的话，编码损坏会以「JSON 语法错误」的形式
	# 报出来，把人的注意力引到完全错误的方向。
	var bad := TextEncoding.first_invalid_offset(bytes)
	if bad >= 0:
		res.error = "第 %d 行附近有非法字符，文件的文字编码坏了。\n多半是编辑器保存时用了 GBK 之类的非 UTF-8 编码，请改用 UTF-8 重新保存。" \
			% TextEncoding.byte_offset_to_line(bytes, bad)
		return res
	if TextEncoding.contains_replacement_char(bytes):
		res.error = "文件里有乱码字符（说明之前被错误编码破坏过），请把受影响的文字改回正常内容。"
		return res

	return from_json_string(TextEncoding.decode(bytes))


## 导出为可分享的文本，去掉缩进以减小体积。
static func export_shareable(project: GameProject) -> String:
	return to_json_string(project, false)
