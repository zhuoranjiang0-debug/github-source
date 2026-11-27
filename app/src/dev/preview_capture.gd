## 开发工具：把画面截图存成 PNG。
##
## 做法是直接实例化正式的入口场景，因此截出来的就是用户真正看到的画面，
## 而不是另拼一份"看起来差不多"的演示场景 —— 后者迟早会和真实画面脱节。
##
## 用法（需要图形界面，不能在 --headless 下跑）：
##   Godot_v4.6.1-stable_win64.exe --path app res://scenes/capture.tscn -- \
##       --out=build/preview.png
##
## 可选参数：
##   --out=<路径>      存到哪里，默认 build/preview.png
##   --scene=<路径>    截哪个场景，默认正式入口 boot.tscn
##   --warmup=<帧数>   等多少帧再截，默认 110（让画面稳定下来）
##   --tap=<帧数>      在第几帧注入一次点击，默认 88；给 -1 表示不点击
##   --key=<帧>:<按键> 在第几帧注入一次按键，可重复，例如 --key=30:F5
##   --window=<宽>x<高> 强制窗口尺寸（用于复现"窗口被放大/最大化"时的表现）
##   --select-instance=<序号>@<帧> 在指定帧选中画布上的第 N 个对象，
##                               用来截取"选中某个对象"时的界面
##   --scale-selected=<横向>x<纵向>@<帧> 在指定帧把选中对象缩放成指定比例
##   --rule-mode@<帧>  在指定帧切到逻辑编辑器（截规则界面用）
##   --select-rule=<序号>@<帧> 在指定帧切到逻辑编辑器并选中第 N 条规则，
##                            用来截"某一条规则"的界面（序号从 0 数起）
##   --ai-prompt=<一句话>@<帧>  在指定帧切到 AI 界面，填入这句话并生成草稿
##   --ai-apply=<帧>            在指定帧把当前草稿应用到工程
##   --level-mode=<帧>          在指定帧切回关卡界面（AI/逻辑界面操作完再截画布用）
##   --select-type=<实体 id>@<帧> 在指定帧选中"这一类"（相当于点素材栏里的一项）
##
## 注意：参数**值里不要有空格**。从 PowerShell 用 Start-Process 调用时，
## 带空格的参数会被劈成两个，工具只收到前半截 —— 表现是"这一步好像没执行"。
## 踩过一次：`--ai-prompt=每 2 秒掉一个金币@70` 里的空格把参数拆开了，
## 结果截图里什么都没发生，白查了半天。
extends Node

const DEFAULT_SCENE := "res://scenes/boot.tscn"
const DEFAULT_WARMUP := 110
const DEFAULT_TAP := 88

var _scenes: Array[String] = []
var _warmup: int = DEFAULT_WARMUP
var _tap_frame: int = DEFAULT_TAP
var _out_path: String = ""
var _frames: int = 0
var _captured: bool = false
var _keys: Array[Dictionary] = []
var _force_window: Vector2i = Vector2i.ZERO
var _select_index: int = -1
var _select_frame: int = 0
var _scale_factor: Vector2 = Vector2.ZERO
var _scale_frame: int = 0
var _rule_mode_frame: int = -1
var _rule_index: int = -1
var _rule_frame: int = 0
var _ai_prompt: String = ""
var _ai_frame: int = 0
var _ai_apply_frame: int = -1
var _level_frame: int = -1
var _type_id: String = ""
var _type_frame: int = 0


func _ready() -> void:
	_parse_args()
	if _out_path.is_empty():
		_out_path = ProjectSettings.globalize_path("res://").path_join("../build/preview.png")
	for scene_path in _scenes:
		add_child(load(scene_path).instantiate())


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_path = arg.substr("--out=".length())
		elif arg.begins_with("--scene="):
			_scenes.append(arg.substr("--scene=".length()))
		elif arg.begins_with("--warmup="):
			_warmup = int(arg.substr("--warmup=".length()))
		elif arg.begins_with("--tap="):
			_tap_frame = int(arg.substr("--tap=".length()))
		elif arg.begins_with("--key="):
			var parts := arg.substr("--key=".length()).split(":")
			if parts.size() == 2:
				_keys.append({
					"frame": int(parts[0]),
					"keycode": OS.find_keycode_from_string(parts[1]),
				})
		elif arg.begins_with("--window="):
			var wh := arg.substr("--window=".length()).split("x")
			if wh.size() == 2:
				_force_window = Vector2i(int(wh[0]), int(wh[1]))
		elif arg.begins_with("--select-instance="):
			var spec := arg.substr("--select-instance=".length()).split("@")
			if spec.size() == 2:
				_select_index = int(spec[0])
				_select_frame = int(spec[1])
		elif arg.begins_with("--scale-selected="):
			var spec := arg.substr("--scale-selected=".length()).split("@")
			if spec.size() == 2:
				var factors := spec[0].split("x")
				if factors.size() == 2:
					_scale_factor = Vector2(float(factors[0]), float(factors[1]))
					_scale_frame = int(spec[1])
		elif arg.begins_with("--rule-mode@"):
			_rule_mode_frame = int(arg.substr("--rule-mode@".length()))
		elif arg.begins_with("--select-rule="):
			var spec := arg.substr("--select-rule=".length()).split("@")
			if spec.size() == 2:
				_rule_index = int(spec[0])
				_rule_frame = int(spec[1])
		elif arg.begins_with("--ai-prompt="):
			var spec := arg.substr("--ai-prompt=".length()).split("@")
			if spec.size() == 2:
				_ai_prompt = spec[0]
				_ai_frame = int(spec[1])
		elif arg.begins_with("--ai-apply="):
			_ai_apply_frame = int(arg.substr("--ai-apply=".length()))
		elif arg.begins_with("--level-mode="):
			_level_frame = int(arg.substr("--level-mode=".length()))
		elif arg.begins_with("--select-type="):
			var spec := arg.substr("--select-type=".length()).split("@")
			if spec.size() == 2:
				_type_id = spec[0]
				_type_frame = int(spec[1])
	if _scenes.is_empty():
		_scenes.append(DEFAULT_SCENE)


func _process(_delta: float) -> void:
	_frames += 1
	# 每帧都强制一次：被测场景会在启动时自己设窗口尺寸，这里要压住它
	if _force_window != Vector2i.ZERO and get_window().size != _force_window:
		get_window().size = _force_window
	if _tap_frame > 0 and _frames == _tap_frame:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = true
		touch.position = Vector2(640.0, 360.0)
		Input.parse_input_event(touch)
	for entry in _keys:
		if _frames == int(entry["frame"]):
			var key := InputEventKey.new()
			key.keycode = entry["keycode"]
			key.pressed = true
			Input.parse_input_event(key)
	if _select_index >= 0 and _frames == _select_frame:
		_select_instance(_select_index)
	if _scale_factor != Vector2.ZERO and _frames == _scale_frame:
		_scale_selected(_scale_factor)
	if _rule_mode_frame >= 0 and _frames == _rule_mode_frame:
		var editor := _find_editor(get_tree().root)
		if editor != null:
			editor._set_rule_mode(true)
	if _rule_index >= 0 and _frames == _rule_frame:
		_select_rule(_rule_index)
	if not _ai_prompt.is_empty() and _frames == _ai_frame:
		_ai_generate(_ai_prompt)
	if _ai_apply_frame >= 0 and _frames == _ai_apply_frame:
		var panel := _find_ai_panel(get_tree().root)
		if panel != null:
			panel.apply_current()
	if _level_frame >= 0 and _frames == _level_frame:
		var editor := _find_editor(get_tree().root)
		if editor != null:
			editor._set_rule_mode(false)
	if not _type_id.is_empty() and _frames == _type_frame:
		var editor := _find_editor(get_tree().root)
		if editor != null and editor.session != null:
			editor.session.select_entity(_type_id)
	if _frames >= _warmup and not _captured:
		_captured = true
		_capture()


func _capture() -> void:
	# 必须等本帧真正画完，否则拿到的是上一帧的内容
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()

	var dir := _out_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := image.save_png(_out_path)
	if err == OK:
		print("截图已保存：%s（%dx%d）" % [_out_path, image.get_width(), image.get_height()])
	else:
		push_error("截图保存失败：%s（错误码 %d）" % [_out_path, err])
	get_tree().quit(0 if err == OK else 1)


## 选中画布上的第 N 个对象。
##
## 这里直接改数据、不注入鼠标事件：注入的鼠标事件在部分显示后端下
## 到不了控件的 _gui_input，而本工具的目的只是"截一张选中状态的图"，
## 没必要为了这个去和输入管线较劲。真实的点击路径由自动化测试负责验证。
func _select_instance(index: int) -> void:
	var editor := _find_editor(get_tree().root)
	if editor == null:
		push_warning("没找到编辑器，无法选中对象")
		return
	var canvas := editor.canvas()
	if canvas == null or canvas.session == null:
		return
	var scene := canvas.session.current_scene()
	if scene == null or index >= scene.instances.size():
		push_warning("对象序号超出范围：%d" % index)
		return
	var placed := scene.instances[index]
	canvas.session.selected_instance_id = placed.instance_id
	canvas.session.changed.emit()


func _find_editor(node: Node) -> EditorScreen:
	if node is EditorScreen:
		return node
	for child in node.get_children():
		var found := _find_editor(child)
		if found != null:
			return found
	return null


func _scale_selected(factor: Vector2) -> void:
	var editor := _find_editor(get_tree().root)
	if editor == null:
		return
	var canvas := editor.canvas()
	if canvas == null or canvas.session == null:
		return
	var selected := canvas.session.selected_instance_id
	if selected.is_empty():
		push_warning("没有选中任何对象，无法缩放")
		return
	canvas.session.set_instance_scale(selected, factor.x, factor.y)


## 选中逻辑界面里的第 N 条规则（会顺带切到逻辑界面）。
## 和上面选对象一样，直接改数据而不是模拟点击：目的只是"截一张图"，
## 真实的点击路径由自动化测试负责验证。
func _select_rule(index: int) -> void:
	var editor := _find_editor(get_tree().root)
	if editor == null:
		push_warning("没找到编辑器，无法选中规则")
		return
	editor._set_rule_mode(true)
	var panel := editor.rule_editor()
	if panel == null or panel.session == null or panel.session.project == null:
		push_warning("逻辑界面还没准备好")
		return
	var rules := panel.session.project.rules
	if index < 0 or index >= rules.size():
		push_warning("规则序号超出范围：%d" % index)
		return
	panel._selected_rule_id = rules[index].id
	panel.rebuild()


func _find_ai_panel(node: Node) -> AIPanel:
	var editor := _find_editor(get_tree().root)
	return editor.ai_panel() if editor != null else null


## 切到 AI 界面，填入一句话并生成草稿（走的是用户真实点的那条路）
func _ai_generate(prompt: String) -> void:
	var editor := _find_editor(get_tree().root)
	if editor == null:
		push_warning("没找到编辑器，AI 面板用不了")
		return
	editor._set_ai_mode(true)
	var panel := editor.ai_panel()
	if panel == null:
		push_warning("没找到 AI 面板")
		return
	if panel.input_line() != null:
		panel.input_line().text = prompt
	panel.generate(prompt)
