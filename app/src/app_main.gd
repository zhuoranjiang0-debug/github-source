## 程序入口：负责在「编辑器」和「试玩」两种模式之间切换。
##
## 两种模式共用同一份数据（EditSession 里的 GameProject），
## 所以点运行之后看到的就是刚刚编辑的东西，不需要先存盘。
##
## 启动参数：
##   --project <路径>   打开指定的工程文件
##   --play             直接进入试玩模式（跳过编辑器）
extends Node2D

const SAMPLE_PATH := "res://samples/demo-jump.ai2d.json"
const NEW_PROJECT_FILE := "my-prototype.ai2d.json"
## 用户自己的作品放在这里，和只读的示例分开，免得混在一起分不清
const PROJECTS_DIR := "projects"
## 编辑器上下两条工具栏加起来需要的高度
const EDITOR_BARS_HEIGHT := 200
## 编辑器右侧属性面板的宽度
const EDITOR_SIDE_PANEL_WIDTH := 300
const ERROR_COLOR := Color("#f87171")
const WIN_COLOR := Color("#4ade80")
const EDITOR_CLEAR_COLOR := Color("#0e1116")

var _editor: EditorScreen = null
var _runtime: GameRuntime = null
var _session: EditSession = null
var _current_path: String = SAMPLE_PATH
var _window_sized: bool = false

var _hud: CanvasLayer = null
var _game_hud: Control = null
var _score_label: Label = null
var _hp_label: Label = null
var _hint_label: Label = null
var _banner: Label = null
var _back_button: Button = null


func _ready() -> void:
	_build_hud()

	var play_only := false
	var path := SAMPLE_PATH
	for args in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for i in args.size():
			if args[i] == "--play":
				play_only = true
			elif args[i] == "--project" and i + 1 < args.size():
				var resolved := _resolve_project_path(args[i + 1])
				if not resolved.is_empty():
					path = resolved
	_current_path = path

	# 编辑器优先打开用户上一次的作品，没有才退回示例。
	# 否则用户存下的东西下次根本找不到，只能一次次从示例重新开始。
	#
	# 但**跑自动化测试时跳过这一步**：测试要的是一个确定的、干净的工程。
	# 曾经因为这一条，测试结果会随"用户手边那份作品"变化 ——
	# 用户在编辑器里多摆了一只小怪，就有测试开始报"对象数对不上"。
	if not play_only and path == SAMPLE_PATH and not _running_tests():
		var mine := _default_save_path()
		if FileAccess.file_exists(mine):
			path = mine
			_current_path = mine

	if play_only:
		_enter_play_from_file(path)
	else:
		_enter_edit(path)


# --------------------------------------------------------------------------
# 模式切换
# --------------------------------------------------------------------------

## 只清掉界面上的东西，会话（_session）刻意保留 ——
## 这样「编辑 → 运行 → 返回编辑」来回切时，没保存的改动不会丢。
func _clear_modes() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.shutdown()
		_runtime.queue_free()
	_runtime = null
	if _editor != null and is_instance_valid(_editor):
		_editor.queue_free()
	_editor = null


func _enter_edit(path: String) -> void:
	var session := EditSession.new()
	if not session.open(path):
		_show_banner("打不开这份工程\n\n%s" % session.last_error, ERROR_COLOR, 26)
		return
	_enter_editor(session)


func _enter_editor(session: EditSession) -> void:
	_clear_modes()
	_session = session
	_hide_banner()
	_set_game_hud_visible(false)
	RenderingServer.set_default_clear_color(EDITOR_CLEAR_COLOR)

	_editor = EditorScreen.new()
	add_child(_editor)
	_editor.setup(session, _default_save_path())
	# 编辑器只管喊一声「我要运行」，切模式由这里负责。
	# 少了这一行，运行按钮和 F5 都会变成哑的 —— 界面看着完全正常，就是没反应。
	_editor.request_play.connect(_on_request_play)

	var canvas := Vector2(session.project.config.canvas_width, session.project.config.canvas_height)
	_ensure_window_size(canvas)
	_window().title = "编辑器 —— %s" % session.project.name


func _enter_play_from_file(path: String) -> void:
	var result := ProjectIO.load_from_file(path)
	if not result.ok:
		_show_banner("打不开这份工程\n\n%s" % result.error, ERROR_COLOR, 26)
		return
	var issues := ProjectValidator.validate(result.project)
	if ProjectValidator.has_errors(issues):
		_show_banner("这份工程有错误，跑不起来\n\n%s" % _first_errors(issues), ERROR_COLOR, 26)
		print(ProjectValidator.format_all(issues))
		return
	_enter_play_with_project(result.project, "")


func _enter_play_with_project(project: GameProject, scene_id: String) -> void:
	_clear_modes()
	_hide_banner()
	_set_game_hud_visible(true)

	_runtime = GameRuntime.new()
	_runtime.setup(project)
	_runtime.game_ended.connect(_on_game_ended)
	add_child(_runtime)
	_runtime.start(scene_id)

	# 不在这里改窗口大小。中途改尺寸会让 Godot 的视口和系统窗口对不上，
	# 屏幕上会残留半屏旧画面，要最小化再还原才刷新（真实踩过）。
	var canvas := Vector2(project.config.canvas_width, project.config.canvas_height)
	_ensure_window_size(canvas)
	# 游戏一律从窗口左上角开始画，不做任何偏移。
	#
	# 曾经为了"居中好看"算过一次偏移量：(窗口尺寸 - 画布尺寸) / 2。
	# 但窗口尺寸在有些情况下（显示缩放、系统裁剪、最大化）会比真实窗口大，
	# 算出来的偏移会把游戏整个推出可视区域 —— 用户看到的就是
	# "试玩里什么都没有，只剩分数和生命"。好看不值得冒这个险。
	_runtime.position = Vector2.ZERO
	RenderingServer.set_default_clear_color(Color(project.config.background_color))

	_window().title = "试玩 —— %s" % project.name
	_update_hud()
	print("开始试玩：%s" % project.name)


## 窗口尺寸在本次运行中只设定一次，之后绝不改变。
func _ensure_window_size(canvas: Vector2) -> void:
	if _window_sized:
		return
	_window_sized = true
	# 只有桌面平台才自己设窗口尺寸。
	#
	# 在网页版和手机/平板上，"窗口"就是页面上那块画布、或者整块屏幕，
	# 尺寸不归我们管。一改，Godot 内部就记下一个和实际显示区域不一样的尺寸
	# （网页版实测：记录 1580x920，画布实际 1280x720），
	# 于是画面比例、点击坐标全都跟着错。
	#
	# 这个函数的本来目的只是"给桌面窗口的上下工具栏腾出高度"，
	# 而移动端上窗口就是满屏，本来就不需要腾。
	if not _is_desktop():
		print("非桌面平台：窗口尺寸由系统决定，跳过 %dx%d 的设置" % [canvas.x, canvas.y])
		return
	_window().size = Vector2i(
		int(maxf(canvas.x + EDITOR_SIDE_PANEL_WIDTH, 1360.0)),
		int(canvas.y + EDITOR_BARS_HEIGHT))


static func _is_desktop() -> bool:
	return not (OS.has_feature("web") or OS.has_feature("mobile"))


func _on_request_play() -> void:
	# 直接拿会话里的工程跑，而不是重新读文件：
	# 用户刚拖进去、还没保存的东西，点运行就该立刻看得到。
	if _session == null or _session.project == null:
		return
	_enter_play_with_project(_session.project, _session.current_scene().id)


func _on_escape() -> void:
	if _session != null and _session.project != null:
		_enter_editor(_session)
	else:
		_enter_edit(_current_path)


func _window() -> Window:
	return get_window()


# --------------------------------------------------------------------------
# 路径
# --------------------------------------------------------------------------

func _resolve_project_path(raw: String) -> String:
	if raw.begins_with("res://") or raw.begins_with("user://"):
		return raw
	var res_root := ProjectSettings.globalize_path("res://")
	var candidates: Array[String] = [
		raw,
		res_root.path_join("..").path_join(raw).simplify_path(),
		res_root.path_join(raw).simplify_path(),
	]
	if raw.begins_with("app/"):
		candidates.append(res_root.path_join(raw.substr(4)).simplify_path())
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## 编辑器里按「保存」时，若这份工程还没存过、或者是内置示例，就存到这里。
## 放在 projects 目录下，用户能在文件夹里亲眼看到文件出现。
## 现在是不是在跑自动化测试。
##
## 测试脚本启动时会把 `ai2d/headless_tests` 设成 true（见 run_tests.gd 开头）。
## 这样 app_main 就不会去打开"用户上一次的作品" —— 测试必须与用户手边的
## 东西无关，否则同一份代码在不同机器上跑出不同结果。
func _running_tests() -> bool:
	return bool(ProjectSettings.get_setting("ai2d/headless_tests", false))


func _default_save_path() -> String:
	return ProjectSettings.globalize_path("res://") \
		.path_join(PROJECTS_DIR).path_join(NEW_PROJECT_FILE)


# --------------------------------------------------------------------------
# 输入
# --------------------------------------------------------------------------

## 退出试玩放在 _input 而不是 _unhandled_input：
## _unhandled_input 是输入链的最后一站，在它之前任何一个控件都可能把事件吃掉；
## 而 _input 是第一站，只要在试玩模式就一定能拦到。
func _input(event: InputEvent) -> void:
	if _runtime == null or _editor != null:
		return
	var wants_exit: bool = event.is_action_pressed("ui_cancel") \
		or (event is InputEventKey and event.pressed and not event.echo
			and event.keycode == KEY_ESCAPE)
	if wants_exit:
		_on_escape()
		# Node2D 没有 accept_event()，那是有 Control 才有的方法
		get_viewport().set_input_as_handled()


func _on_game_ended(result: String, message: String) -> void:
	var color := WIN_COLOR if result == "win" else ERROR_COLOR
	var prefix := "胜利！" if result == "win" else "失败"
	var text := "%s %s" % [prefix, message] if not message.is_empty() else prefix
	_show_banner("%s\n\n按 R 重开    ·    按 Esc 回到编辑" % text, color)


# --------------------------------------------------------------------------
# HUD
# --------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	_game_hud = Control.new()
	_game_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_hud.visible = false
	_hud.add_child(_game_hud)

	_score_label = _make_label(_game_hud, 30, Color("#fbbf24"))
	_place(_score_label, 24, 16, 300, 40)
	_hp_label = _make_label(_game_hud, 30, Color("#f87171"))
	_place(_hp_label, 24, 56, 300, 40)

	_hint_label = _make_label(_game_hud, 18, Color(1, 1, 1, 0.45))
	_hint_label.text = "方向键或左下按键移动    ·    空格或点屏幕跳跃    ·    R 重开"
	# 挪到上方：底部是屏幕按键的地盘，提示放那儿会被盖住
	_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	_hint_label.offset_left = 24
	_hint_label.offset_top = 96
	_hint_label.offset_right = 1000
	_hint_label.offset_bottom = 124

	# 键盘之外再给一条明确的路。演示时对着老师按快捷键容易紧张，
	# 屏幕上有个按钮点一下就回去，比记快捷键可靠得多。
	_back_button = Button.new()
	_back_button.text = "← 返回编辑  (Esc)"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.pressed.connect(_on_escape)
	_game_hud.add_child(_back_button)
	_back_button.set_anchors_preset(Control.PRESET_TOP_RIGHT, false)
	_back_button.offset_left = -220
	_back_button.offset_top = 16
	_back_button.offset_right = -24
	_back_button.offset_bottom = 54

	_banner = _make_label(_hud, 40, Color.WHITE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.visible = false


func _make_label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	# HUD 不能吞掉输入，否则点击会被界面拦住、传不到运行器
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label


func _place(label: Label, x: float, y: float, w: float, h: float) -> void:
	label.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	label.offset_left = x
	label.offset_top = y
	label.offset_right = x + w
	label.offset_bottom = y + h


func _set_game_hud_visible(shown: bool) -> void:
	_game_hud.visible = shown


func _update_hud() -> void:
	if _runtime == null or not is_instance_valid(_runtime) or not _runtime.is_running():
		return
	_score_label.text = "分数 %s" % _format(_runtime.query_property("tag:player", "score"))
	_hp_label.text = "生命 %s" % _format(_runtime.query_property("tag:player", "hp"))


func _process(_delta: float) -> void:
	_update_hud()


static func _format(value: Variant) -> String:
	if value == null:
		return "-"
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	return str(value)


static func _first_errors(issues: Array) -> String:
	var lines: Array[String] = []
	for issue in issues:
		if issue.level == ProjectValidator.LEVEL_ERROR:
			lines.append("· " + issue.message)
		if lines.size() >= 3:
			break
	return "\n".join(lines)


func _show_banner(text: String, color: Color, font_size: int = 40) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.add_theme_font_size_override("font_size", font_size)
	_banner.visible = true


func _hide_banner() -> void:
	_banner.visible = false
