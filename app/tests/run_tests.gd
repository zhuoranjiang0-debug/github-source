## 数据层自动化测试。以无界面方式运行：
##   godot --headless --path app --script res://tests/run_tests.gd
##
## 这一层刻意不依赖任何渲染或输入，因此可以在 CI 里快速跑。
extends SceneTree

const SAMPLE_PATH := "res://samples/demo-jump.ai2d.json"

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	# 告诉 app_main"现在在跑测试"：别去打开用户上一次的作品。
	# 这一条保证测试与"用户手边那份工程"无关 —— 少了它，
	# 用户在编辑器里多摆一个对象，这边就有测试开始报"对象数对不上"。
	ProjectSettings.set_setting("ai2d/headless_tests", true)
	# _run_all 是协程：运行器相关的用例需要等待真实的物理帧，
	# 因此整体在这里启动，结束时统一退出。
	_run_all()


func _run_all() -> void:
	_case("空工程创建")
	_test_empty_project()

	_case("JSON 往返：数值类型不漂移")
	_test_json_roundtrip_numbers()

	_case("模型往返：字段不丢失")
	_test_model_roundtrip()

	_case("示例工程加载并校验")
	_test_sample_project()

	_case("校验器能发现引用错误")
	_test_validator_catches_errors()

	_case("所有示例工程都能正常加载和校验")
	_test_all_samples_are_valid()

	_case("示例文件的文字编码体检")
	_test_sample_encoding()

	_case("批处理脚本必须是纯 ASCII")
	_test_batch_files_are_ascii()

	_case("编辑器会话：放、拖、删、撤销、存读闭环")
	_test_edit_session()

	_case("编辑器：每个对象自己的颜色、大小与自定义属性")
	_test_instance_properties()

	_case("词汇表：每种类型都配了复述模板")
	_test_vocabulary_completeness()

	_case("规则：编辑与自然语言复述")
	_test_rule_editing()

	_case("编辑器界面：素材栏与拖放接线")
	await _test_editor_screen()

	_case("编辑器界面：属性面板")
	await _test_inspector_panel()

	_case("编辑器界面：逻辑编辑器")
	await _test_rule_editor_ui()

	_case("AI 助手：离线生成、草稿预览、一步撤销")
	await _test_ai_assistant()

	_case("编辑器：把某个对象改成「会动」")
	await _test_instance_motion_override()

	_case("编辑器：配错规则时界面会提示")
	await _test_rule_warning_display()

	_case("工程文件：老工程自动升级")
	_test_project_upgrade()

	_case("编辑器界面：工程级提醒显示在状态栏")
	await _test_project_warning_bar()

	_case("编辑器：编辑「这一类」（类型面板）")
	await _test_type_panel()

	_case("编辑器界面：AI 面板")
	await _test_ai_panel_ui()

	_case("编辑器：触屏手势")
	await _test_touch_gestures()

	_case("编辑器：叠在一起时往下钻")
	await _test_overlap_drill_down()

	_case("编辑器：Delete 键删除对象")
	await _test_delete_key()

	_case("整体：编辑器与试玩模式的切换")
	await _test_mode_switch()

	_case("整体：试玩中按 Esc 回到编辑器")
	await _test_escape_returns_to_editor()

	_case("运行器：实例的颜色与缩放覆盖确实生效")
	await _test_runtime_instance_overrides()

	_case("运行器：屏幕按键")
	await _test_screen_buttons()

	_case("编辑器：按键绑定与复制")
	await _test_button_editing()

	_case("词汇表：屏幕按键的输入动作")
	_test_button_action_vocabulary()

	_case("词汇表：规则里的按键是可选项，不是手打")
	_test_rule_key_params()

	_case("规则引擎：带参数的事件要按参数过滤")
	await _test_trigger_filtering()

	_case("输入配置")
	_test_input_configuration()

	_case("运行器：背景色生效")
	await _test_runtime_background()

	_case("运行器：场景构建与落地")
	await _test_runtime_scene_build()

	_case("运行器：点击跳跃")
	await _test_runtime_jump()

	_case("运行器：吃金币加分并集齐获胜")
	await _test_runtime_collect_and_win()

	_case("运行器：碰到尖刺扣血")
	await _test_runtime_hazard()

	_case("运行器：真实输入事件链路")
	await _test_runtime_input_path()

	_case("运行器：按住方向键持续移动")
	await _test_runtime_movement()

	print("")
	print("通过 %d 项，失败 %d 项" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --------------------------------------------------------------------------
# 断言辅助
# --------------------------------------------------------------------------

func _case(name: String) -> void:
	_current = name
	print("── %s" % name)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("   ✓ %s" % what)
	else:
		_failed += 1
		print("   ✗ %s" % what)


func _check_eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual == expected:
		_passed += 1
		print("   ✓ %s" % what)
	else:
		_failed += 1
		print("   ✗ %s（期望 %s，实际 %s）" % [what, str(expected), str(actual)])


# --------------------------------------------------------------------------
# 用例
# --------------------------------------------------------------------------

func _test_empty_project() -> void:
	var p := ProjectIO.create_empty("测试工程")
	_check(not p.id.is_empty(), "自动生成了工程 ID")
	_check_eq(p.scenes.size(), 1, "默认带一个空场景")
	_check_eq(p.config.start_scene_id, p.scenes[0].id, "起始场景指向默认场景")

	# 新建的工程场景必然是空的，这只是提醒而非错误。
	var issues := ProjectValidator.validate(p)
	_check(not ProjectValidator.has_errors(issues), "新建工程没有错误级问题")
	_check_eq(issues.size(), 2, "新建工程只有两条提醒")
	var codes := {}
	for issue in issues:
		codes[issue.code] = true
	_check(codes.has("scene.no_instances"), "提醒之一是「场景里没有对象」")
	_check(codes.has("project.no_touch_controls"), "提醒之二是「没有屏幕按键，手机上没法操作」")


func _test_json_roundtrip_numbers() -> void:
	var p := ProjectIO.create_empty("数值测试")
	p.config.canvas_width = 1280
	p.config.gravity = 1600.0
	var text := ProjectIO.to_json_string(p, true)

	# 整数不能变成 1280.0，否则工程文件读起来会很难受，
	# 而且每次存盘都会产生无意义的 diff。
	_check(text.contains("\"width\": 1280"), "整数字段序列化为 1280 而非 1280.0")

	var loaded := ProjectIO.from_json_string(text)
	_check(loaded.ok, "重新解析成功")
	_check_eq(loaded.project.config.canvas_width, 1280, "整数字段读回后仍相等")
	_check(is_equal_approx(loaded.project.config.gravity, 1600.0), "浮点字段读回后相等")
	_check(typeof(loaded.project.config.canvas_width) == TYPE_INT, "画布宽度保持整数类型")


func _test_model_roundtrip() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	_check(loaded.ok, "示例工程读取成功：%s" % loaded.error)
	if not loaded.ok:
		return
	var project := loaded.project
	var dict_a := project.to_dict()
	var again := GameProject.from_dict(dict_a)
	var dict_b := again.to_dict()
	_check_eq(dict_b, dict_a, "序列化 → 反序列化 → 序列化 结果完全一致")

	_check_eq(project.entities.size(), 7, "读到 7 个实体定义（含 3 个屏幕按键）")
	_check_eq(project.scenes.size(), 1, "读到 1 个场景")
	_check_eq(project.rules.size(), 11, "读到 11 条规则")
	_check(project.find_entity("ent_player") != null, "能按 ID 找到玩家实体")
	_check(project.find_entity("ent_nope") == null, "查不存在的实体返回 null")
	_check(project.start_scene() != null, "能取到起始场景")
	_check_eq(project.entities_with_tag("coin").size(), 1, "按标签查到金币实体")
	_check(project.find_entity("ent_player").has_tag("player"), "标签查询正确")


func _test_sample_project() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	if not loaded.ok:
		_check(false, "示例工程读取失败：%s" % loaded.error)
		return
	var issues := ProjectValidator.validate(loaded.project)
	if not issues.is_empty():
		print(ProjectValidator.format_all(issues))
	_check(not ProjectValidator.has_errors(issues), "示例工程没有错误级问题")
	_check(issues.is_empty(), "示例工程完全干净，没有警告")


func _test_validator_catches_errors() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	if not loaded.ok:
		_check(false, "示例工程读取失败")
		return
	var p := loaded.project

	p.scenes[0].instances[0].entity_id = "ent_not_exist"
	p.rules[0].trigger = {"type": "no_such_trigger"}
	p.rules[1].actions.append({"type": "no_such_action"})
	p.entities[0].asset_id = "asset_not_exist"

	var issues := ProjectValidator.validate(p)
	var codes := {}
	for i in issues:
		codes[i.code] = true

	_check(codes.has("instance.entity_missing"), "发现「实例引用了不存在的实体」")
	_check(codes.has("rule.trigger_unknown"), "发现「未知事件类型」")
	_check(codes.has("rule.action_unknown"), "发现「未知动作类型」")
	_check(codes.has("entity.asset_missing"), "发现「实体引用了不存在的素材」")
	_check(ProjectValidator.has_errors(issues), "整体判定为有错误")


# --------------------------------------------------------------------------
# 运行器用例
# --------------------------------------------------------------------------

var _last_result := ""
var _last_message := ""


## 示例工程是用户上手时的第一印象，写坏一份就全盘皆输。
## 这里把 samples 目录下的每一份都过一遍，以后新增示例会自动被覆盖到。
func _test_all_samples_are_valid() -> void:
	var dir := DirAccess.open("res://samples")
	if dir == null:
		_check(false, "能打开 samples 目录")
		return

	var found: Array[String] = []
	for entry in dir.get_files():
		if entry.ends_with(".ai2d.json"):
			found.append(entry)

	_check(found.size() >= 2, "找到 %d 个示例工程" % found.size())
	for entry in found:
		var result := ProjectIO.load_from_file("res://samples/".path_join(entry))
		if not result.ok:
			_check(false, "%s 能读进来（%s）" % [entry, result.error])
			continue
		var issues := ProjectValidator.validate(result.project)
		if not issues.is_empty():
			print("      " + ProjectValidator.format_all(issues).replace("\n", "\n      "))
		_check(not ProjectValidator.has_errors(issues), "%s 没有错误" % entry)


## 编码体检：确保示例文件里没有非法字节、也没有乱码替换字符。
##
## 这条测试来自一次真实事故——在编辑器里改完保存时用错了编码，
## 个别汉字变成乱码，但 JSON 结构仍然合法，程序照跑不误，
## 只有游戏里的文字悄悄变了样。靠肉眼基本发现不了，必须让机器盯着。
func _test_sample_encoding() -> void:
	var dir := DirAccess.open("res://samples")
	if dir == null:
		_check(false, "能打开 samples 目录")
		return

	var count := 0
	for entry in dir.get_files():
		if not entry.ends_with(".ai2d.json"):
			continue
		count += 1
		var bytes := FileAccess.get_file_as_bytes("res://samples/".path_join(entry))

		var bad := TextEncoding.first_invalid_offset(bytes)
		if bad < 0:
			_check(true, "%s 是合法的 UTF-8" % entry)
		else:
			_check(false, "%s 在第 %d 行有非法字节，文件被非 UTF-8 编辑器写坏了"
				% [entry, TextEncoding.byte_offset_to_line(bytes, bad)])

		_check(not TextEncoding.contains_replacement_char(bytes),
			"%s 不含乱码替换字符" % entry)

	_check(count >= 2, "体检覆盖了 %d 个示例文件" % count)


## 批处理脚本必须是纯 ASCII。
##
## cmd.exe 读 .bat 用的是系统 OEM 代码页（中文 Windows 上是 GBK），
## 文件里写 UTF-8 中文会被当成乱码：轻则显示成鬼画符，
## 重则把某一行的引号吃掉、整个脚本崩掉。
##
## 这条检查来自真实教训 —— 我在注释里写了中文文件名，犯了三次。
func _test_batch_files_are_ascii() -> void:
	var repo_root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var dir := DirAccess.open(repo_root)
	if dir == null:
		_check(false, "能打开仓库根目录（%s）" % repo_root)
		return

	var checked := 0
	for entry in dir.get_files():
		if not entry.ends_with(".bat"):
			continue
		checked += 1
		var bytes := FileAccess.get_file_as_bytes(repo_root.path_join(entry))
		var bad := 0
		for byte in bytes:
			if byte > 127:
				bad += 1
		_check(bad == 0, "%s 是纯 ASCII（发现 %d 个非 ASCII 字节）" % [entry, bad])
	_check(checked >= 4, "检查了 %d 个批处理脚本" % checked)


# --------------------------------------------------------------------------
# 编辑器会话
# --------------------------------------------------------------------------

func _test_edit_session() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var before := session.current_scene().instances.size()
	_check_eq(before, 16, "示例场景里有 16 个对象（13 个游戏对象 + 3 个屏幕按键）")

	# 放进一个对象
	var placed := session.add_instance("ent_coin", Vector2(700, 200))
	_check(placed != null, "能把金币放进场景")
	_check_eq(session.current_scene().instances.size(), before + 1, "场景对象数加一")
	_check(session.dirty, "放置后有未保存改动")
	_check_eq(session.selected_instance_id, placed.instance_id, "放置后自动选中新对象")

	# 点选
	_check_eq(session.instance_at(Vector2(700, 200)), placed.instance_id, "点在对象上能选中它")
	_check_eq(session.instance_at(Vector2(5, 5)), "", "点空白处不会误选中")

	# 后放的对象在上层，重叠时应选中后放的那个
	var stacked := session.add_instance("ent_coin", Vector2(700, 200))
	_check_eq(session.instance_at(Vector2(700, 200)), stacked.instance_id, "重叠时选中上层对象")
	session.remove_instance(stacked.instance_id)

	# 拖动
	session.push_undo("移动对象")
	session.move_instance(placed.instance_id, Vector2(800, 300))
	var moved := session.find_instance(placed.instance_id)
	_check_eq(Vector2(moved.x, moved.y), Vector2(800, 300), "拖动后位置更新")

	# 撤销 / 重做
	_check(session.can_undo(), "可以撤销")
	session.undo()
	var after_undo := session.find_instance(placed.instance_id)
	_check(after_undo != null and is_equal_approx(after_undo.x, 700.0), "撤销把位置退回去了")
	_check(session.can_redo(), "可以重做")
	session.redo()
	var after_redo := session.find_instance(placed.instance_id)
	_check(after_redo != null and is_equal_approx(after_redo.x, 800.0), "重做把位置又恢复了")

	# 一路撤销到底，应该完全回到刚打开工程时的样子
	var guard := 0
	while session.can_undo() and guard < 100:
		session.undo()
		guard += 1
	_check_eq(session.current_scene().instances.size(), before, "一路撤销能回到刚打开时的状态")
	_check_eq(session.find_instance(placed.instance_id), null, "一路撤销后新放的对象都不在了")

	# 删除
	var again := session.add_instance("ent_coin", Vector2(400, 300))
	_check(session.remove_instance(again.instance_id), "能删除对象")
	_check_eq(session.current_scene().instances.size(), before, "删除后对象数恢复")

	# 存盘再读回来 —— 这是「能存」的验收标准
	var out := OS.get_temp_dir().path_join("ai2d_edit_roundtrip.ai2d.json")
	_check(session.save(out), "能保存到文件（%s）" % session.last_error)
	_check(not session.dirty, "保存后未保存标记被清掉")

	var reopened := EditSession.new()
	_check(reopened.open(out), "保存出来的文件能重新打开")
	if reopened.project != null:
		_check_eq(reopened.current_scene().instances.size(), before, "读回来的内容与保存前一致")
		_check(not reopened.dirty, "刚打开的工程没有未保存改动")
		_check(not ProjectValidator.has_errors(ProjectValidator.validate(reopened.project)),
			"保存出来的文件仍然通过校验")
	DirAccess.remove_absolute(out)

	# 打不开的文件要给得出原因
	var bad := EditSession.new()
	_check(not bad.open("res://samples/不存在的工程.ai2d.json"), "打不开的文件会明确失败")
	_check(not bad.last_error.is_empty(), "失败时给出了原因：%s" % bad.last_error)

	# 内置示例是只读的：对示例按保存，不能覆盖它，要另存到别处。
	# 这条来自一次真实事故——用户在编辑器里改示例后按了 Ctrl+S，
	# 直接把示例文件覆盖了，而后面的自动化测试才发现对象数量不对。
	var sample := EditSession.new()
	_check(sample.open(SAMPLE_PATH), "能打开内置示例")
	_check(sample.is_bundled_sample(), "能识别出打开的是内置示例")

	var copy_path := OS.get_temp_dir().path_join("ai2d_sample_copy.ai2d.json")
	_check_eq(sample.save_project(copy_path), copy_path, "对示例按保存会改写到别的位置")
	_check(FileAccess.file_exists(copy_path), "副本文件确实生成了")

	var untouched := ProjectIO.load_from_file(SAMPLE_PATH)
	_check(untouched.ok and untouched.project.scenes[0].instances.size() == 16,
		"内置示例本身一个字节都没被动过")
	DirAccess.remove_absolute(copy_path)


## 颜色原本只存在实体定义（类型）上，改一次所有同类对象一起变。
## 这里验证「每个对象有自己的颜色」，以及缩放真的能改。
func _test_instance_properties() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var coins: Array[PlacedEntity] = []
	for placed in session.current_scene().instances:
		if placed.entity_id == "ent_coin":
			coins.append(placed)
	_check_eq(coins.size(), 5, "场景里有 5 枚金币")
	if coins.size() < 2:
		return

	var first := coins[0]
	var second := coins[1]
	var original := session.effective_color(first)
	_check_eq(session.effective_color(second), original, "默认情况下两个金币同色")

	session.set_instance_color(first.instance_id, "#ff0000")
	_check_eq(session.effective_color(first), Color("#ff0000"), "改颜色只影响这一个对象")
	_check_eq(session.effective_color(second), original, "同类型的另一枚金币颜色不变")

	session.set_instance_color(first.instance_id, "")
	_check_eq(session.effective_color(first), original, "清空颜色后恢复跟随类型")

	session.set_instance_scale(first.instance_id, 2.0, 1.5)
	_check_eq(Vector2(first.scale_x, first.scale_y), Vector2(2.0, 1.5), "能改大小")

	# 金币半径 22。横向拉成两倍后形状是椭圆（横向 44、纵向 22），
	# 点选判定必须跟着变，否则它看着很宽却只能在原来那一小块里点得中。
	session.set_instance_scale(first.instance_id, 2.0, 1.0)
	_check_eq(session.instance_at(Vector2(first.x + 35.0, first.y)), first.instance_id,
		"横向拉宽后，右侧 35 像素处仍能点中")
	# 往上方探：下方现在是屏幕按键的地盘，不能用那儿验证
	_check_eq(session.instance_at(Vector2(first.x, first.y - 35.0)), "",
		"纵向没变，上方 35 像素处点不中")
	session.set_instance_scale(first.instance_id, 1.0, 1.0)

	session.set_instance_property(first.instance_id, "score", 5)
	_check_eq(first.properties.get("score"), 5, "能新增自定义属性")
	session.set_instance_property(first.instance_id, "score", 9)
	_check_eq(first.properties.get("score"), 9, "能改属性值")
	_check(session.rename_instance_property(first.instance_id, "score", "points"), "能改属性名")
	_check_eq(first.properties.get("points"), 9, "改名后值跟着走")
	_check(not first.properties.has("score"), "旧名字不再存在")
	session.set_instance_property(first.instance_id, "score", 5)
	_check(not session.rename_instance_property(first.instance_id, "points", "score"),
		"目标名字已被占用时拒绝改名")
	session.remove_instance_property(first.instance_id, "points")
	_check(not first.properties.has("points"), "能删属性")
	session.remove_instance_property(first.instance_id, "score")

	# 改完要能存下来、读回来
	session.set_instance_color(first.instance_id, "#ff0000")
	session.set_instance_scale(first.instance_id, 2.0, 1.5)
	session.set_instance_property(first.instance_id, "score", 9)
	var out := OS.get_temp_dir().path_join("ai2d_instance_props.ai2d.json")
	_check(session.save(out), "能保存（%s）" % session.last_error)

	var reopened := EditSession.new()
	_check(reopened.open(out), "保存后的文件能重新打开")
	var again := reopened.find_instance(first.instance_id)
	_check(again != null, "能找回那个对象")
	if again != null:
		_check_eq(again.color, "#ff0000", "颜色存下来了")
		_check_eq(Vector2(again.scale_x, again.scale_y), Vector2(2.0, 1.5), "大小存下来了")
		_check_eq(again.properties.get("score"), 9, "自定义属性存下来了")
	DirAccess.remove_absolute(out)


func _find_direct_collision_shape(node: Node) -> CollisionShape2D:
	for child in node.get_children():
		if child is CollisionShape2D:
			return child
	return null


## 测试环境里没法用 Input.parse_input_event 把触摸送进节点
## （和之前注入鼠标事件遇到的是同一个限制），所以直接调用处理函数。
## 真实投递由真机验证 —— 用户实测"按住半边屏幕移动会跳一下"，
## 恰恰证明真机上触摸是能送到的。
## 按键既然是给创作者用的，就必须能被创作者改。
## 这一条验证：能改单个按键的绑定（不影响同类）、能复制出新的按键。
func _test_button_editing() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var button := session.find_instance("i_btn_left")
	_check(button != null, "找到左键")
	if button == null:
		return
	_check_eq(session.effective_button_action(button), "ui_left",
		"默认跟随实体定义绑定的动作")

	# 改这一个按键：绑到 ui_up
	session.set_instance_button_action(button.instance_id, "ui_up")
	_check_eq(session.effective_button_action(button), "ui_up", "能改这一个按键的绑定")
	var other := session.find_instance("i_btn_right")
	_check_eq(session.effective_button_action(other), "ui_right",
		"同类型的另一个按键不受影响")

	# 清空就恢复跟随类型
	session.set_instance_button_action(button.instance_id, "")
	_check_eq(session.effective_button_action(button), "ui_left", "清空后恢复跟随类型")

	# 复制一个按键出来
	var before := session.current_scene().instances.size()
	var copy := session.duplicate_instance(button.instance_id, Vector2(60, 60))
	_check(copy != null, "能复制出一个新按键")
	_check_eq(session.current_scene().instances.size(), before + 1, "场景里多了一个对象")
	_check_eq(session.selected_instance_id, copy.instance_id, "复制出来的自动被选中")
	if copy != null:
		session.set_instance_button_action(copy.instance_id, "ui_down")
		_check_eq(session.effective_button_action(copy), "ui_down",
			"复制出来的可以单独改绑定")
		_check_eq(session.effective_button_action(button), "ui_left",
			"原键的绑定不受影响")

	# 运行器要用改过之后的绑定
	var rt := GameRuntime.new()
	rt.setup(session.project)
	root.add_child(rt)
	rt.start()
	await process_frame
	_check(rt.button_actions().has("ui_down"), "运行器用的是改过之后的绑定")
	_check_eq(rt.button_actions().size(), 4, "复制之后场景里有 4 个按键")

	# 按键上写什么，要跟着**绑定的动作**走。
	# 复制出来的那个已经改成 ui_down：它必须画向下的箭头，
	# 而不是继续写着"左" —— 屏幕上写字、按下去干别的事，用户会以为程序坏了。
	var actions := rt.button_actions()
	var labels := rt.button_labels()
	var arrows := rt.button_arrows()
	for i in actions.size():
		if actions[i] == "ui_down":
			_check_eq(arrows[i], "down", "绑成往下走的按键画的是向下箭头")
		elif actions[i] == "ui_accept":
			_check_eq(labels[i], "跳", "跳跃键上写的是「跳」")
			_check_eq(arrows[i], "", "跳跃键不画箭头，写名字")
		elif actions[i] == "ui_left":
			_check_eq(arrows[i], "left", "左键画的是向左箭头")

	rt.stop()
	root.remove_child(rt)
	rt.queue_free()
	await process_frame


## 屏幕按键做成"用户自己编辑"之后，动作表就成了界面和运行器共用的那份真相。
## 这里锁死几件事：表里的动作都有给人看的名字、示例里用到的动作都在表里。
func _test_button_action_vocabulary() -> void:
	var ids := RuleVocabulary.button_action_ids()
	_check(ids.size() >= 7, "常用输入动作有 7 个")
	_check(ids.has("ui_left") and ids.has("ui_accept"), "里面既有方向也有跳跃")

	for id in ids:
		_check(not RuleVocabulary.button_action_label(id).is_empty(),
			"「%s」有写在按键上的短名字" % id)
		_check(not RuleVocabulary.button_action_menu(id).is_empty(),
			"「%s」有下拉框里给人看的说明" % id)

	_check_eq(RuleVocabulary.button_action_arrow("ui_left"), "left", "左是向左的箭头")
	_check_eq(RuleVocabulary.button_action_arrow("ui_down"), "down", "下是向下的箭头")
	_check_eq(RuleVocabulary.button_action_arrow("ui_accept"), "", "跳跃键不画箭头")
	_check_eq(RuleVocabulary.button_action_label("ui_accept"), "跳",
		"跳跃键在按键上写「跳」")

	# 手改 JSON 绑了个表里没有的动作：名字给不出来（运行器退回实体名），
	# 但下拉框要把 id 原样显示出来，别让人以为没绑上。
	_check_eq(RuleVocabulary.button_action_label("dash"), "", "表外的动作给不出短名字")
	_check_eq(RuleVocabulary.button_action_menu("dash"), "dash",
		"表外的动作在下拉框里显示 id 本身")

	# 示例工程里每个按键绑的动作都得在表里，否则用户一打开属性面板
	# 看到的是一串英文 id，等于告诉他"这个键你改不了"。
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	_check(loaded.ok, "示例工程读取成功")
	if not loaded.ok:
		return
	var known := ids
	for def in loaded.project.entities:
		if def.is_button():
			_check(known.has(def.button_action),
				"示例里的按键「%s」绑的动作在常用表里" % def.name)


## 规则里引用"按住哪个键"时，以前是一个空输入框，得手打 ui_accept。
## 两个毛病：看不出那是哪个键；填错了没有任何提示（校验器只管语句类型和
## 对象选择器，不管这个参数存不存在），规则只是永远不成立。
##
## 这一条锁死"它现在是可选项"，并且锁住面板和规则说的是同一套话。
func _test_rule_key_params() -> void:
	var held: Dictionary = RuleVocabulary.condition_def("key_held")
	var held_spec: Dictionary = held.get("params", {}).get("key", {})
	_check_eq(String(held_spec.get("type", "")), "enum",
		"「按住按键」给的是可选项，不是手打输入框")

	var options: Array = held_spec.get("options", [])
	var labels: Dictionary = held_spec.get("option_labels", {})
	_check_eq(options.size(), RuleVocabulary.ACTION_PARAM_OPTIONS.size(),
		"可选的动作数量和共享表一致")
	for option in options:
		_check(labels.has(String(option)), "「%s」有给人看的说法" % option)

	# 同一个动作在三个地方出现：按键属性面板的下拉、规则里的下拉、
	# 规则念出来的句子。名字只写一处，漂了这里立刻报出来。
	for action in RuleVocabulary.BUTTON_ACTIONS:
		_check(options.has(String(action)),
			"屏幕按键能绑的「%s」在规则里也能选" % action)
		_check_eq(RuleVocabulary.button_action_menu(String(action)),
			String(labels.get(String(action), "")),
			"「%s」在按键面板和规则里叫同一个名字" % action)

	# 键盘那一张表是另一回事，但同样不该手打
	var press: Dictionary = RuleVocabulary.trigger_def("key_press")
	var press_spec: Dictionary = press.get("params", {}).get("key", {})
	var press_options: Array = press_spec.get("options", [])
	_check_eq(String(press_spec.get("type", "")), "enum",
		"「按下按键时」给的也是可选项")
	_check(press_options.has("Space"), "可选里有空格键")

	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	_check(loaded.ok, "示例工程读取成功")
	if not loaded.ok:
		return
	var project := loaded.project

	# 示例里正在用的值必须在可选项里，否则面板上会显示成
	# "当前值：xxx（其他选项里没有）"，等于告诉用户"这个你改不了"
	for rule in project.rules:
		for condition in rule.conditions:
			if String(condition.get("type", "")) == "key_held":
				_check(options.has(String(condition.get("key", ""))),
					"示例规则「%s」引用的按键在可选项里" % rule.name)
		if String(rule.trigger.get("type", "")) == "key_press":
			_check(press_options.has(String(rule.trigger.get("key", ""))),
				"示例规则「%s」盯的键盘键在可选项里" % rule.name)

	# 句子也要跟着变人话：以前读"正按住「ui_left」"，现在读"正按住「往左走」"
	var move_rule: RuleDef = null
	var jump_rule: RuleDef = null
	for rule in project.rules:
		if rule.id == "rule_move_left":
			move_rule = rule
		elif rule.id == "rule_jump_key":
			jump_rule = rule

	_check(move_rule != null, "找得到向左移动的规则")
	if move_rule != null:
		var text := RuleVocabulary.describe(move_rule, project)
		print("   " + text)
		_check(text.contains("往左走") and not text.contains("ui_left"),
			"句子里念的是人话，不再是 ui_left")

	if jump_rule != null:
		var text := RuleVocabulary.describe(jump_rule, project)
		print("   " + text)
		_check(text.contains("空格"), "键盘那一条念的是「空格」")

	# 带「反向」的条件，句子必须念成反面。
	# 以前不念，于是「松开方向键就停下」读出来是"正按住左、正按住右"，
	# 跟它实际干的事正好相反 —— 这种"看着相反"的规则比看不懂更糟。
	var stop_rule: RuleDef = null
	for rule in project.rules:
		if rule.id == "rule_move_stop":
			stop_rule = rule
	_check(stop_rule != null, "找得到「松开方向键就停下」")
	if stop_rule != null:
		var text := RuleVocabulary.describe(stop_rule, project)
		print("   " + text)
		_check(text.contains("没有按住"),
			"反向的条件念成「没有按住」，不是「正按住」")

	# 手改 JSON 填了个表外的值：不该崩，也不该被悄悄改掉，
	# 界面会补一项"当前值：xxx"让它显示出来
	_check_eq(RuleVocabulary.render_param(
		RuleVocabulary.condition_def("key_held"), "key", "Key9", project), "Key9",
		"表外的值原样显示，不会崩")


func _touch_to(rt: GameRuntime, pos: Vector2, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	rt._unhandled_input(event)


## 屏幕按键要解决的是用户实测报出来的那件事：
## 在平板上按住左半边移动，小恐龙会先跳一下。
##
## 根子是同一个触摸动作承载了两种含义。按键把边界划清楚：
## 手指落在按键上就是按那个键，不再算"点击屏幕"。
func _test_screen_buttons() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	_check(loaded.ok, "示例工程读取成功")
	if not loaded.ok:
		return

	var rt := GameRuntime.new()
	rt.setup(loaded.project)
	root.add_child(rt)
	rt.start()

	var actions := rt.button_actions()
	_check_eq(actions.size(), 3, "场景里有 3 个屏幕按键")
	_check(actions.has("ui_left") and actions.has("ui_right") and actions.has("ui_accept"),
		"三个按键分别绑到 左 / 右 / 跳")
	_check_eq(rt.alive_count(), 13, "屏幕按键不算游戏对象，世界对象仍是 13 个")

	# 先让玩家落地
	for i in 60:
		await physics_frame
	var player := rt.actor_by_instance("i_player") as Actor
	_check(player != null and player.is_grounded(), "玩家已经站在地面上")

	var rects := rt.button_rects()
	var left_center := Vector2.ZERO
	var jump_center := Vector2.ZERO
	for i in actions.size():
		if actions[i] == "ui_left":
			left_center = rects[i].get_center()
		elif actions[i] == "ui_accept":
			jump_center = rects[i].get_center()
	_check(left_center != Vector2.ZERO, "能算出左键在屏幕上的中心位置")
	_check(jump_center != Vector2.ZERO, "能算出跳跃键在屏幕上的中心位置")

	# 跳跃键：按住它，小恐龙要真的跳起来。
	# 这是用户在平板上实测报出来的问题——按键做出来了，但没有规则认它，
	# 于是屏幕上按了没反应。示例里补了一条
	# 「每一帧 + 正按住跳跃 + 站在地上 → 跳起来」，这里盯着它别退化。
	_touch_to(rt, jump_center, true, 1)
	await physics_frame
	_check(Input.is_action_pressed("ui_accept"), "手指按在跳跃键上，等于按住了 ui_accept")
	for i in 4:
		await physics_frame
	_check(player.velocity.y < -50.0, "按住跳跃键，小恐龙真的往上跳了")

	_touch_to(rt, jump_center, false, 1)
	await physics_frame
	_check(not Input.is_action_pressed("ui_accept"), "松开跳跃键，ui_accept 也跟着松开")

	# 等它落回地面，后面测左右移动时才有一个干净的起点
	for i in 90:
		await physics_frame
	_check(player.is_grounded(), "跳完能落回地面")

	_touch_to(rt, left_center, true, 0)
	await physics_frame
	_check(Input.is_action_pressed("ui_left"), "手指按在左键上，等于按住了 ui_left")

	for i in 20:
		await physics_frame
	_check(player.velocity.x < -100.0, "按住左键，玩家真的向左移动了")
	_check(player.velocity.y > -100.0, "而且没有跳起来 —— 按键吞掉了这次触摸")

	_touch_to(rt, left_center, false, 0)
	await physics_frame
	_check(not Input.is_action_pressed("ui_left"), "松开手指，ui_left 也跟着松开")

	rt.stop()
	root.remove_child(rt)
	rt.queue_free()
	await process_frame


## 一条「按下 E 键就加分」的规则，不能在按 Q 的时候也触发。
## 这类"乱触发"用户一眼就看得出来，但在代码里毫无异样。
func _test_trigger_filtering() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	if not loaded.ok:
		_check(false, "示例工程读取失败")
		return
	var project := loaded.project
	var player: EntityDef = project.find_entity("ent_player")

	# 清空示例规则，只留我们这一条，免得互相干扰
	project.rules = []
	var rule := RuleDef.new()
	rule.id = "test_key"
	rule.name = "按 E 加分"
	rule.trigger = {"type": "key_press", "key": "E"}
	rule.actions = [{"type": "change_property", "target": "tag:player",
		"property": "score", "delta": 10}]
	project.rules.append(rule)

	var rt := GameRuntime.new()
	rt.setup(project)
	root.add_child(rt)
	rt.start()
	await process_frame

	_check_eq(rt.query_property("tag:player", "score"), 0, "开局分数是 0")

	rt.engine_emit("key_press", {"key": "Q"})
	_check_eq(rt.query_property("tag:player", "score"), 0, "按 Q 不会触发（规则指定的是 E）")

	rt.engine_emit("key_press", {"key": "E"})
	_check_eq(rt.query_property("tag:player", "score"), 10, "按 E 才触发")

	rt.stop()
	root.remove_child(rt)
	rt.queue_free()
	await process_frame

	# 销毁事件同理：指定监视金币，就不该被别的东西消失触发
	project.rules = []
	var watched := RuleDef.new()
	watched.id = "test_destroy"
	watched.name = "金币消失时加分"
	watched.trigger = {"type": "entity_destroyed", "target": "tag:coin"}
	watched.actions = [{"type": "change_property", "target": "tag:player",
		"property": "score", "delta": 5}]
	project.rules.append(watched)

	var rt2 := GameRuntime.new()
	rt2.setup(project)
	root.add_child(rt2)
	rt2.start()
	await process_frame

	var spike: Actor = rt2.actor_by_instance("i_spike_1")
	rt2.destroy_actor(spike)
	_check_eq(rt2.query_property("tag:player", "score"), 0, "尖刺消失不会触发（规则只盯金币）")

	var coin: Actor = rt2.actor_by_instance("i_coin_1")
	rt2.destroy_actor(coin)
	_check_eq(rt2.query_property("tag:player", "score"), 5, "金币消失才触发")

	rt2.stop()
	root.remove_child(rt2)
	rt2.queue_free()
	await process_frame


## 词汇表和复述模板是两张表，必须一一对应。
## 以后新增一种动作却忘了补模板，这条测试会立刻报出来。
func _test_vocabulary_completeness() -> void:
	var missing: Array[String] = []
	for type in RuleVocabulary.TRIGGERS:
		if not RuleVocabulary.TRIGGER_PHRASES.has(type):
			missing.append(type)
	_check(missing.is_empty(), "每个事件都有复述模板（缺 %s）" % str(missing))

	missing = []
	for type in RuleVocabulary.CONDITIONS:
		if not RuleVocabulary.CONDITION_PHRASES.has(type):
			missing.append(type)
	_check(missing.is_empty(), "每个条件都有复述模板（缺 %s）" % str(missing))

	missing = []
	for type in RuleVocabulary.ACTIONS:
		if not RuleVocabulary.ACTION_PHRASES.has(type):
			missing.append(type)
	_check(missing.is_empty(), "每个动作都有复述模板（缺 %s）" % str(missing))

	# 勾了「反向」之后怎么念：每种条件都要有反面说法。
	# compare 除外 —— 它靠把运算符翻过来念（「>= 0」→「< 0」），不需要模板。
	missing = []
	for type in RuleVocabulary.CONDITIONS:
		if type == "compare":
			continue
		if not RuleVocabulary.CONDITION_NEGATED_PHRASES.has(type):
			missing.append(type)
	_check(missing.is_empty(), "每种条件都有「反向」时的念法（缺 %s）" % str(missing))

	missing = []
	for type in RuleVocabulary.CONDITION_NEGATED_PHRASES:
		if not RuleVocabulary.CONDITIONS.has(type):
			missing.append(type)
	_check(missing.is_empty(), "反向念法里没有多余的类型（多出 %s）" % str(missing))

	# 反过来也要查：模板表里不能留着已经不存在的类型
	missing = []
	for type in RuleVocabulary.TRIGGER_PHRASES:
		if not RuleVocabulary.TRIGGERS.has(type):
			missing.append(type)
	for type in RuleVocabulary.CONDITION_PHRASES:
		if not RuleVocabulary.CONDITIONS.has(type):
			missing.append(type)
	for type in RuleVocabulary.ACTION_PHRASES:
		if not RuleVocabulary.ACTIONS.has(type):
			missing.append(type)
	_check(missing.is_empty(), "复述模板里没有多余的、已经不存在的类型（多出 %s）" % str(missing))


## 规则能不能被念成人话，直接决定用户看不看得懂自己配了什么。
func _test_rule_editing() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	if not loaded.ok:
		_check(false, "示例工程读取失败")
		return
	var project := loaded.project

	var rule_jump: RuleDef = null
	var rule_coin: RuleDef = null
	for rule in project.rules:
		if rule.id == "rule_jump":
			rule_jump = rule
		elif rule.id == "rule_coin":
			rule_coin = rule

	_check(rule_jump != null, "找得到跳跃规则")
	if rule_jump != null:
		var text := RuleVocabulary.describe(rule_jump, project)
		print("   " + text)
		_check_eq(text, "当点击屏幕时，如果「小恐龙」站在地上，就让「小恐龙」跳起来（高度 190）",
			"跳跃规则能念成一句完整的话")

	_check(rule_coin != null, "找得到金币规则")
	if rule_coin != null:
		var text := RuleVocabulary.describe(rule_coin, project)
		print("   " + text)
		_check_eq(text, "当「小恐龙」碰到「金币」时，就把「小恐龙」的「score」增减 1，删除对方",
			"金币规则能念成一句完整的话")

	# 数字不该带着 190.0 这种没意义的小数尾巴
	_check_eq(RuleVocabulary.format_number(190.0), "190", "整数不显示小数尾巴")
	_check_eq(RuleVocabulary.format_number(1.5), "1.5", "真小数照常显示")

	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "编辑器能打开示例工程")
	if session.project == null:
		return

	var before := session.project.rules.size()
	var rule := session.add_rule()
	_check(rule != null, "能新建规则")
	_check_eq(session.project.rules.size(), before + 1, "规则数量加一")
	_check_eq(String(rule.trigger.get("type", "")), EditSession.DEFAULT_TRIGGER, "新规则有默认事件")
	_check(rule.actions.is_empty(), "新规则还没有动作")

	# 换事件类型：旧参数必须被清掉，不能留下看不见的垃圾
	session.set_rule_trigger_param(rule.id, "interval", 3.0)
	session.set_rule_trigger_type(rule.id, "timer")
	_check_eq(String(rule.trigger.get("type", "")), "timer", "事件换成了定时")
	_check_eq(rule.trigger.get("interval"), 1.0, "换事件后参数重置为该事件的默认值")
	_check(not rule.trigger.has("key"), "没有残留旧事件的参数")

	session.set_rule_trigger_type(rule.id, "collision")
	session.set_rule_trigger_param(rule.id, "a", "tag:player")
	session.set_rule_trigger_param(rule.id, "b", "tag:coin")
	_check_eq(String(rule.trigger.get("a", "")), "tag:player", "能改事件参数")

	var condition_index := session.add_rule_condition(rule.id, "grounded")
	_check_eq(condition_index, 0, "能加条件")
	_check_eq(String(rule.conditions[0].get("target", "")), "self", "条件参数有默认值")
	session.set_rule_condition_param(rule.id, 0, "target", "tag:player")
	_check_eq(String(rule.conditions[0].get("target", "")), "tag:player", "能改条件参数")

	var action_index := session.add_rule_action(rule.id, "change_property")
	_check_eq(action_index, 0, "能加动作")
	session.set_rule_action_param(rule.id, 0, "property", "score")
	session.set_rule_action_param(rule.id, 0, "delta", 2)
	_check_eq(rule.actions[0].get("delta"), 2, "能改动作参数")

	var sentence := RuleVocabulary.describe(rule, session.project)
	print("   " + sentence)
	_check(sentence.contains("score") and sentence.contains("增减 2"),
		"新配的规则也能念成人话")

	_check(session.remove_rule_condition(rule.id, 0), "能删条件")
	_check(rule.conditions.is_empty(), "条件删掉了")
	_check(session.remove_rule_action(rule.id, 0), "能删动作")
	_check(rule.actions.is_empty(), "动作删掉了")
	_check(session.remove_rule(rule.id), "能删规则")
	_check_eq(session.project.rules.size(), before, "规则数量恢复")

	# 对象选择器的候选项必须来自工程里真实存在的东西
	var values := _selector_values(session.selector_options("action", "collision"))
	_check(values.has("self"), "碰撞规则的选择器里有「自身」")
	_check(values.has("other"), "碰撞规则的选择器里有「对方」")
	_check(values.has("tag:player"), "选择器里有工程中真实存在的「玩家」标签")
	_check(values.has("instance:i_player"), "选择器里能选到场景里的具体实例")

	# ---- 「自身」只在给得出触发对象的事件里才有意义 ----
	# 用户报过："看不出来「自身」指的是哪个对象"。查下去发现：
	# 「每一帧」这类事件没有触发对象，选「自身」的规则会永远不生效。
	# 界面不再列它，校验器也拦一道。
	var no_actor := _selector_values(session.selector_options("action", "every_frame"))
	_check(not no_actor.has("self"), "「每一帧」的规则里不列「自身」")
	_check(not no_actor.has("other"), "也不列「对方」（只有碰撞才有）")
	var with_actor := _selector_values(session.selector_options("action", "property_change"))
	_check(with_actor.has("self"), "事件给得出触发对象时，「自身」才出现")
	# 事件自己的参数是拿来匹配的，那会儿还没有自身/对方
	var trigger_options := _selector_values(session.selector_options("trigger", "collision"))
	_check(not trigger_options.has("self"), "事件自己的参数里不列「自身」")
	_check(not trigger_options.has("other"), "事件自己的参数里不列「对方」")

	# ---- 同类实例要分得出来 ----
	# 以前五枚金币都叫「金币（这一份）」，一模一样，根本挑不出来
	var labels: Array[String] = []
	for option in session.selector_options("action", "collision"):
		if option.has("value"):
			labels.append(String(option["label"]))
	var coin_labels: Array[String] = []
	for label in labels:
		if label.begins_with("金币 #"):
			coin_labels.append(label)
	_check_eq(coin_labels.size(), 5, "五枚金币各是一条，不再互相重名")
	if coin_labels.size() == 5:
		var unique := {}
		for label in coin_labels:
			unique[label] = true
		_check_eq(unique.size(), 5, "五条金币选项的标签各不相同（%s）" % coin_labels[0])
		_check(coin_labels[0].contains(","), "标签上带着位置，好对上画布上那一枚")
	_check(labels.has("所有「金币」"), "仍然保留「所有「金币」」这一条按标签的选法")


## 金币这类对象没有实体碰撞体，只有触发区（Area2D 里的碰撞形状）
## 从选择器的候选项里取出"值"（跳过分组标题那种只有 separator 的条目）
func _selector_values(options: Array[Dictionary]) -> Array[String]:
	var values: Array[String] = []
	for option in options:
		if option.has("value"):
			values.append(String(option["value"]))
	return values


func _find_hitbox_shape(node: Node) -> CollisionShape2D:
	for child in node.get_children():
		if child is Area2D:
			for grand in child.get_children():
				if grand is CollisionShape2D:
					return grand
	return null


func _find_color_picker(node: Node) -> ColorPickerButton:
	if node is ColorPickerButton:
		return node
	for child in node.get_children():
		var found := _find_color_picker(child)
		if found != null:
			return found
	return null


func _find_spin_boxes(node: Node) -> Array[SpinBox]:
	var out: Array[SpinBox] = []
	if node is SpinBox:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_spin_boxes(child))
	return out


func _find_option_buttons(node: Node) -> Array[OptionButton]:
	var out: Array[OptionButton] = []
	if node is OptionButton:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_option_buttons(child))
	return out


## 找出"当前显示着这段文字"的下拉框，用来在测试里定位特定的选择器
func _find_option_by_selected_text(node: Node, text: String) -> OptionButton:
	for picker in _find_option_buttons(node):
		if picker.get_item_count() > 0 and picker.selected >= 0 \
			and picker.get_item_text(picker.selected) == text:
			return picker
	return null


# --------------------------------------------------------------------------
# 触屏手势
# --------------------------------------------------------------------------

func _mouse_button(canvas: EditCanvas, pressed: bool, pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pos
	canvas._gui_input(event)


func _mouse_move(canvas: EditCanvas, pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	canvas._gui_input(event)


func _touch(canvas: EditCanvas, index: int, pressed: bool, pos: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	canvas._gui_input(event)


func _touch_drag(canvas: EditCanvas, index: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	canvas._gui_input(event)


func _instance_xy(session: EditSession, instance_id: String) -> Vector2:
	var placed := session.find_instance(instance_id)
	return Vector2(placed.x, placed.y) if placed != null else Vector2(-9999, -9999)


## 触屏手势里最容易做错的三件事：
## 单指能不能平移、双指能不能缩放、第二根手指落下时拖动有没有停下来。
func _test_touch_gestures() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("touch.ai2d.json"))
	await process_frame

	var canvas := screen.canvas()
	_check(canvas != null, "有编辑画布")
	if canvas == null:
		screen.queue_free()
		return

	# 单指拖空白处 = 平移画布。
	# 手机上这是唯一的平移方式（没有中键），电脑上也比中键拖动顺手。
	var offset_before := canvas.view_offset()
	_mouse_button(canvas, true, Vector2(60, 60))
	_mouse_move(canvas, Vector2(160, 110))
	_mouse_button(canvas, false, Vector2(160, 110))
	_check(canvas.view_offset() != offset_before, "单指拖空白处能平移画布")
	_check_eq(canvas.view_offset() - offset_before, Vector2(100, 50),
		"平移距离和手指移动距离一致")

	# 双指分开 = 放大
	var scale_before := canvas.view_scale()
	_touch(canvas, 0, true, Vector2(400, 300))
	_touch(canvas, 1, true, Vector2(600, 300))
	_touch_drag(canvas, 1, Vector2(800, 300))
	_check(canvas.view_scale() > scale_before * 1.5, "双指分开，画布放大")

	# 间距不变、只把两指一起挪 = 纯平移，缩放不该跟着变
	var scale_at_rest := canvas.view_scale()
	var offset_at_rest := canvas.view_offset()
	_touch_drag(canvas, 0, Vector2(500, 300))
	_touch_drag(canvas, 1, Vector2(900, 300))
	_check(is_equal_approx(canvas.view_scale(), scale_at_rest), "两指间距不变时缩放不变")
	_check(canvas.view_offset().x > offset_at_rest.x, "两指一起移动能平移画布")

	_touch(canvas, 0, false, Vector2(500, 300))
	_touch(canvas, 1, false, Vector2(900, 300))

	# 第二根手指落下时，正在拖的对象必须立刻停下来。
	# 不处理的话，你一边捏合缩放，被拖着的对象一边跟着手指飞。
	var coin: PlacedEntity = session.current_scene().instances[6]
	var coin_screen := canvas.world_to_screen(Vector2(coin.x, coin.y))
	# 先记下拖动前的位置：coin 就是会话里那个对象本身，
	# 拖完之后它的坐标也变了，拿它当基准比较永远不会成立。
	var start_x := coin.x
	_mouse_button(canvas, true, coin_screen)
	_mouse_move(canvas, coin_screen + Vector2(30, 0))
	var dragged := _instance_xy(session, coin.instance_id)
	_check(dragged.x > start_x, "单指能拖动对象")

	# 真实情况下第一根手指也会产生触摸事件，两个都送进去更接近实际
	_touch(canvas, 0, true, coin_screen)
	_touch(canvas, 1, true, Vector2(900, 500))
	_mouse_move(canvas, coin_screen + Vector2(200, 0))
	_check_eq(_instance_xy(session, coin.instance_id), dragged,
		"第二根手指按下后，对象不再跟着动")

	_touch(canvas, 0, false, coin_screen)
	_touch(canvas, 1, false, Vector2(900, 500))
	_mouse_button(canvas, false, coin_screen + Vector2(200, 0))

	screen.queue_free()
	await process_frame


## 两个对象完全叠在一起时，点一下应该选中表层那个；
## 在同一个地方再点一下，就往下钻一层。
##
## 没有这一条，完全叠住时底下那个永远选不到 —— 点来点去都是同一个选中框，
## 用户会以为对象丢了。平板没有 Alt 键可用，所以用"再点一下"这个办法。
func _test_overlap_drill_down() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("overlap.ai2d.json"))
	await process_frame
	var canvas := screen.canvas()

	# 同一处放两个金币，后放的在上层
	var spot := Vector2(700, 300)
	var lower := session.add_instance("ent_coin", spot)
	var upper := session.add_instance("ent_coin", spot)
	_check(lower != null and upper != null, "在同一处放了两个金币")
	if lower == null or upper == null:
		screen.queue_free()
		return
	var at := canvas.world_to_screen(spot)

	_mouse_button(canvas, true, at)
	_check_eq(session.selected_instance_id, upper.instance_id, "点一下先选中表层那个")
	_check(canvas.overlap_note().contains("叠着"),
		"状态栏会提示这里叠着好几个（%s）" % canvas.overlap_note())
	_mouse_button(canvas, false, at)

	_mouse_button(canvas, true, at)
	_check_eq(session.selected_instance_id, lower.instance_id, "同一个地方再点一下，钻到下面那个")
	_mouse_button(canvas, false, at)

	_mouse_button(canvas, true, at)
	_check_eq(session.selected_instance_id, upper.instance_id, "再点一下绕回最上面那个")
	_mouse_button(canvas, false, at)

	# 换个地方点，回到正常行为：从那一处最上面的开始
	_mouse_button(canvas, true, Vector2(40, 40))
	_mouse_button(canvas, false, Vector2(40, 40))
	_check(session.selected_instance_id.is_empty(), "点空白处取消选中")
	_mouse_button(canvas, true, at)
	_check_eq(session.selected_instance_id, upper.instance_id, "换地方之后再点，重新从表层开始")
	_mouse_button(canvas, false, at)

	screen.queue_free()
	await process_frame


## 逻辑编辑器是 M3 的主体：能不能在界面上真的把规则配出来。
func _test_rule_editor_ui() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("rule_ui.ai2d.json"))
	await process_frame

	var editor := screen.rule_editor()
	_check(editor != null, "编辑器里有逻辑编辑器")
	_check(not editor.is_visible_in_tree(), "默认显示的是关卡编辑")
	_check(screen.canvas().is_visible_in_tree(), "默认能看到画布")

	screen._set_rule_mode(true)
	await process_frame
	_check(editor.is_visible_in_tree(), "切到逻辑模式后逻辑编辑器出现")
	_check(not screen.canvas().is_visible_in_tree(), "这时关卡画布被收起")
	# 示例工程本来就有 6 条规则，列表里应该能看到
	_check(_find_button(editor, "＋ 新规则") != null, "逻辑界面里有「＋ 新规则」按钮")

	var before := session.project.rules.size()
	var add := _find_button(editor, "＋ 新规则")
	if add != null:
		add.pressed.emit()
		await process_frame
	_check_eq(session.project.rules.size(), before + 1, "点一下真的新增了一条规则")

	var add_action := _find_button(editor, "＋ 加一个动作")
	_check(add_action != null, "有「＋ 加一个动作」按钮")
	if add_action != null:
		add_action.pressed.emit()
		await process_frame

	var rule := session.project.rules[before]
	_check_eq(rule.actions.size(), 1, "动作加上了")

	# 「反向」勾选框。数据里一直有这个字段（示例的「松开方向键就停下」在用），
	# 但界面上从来没地方勾，只能手改 JSON —— 于是那句话读出来还是正着的。
	var add_condition := _find_button(editor, "＋ 加一个条件")
	_check(add_condition != null, "有「＋ 加一个条件」按钮")
	if add_condition != null:
		add_condition.pressed.emit()
		await process_frame
		_check_eq(rule.conditions.size(), 1, "条件加上了")

		var negate_box := _find_button(editor, "反向（不满足）")
		_check(negate_box != null, "条件块上有「反向」勾选框")
		if negate_box != null and rule.conditions.size() == 1:
			negate_box.button_pressed = true
			await process_frame
			_check_eq(rule.conditions[0].get("negate"), true,
				"勾上「反向」，数据里真的取反了")
			var sentence := RuleVocabulary.describe(rule, session.project)
			print("   " + sentence)
			_check(sentence.contains("<"),
				"勾了反向，句子里把运算符翻过来念")

	if rule.actions.size() == 1:
		var statement: Dictionary = rule.actions[0]
		var missing: Array[String] = []
		var def := RuleVocabulary.action_def(String(statement.get("type", "")))
		for key in RuleVocabulary.param_defs(def):
			if not statement.has(key):
				missing.append(key)
		_check(missing.is_empty(), "新建的动作自带全部参数（缺 %s）" % str(missing))

	# 从下拉框换事件类型：选完之后数据必须真的变，新事件的参数栏要跟着换出来。
	# 用户报过「选了『每隔一段时间』却找不到填间隔的地方」——
	# 原因是回调的参数个数对不上，调用失败，而下拉框自己照样换了文字。
	# 界面上看起来"选上了"，底下什么都没发生。
	var spins_before := _find_spin_boxes(editor).size()
	var picker := _find_option_by_selected_text(editor, RuleVocabulary.trigger_label("tap"))
	_check(picker != null, "找到事件类型下拉框")
	if picker != null:
		var target_index := -1
		for i in picker.get_item_count():
			if picker.get_item_text(i) == RuleVocabulary.trigger_label("timer"):
				target_index = i
		_check(target_index >= 0, "下拉框里能选到「每隔一段时间」")
		if target_index >= 0:
			picker.selected = target_index
			picker.item_selected.emit(target_index)
			await process_frame
			_check_eq(String(rule.trigger.get("type", "")), "timer", "选完之后事件真的换了")
			_check(rule.trigger.has("interval"), "「间隔」这个参数出现在了数据里")
			_check(_find_spin_boxes(editor).size() > spins_before,
				"界面上真的多出了可以填间隔的数字框")
			_check(_find_option_by_selected_text(editor, RuleVocabulary.trigger_label("timer")) != null,
				"下拉框显示的是新选的事件")

	# 表单要真的长出来：动作类型、对象选择器都是下拉框
	_check(_find_option_buttons(editor).size() >= 2, "界面上生成了下拉框（类型 + 对象选择器）")
	_check(_find_spin_boxes(editor).size() >= 1, "界面上生成了数字框（动作的数值参数）")

	screen._set_rule_mode(false)
	await process_frame
	_check(not editor.is_visible_in_tree(), "能切回关卡编辑")
	_check(screen.canvas().is_visible_in_tree(), "画布回来了")

	screen.queue_free()
	await process_frame


## AI 助手是 M4 的主体。要盯住三件事：
##   1. 离线也能用，而且**同一个问题给同一个答案**（不然演示时像在掷骰子）
##   2. 生成的东西**先过校验**，不合法就碰不到真工程
##   3. 应用之后**一步就能撤销**——这是"敢让它动手"的前提
func _test_ai_assistant() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return
	var service := AIService.new()

	# ---- 生成一个敌人 ----
	var draft := service.draft("一个会飞的紫色小怪", session.project)
	_check(draft.ok(), "离线生成器认得这句话")
	_check(draft.title.contains("紫") and draft.title.contains("飞"),
		"名字里带上了我说的颜色和「会飞」（%s）" % draft.title)
	_check_eq(draft.entities.size(), 1, "生成了一种新对象")
	if draft.entities.size() == 1:
		var entity: Dictionary = draft.entities[0]
		_check_eq(String(entity.get("color", "")), "#c084fc", "颜色就是我说的紫")
		_check((entity.get("tags", []) as Array).has("hazard"),
			"打了「危险物」标签，工程里已有的扣血规则才管得到它")
		_check_eq(String((entity.get("physics", {}) as Dictionary).get("mode", "")),
			"kinematic", "飞行怪默认就是「会动」的 —— 不然用户配了速度它也不动")
		_check_eq(float((entity.get("physics", {}) as Dictionary).get("gravity_scale", -1.0)),
			0.0, "而且不受重力，所以它飘着")
	_check_eq(draft.placements.size(), 1, "会在当前关卡里摆一个，不然用户看不到")
	_check(draft.rules.is_empty(),
		"工程里已经有「碰到危险物扣血」，就不再重复造一条规则")
	_check(draft.steps.size() >= 2, "预告里列了它要做的每一步")
	# "小怪"里的"小"是名字，不是尺寸 —— 用户没说要小号的
	if draft.entities.size() == 1:
		var normal_size := float((draft.entities[0] as Dictionary).get("collider", {}).get("width", 0))
		_check_eq(normal_size, 48.0, "说「小怪」不会把它缩小")
	_check(draft.steps[0].contains("普通大小"), "预告里也写的是普通大小")

	# 同一个问题必须给同一个答案：演示时"每次都不一样"会让人怀疑它稳不稳
	var again := service.draft("一个会飞的紫色小怪", session.project)
	_check_eq(JSON.stringify(again.to_dict()), JSON.stringify(draft.to_dict()),
		"同一句话问两次，结果一模一样")

	# ---- 换个说法：颜色和大小都要认出来 ----
	var big := service.draft("一个红色的大怪", session.project)
	_check(big.ok(), "换句话也认得")
	if big.entities.size() == 1:
		_check_eq(String((big.entities[0] as Dictionary).get("color", "")), "#f87171",
			"红色认得出来")
		var big_size := float((big.entities[0] as Dictionary).get("collider", {}).get("width", 0))
		_check(big_size > 48.0, "「大」这个字让它变大（宽 %d）" % int(big_size))
		_check_eq(String((big.entities[0] as Dictionary).get("physics", {}).get("mode", "")),
			"static", "不提「飞」的敌人还是静止的危险物")

	# ---- 认不出来的时候要老实说，不能瞎编 ----
	var confused := service.draft("今天天气不错", session.project)
	_check(not confused.ok(), "听不懂就不给草稿")
	_check(confused.error.contains("没听懂"), "而且说清是没听懂")
	_check(confused.error.contains("试试"), "顺带告诉用户能说什么")
	_check(not service.draft("", session.project).ok(), "空输入也不硬凑")

	# ---- 让天上掉金币 ----
	var rain := service.draft("每 3 秒掉一个金币", session.project)
	_check(rain.ok(), "金币雨这句也认得")
	# 中文里"掉金币"和"掉一个金币"差着两个字，别只认死一种说法
	_check(service.draft("天上掉金币", session.project).ok(), "换个说法也认得（天上掉金币）")
	var half := service.draft("每隔 1.5 秒来一枚金币", session.project)
	_check(half.ok(), "再换一种也认得")
	if half.rules.size() == 1:
		_check_eq(float((half.rules[0] as Dictionary).get("trigger", {}).get("interval", 0.0)),
			1.5, "小数秒数也读得出来")
	_check_eq(rain.rules.size(), 1, "加了一条规则")
	# 用户报过：生成的"掉金币"位置在屏幕外、而且根本不会往下掉。
	# 根因是示例里的金币不受重力，直接生成它只会停在半空。
	# 所以现在会**另做一种"会掉的金币"**，这里锁死这两条。
	_check_eq(rain.entities.size(), 1, "顺手做了一种「会掉的金币」")
	var falling_id := ""
	if rain.entities.size() == 1:
		var coin_copy: Dictionary = rain.entities[0]
		falling_id = String(coin_copy.get("id", ""))
		var physics: Dictionary = coin_copy.get("physics", {})
		_check_eq(String(physics.get("mode", "")), "kinematic", "它是会动的，不是静止的")
		_check_eq(float(physics.get("gravity_scale", 0.0)), 1.0, "而且受重力，才会往下掉")
		_check((coin_copy.get("tags", []) as Array).has("coin"),
			"仍然带着 coin 标签，工程里那条「吃金币加分」照样管得到它")
		var coin_def := session.project.find_entity("ent_coin")
		_check_eq(String(coin_copy.get("color", "")), coin_def.color,
			"长得和原来的金币一样")
		_check(String(coin_copy.get("name", "")) != coin_def.name,
			"但它是另一种对象，不会把地面上摆好的金币一起改掉")
	if rain.rules.size() == 1:
		var rule: Dictionary = rain.rules[0]
		var trigger: Dictionary = rule.get("trigger", {})
		_check_eq(String(trigger.get("type", "")), "timer", "用的是「每隔一段时间」")
		_check_eq(float(trigger.get("interval", 0.0)), 3.0, "间隔就是我说的 3 秒")
		var action: Dictionary = (rule.get("actions", []) as Array)[0]
		_check_eq(String(action.get("type", "")), "spawn", "动作是「创建对象」")
		_check_eq(String(action.get("entity_id", "")), falling_id, "生成的是那种会掉的金币")
	_check(("\n".join(rain.steps)).contains("往下掉"), "草稿里如实写明它会长什么样、会不会掉")

	# 拾取物存在的工程里必须有一个"地面"类对象。
	# 用户定的规则是"金币只和地面碰撞"，代价就是：没有地面时它会穿过一切
	# 掉出画面 —— 而且一声不吭。这种静默失败必须在编辑期提醒。
	var no_ground := GameProject.from_dict(session.project.to_dict())
	# 把场景里所有"实际是地面"的对象都改成普通障碍（实例级覆盖）
	for scene in no_ground.scenes:
		for placed in scene.instances:
			var def := no_ground.find_entity(placed.entity_id)
			if PlacedEntity.resolve_collision_group(def, placed) == EntityDef.COLLISION_GROUND:
				placed.collision_group = EntityDef.COLLISION_SOLID
	var warned := false
	for issue in ProjectValidator.validate(no_ground):
		if issue.code == "project.no_ground":
			warned = true
	_check(warned, "工程里没有「地面」类对象时会警告：掉落物会穿过一切")

	# ---- 工程里没有金币时，要说不做，而不是硬做 ----
	var no_coin := GameProject.from_dict(session.project.to_dict())
	var kept: Array[EntityDef] = []
	for def in no_coin.entities:
		if not def.has_tag("coin"):
			kept.append(def)
	no_coin.entities = kept
	var no_coin_draft := service.draft("每 2 秒掉一个金币", no_coin)
	_check(not no_coin_draft.ok(), "工程里没有金币就直说做不了")
	_check(no_coin_draft.error.contains("金币"), "并且说清缺的是什么")

	# ---- 工程里没有"危险物扣血"规则时，要自己补一条 ----
	var no_hazard := GameProject.from_dict(session.project.to_dict())
	var kept_rules: Array[RuleDef] = []
	for rule in no_hazard.rules:
		var trigger: Dictionary = rule.trigger
		var touches_hazard := String(trigger.get("a", "")) == "tag:hazard" \
			or String(trigger.get("b", "")) == "tag:hazard"
		if not touches_hazard:
			kept_rules.append(rule)
	no_hazard.rules = kept_rules
	var lonely := service.draft("一个蓝色的小怪", no_hazard)
	_check_eq(lonely.rules.size(), 1, "没有现成规则时，它会自己补一条扣血规则")

	# ---- 应用到工程：一步撤销 ----
	var entities_before := session.project.entities.size()
	var instances_before := session.current_scene().instances.size()
	var problem := session.apply_ai_draft(draft)
	_check_eq(problem, "", "草稿能应用进工程")
	_check_eq(session.project.entities.size(), entities_before + 1, "工程里多了一种对象")
	_check_eq(session.current_scene().instances.size(), instances_before + 1, "关卡里多了一个对象")
	_check_eq(session.project.rules.size(), 11, "规则没变（复用了现成那条）")
	_check(not session.selected_instance_id.is_empty(), "新生成的对象被自动选中")
	_check(session.dirty, "应用之后标记为有未保存改动")

	session.undo()
	_check_eq(session.project.entities.size(), entities_before, "按一次 Ctrl+Z 就整份撤掉")
	_check_eq(session.current_scene().instances.size(), instances_before, "摆出来的对象也撤掉了")

	# ---- 不合法的草稿根本碰不到真工程 ----
	var bad := AIDraft.new()
	bad.title = "坏草稿"
	bad.rules.append({
		"id": "rule_ai_bad", "name": "坏规则", "enabled": true, "scene_id": "",
		"trigger": {"type": "我瞎编的事件"}, "conditions": [], "actions": [],
	})
	var rules_before := session.project.rules.size()
	var rejected := session.apply_ai_draft(bad)
	_check(not rejected.is_empty(), "没通过校验的草稿会被拒绝")
	_check(rejected.contains("校验"), "而且说清是校验没过")
	_check_eq(session.project.rules.size(), rules_before, "被拒绝的草稿一点都没改动工程")

	# ---- 真跑一遍：生成出来的金币必须真的往下掉 ----
	# 这一条是被用户报出来的缺陷逼出来的：草稿写着"会掉下来"，
	# 实际它停在半空中不动 —— 因为示例里的金币不受重力。
	# 只断言数据不够，得让运行器真的跑一遍才算数。
	var rain_session := EditSession.new()
	_check(rain_session.open(SAMPLE_PATH), "再开一份示例工程做试跑")
	if rain_session.project != null:
		var draft2 := service.draft("每 1 秒掉一个金币", rain_session.project)
		_check_eq(rain_session.apply_ai_draft(draft2), "", "金币雨草稿能应用")

		var rt := GameRuntime.new()
		rt.setup(rain_session.project)
		root.add_child(rt)
		rt.start()
		await _step(75)

		var fallen: Actor = null
		for actor in rt.actors:
			if actor.definition != null and actor.definition.id.begins_with("ent_ai_coin"):
				fallen = actor
				break
		_check(fallen != null, "规则真的把金币生成出来了")
		if fallen != null:
			var y_before := fallen.position.y
			await _step(20)
			_check(fallen.position.y > y_before + 10.0,
				"而且它真的在往下掉（%d → %d）" % [int(y_before), int(fallen.position.y)])

		# 落地之后还得在：没接住的金币应该留在地上等人来捡。
		# "东西生出来又莫名不见"是最难查的一类问题，所以这里等久一点看总数。
		await _step(300)
		var landed := 0
		var resting_y := 0.0
		var lowest := -1.0e9
		var highest := 1.0e9
		var resting_x := 0.0
		for a in rt.actors:
			if a.definition != null and a.definition.id.begins_with("ent_ai_coin"):
				landed += 1
				resting_y = maxf(resting_y, a.position.y)
				lowest = maxf(lowest, a.position.y)
				highest = minf(highest, a.position.y)
				resting_x = a.position.x
		print("   几秒后还在场的掉落金币：%d 个，最靠下的一个 y=%d" % [landed, int(resting_y)])
		_check(landed >= 2, "每隔一段时间落一颗，地上会攒下好几颗（%d）" % landed)
		# 地面顶上在 y≈672。金币得**停在地面上**，不能穿过去掉出画面 ——
		# 穿过去的话画面上什么都看不到，用户只会说"金币没掉下来"。
		_check(resting_y < 720.0, "金币落在地面上，没有穿过地面掉出去（y=%d）" % int(resting_y))
		# 拾取物不互相挡：几颗金币应该**叠在同一处**，而不是一颗踩一颗堆成柱子。
		# 用户看过那根柱子的截图，说的原话是"金币应该可以和金币重叠"。
		# 只统计"已经落地"的那些：刚落下来的还在半空中，高度当然不一样。
		var resting: Array[float] = []
		for a in rt.actors:
			if a.definition != null and a.definition.id.begins_with("ent_ai_coin") \
				and a.position.y > 400.0 and absf(a.velocity.y) < 1.0:
				resting.append(a.position.y)
		_check(resting.size() >= 3, "攒下好几颗已经落地的金币（%d 颗）" % resting.size())
		if resting.size() >= 2:
			var spread: float = resting.max() - resting.min()
			_check(spread < 2.0, "落地的金币叠在同一处，不再堆成柱子（y 差 %d）" % int(spread))

		# 拾取物不挡人，但仍然吃得到：把玩家挪到金币身上，分数应该加。
		# 这两件事必须同时成立 —— 只做"不挡人"而把判定也顺手关掉，
		# 会变成"金币看不到了也吃不到了"，那比原来更糟。
		var player := rt.actor_by_instance("i_player") as Actor
		var target_coin: Actor = null
		for a in rt.actors:
			if a.definition != null and a.definition.id.begins_with("ent_ai_coin"):
				target_coin = a
				break
		_check(player != null and target_coin != null, "找得到玩家和一枚掉落金币")
		if player != null and target_coin != null:
			# 挡不挡人，看的是物理层：玩家的掩码里不该有拾取物那一层
			_check((player.collision_mask & target_coin.collision_layer) == 0,
				"拾取物不挡玩家（物理层分开了）")
			_check((target_coin.collision_mask & target_coin.collision_layer) == 0,
				"拾取物也不互相挡")
			# 用户报过："金币会粘在小怪身上跟小怪一起走" —— 金币和会动的对象
			# 之间本来有实体碰撞，Godot 会把脚下的东西当移动平台带着跑。
			# 现在拾取物的掩码里只有"不动的地形"那一层。
			_check((target_coin.collision_mask & Actor.LAYER_MOVING) == 0,
				"拾取物不和会动的对象碰（不然会被带着走）")
			# 用户又说："尖刺不碰吧" —— 现在拾取物只和"地面"那一层碰，
			# 普通障碍（尖刺、静止的怪）都会穿过去
			var spikes := rt.actors_with_tag("hazard")
			if not spikes.is_empty():
				_check((target_coin.collision_mask & (spikes[0] as Actor).collision_layer) == 0,
					"拾取物不和尖刺碰（会穿过去落到地面）")
			var grounds := rt.actors_with_tag("ground")
			if not grounds.is_empty():
				_check((target_coin.collision_mask & (grounds[0] as Actor).collision_layer) != 0,
					"但拾取物照样和地面碰，所以能落地")

			var score_before := int(rt.query_property("tag:player", "score"))
			player.position = Vector2(target_coin.position.x, target_coin.position.y)
			await _step(6)
			_check(int(rt.query_property("tag:player", "score")) > score_before,
				"站到金币上就吃得到（%d → %d）" % [score_before, int(rt.query_property("tag:player", "score"))])
			_check(resting_x > 0.0, "金币的落点在画面里（x=%d）" % int(resting_x))

		await _dispose_runtime(rt)


## 用户的原话："我给 AI 生成的小怪配了「设置速度」，它纹丝不动。"
##
## 根因是那只小怪的物理类型是"静止"，而静止对象不参与物理步进 ——
## 速度写进去了，没有任何东西去用它。类型上的物理属性界面上改不了，
## 所以补了一条实例级的通道：选中这一个对象，直接把它改成"会动"。
func _test_instance_motion_override() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	# 挑两枚一模一样的空中金币：改一枚，另一枚必须不受影响
	var first := session.current_scene().instances[6]
	var second := session.current_scene().instances[7]
	_check_eq(first.entity_id, second.entity_id, "这两枚是同一种对象")
	_check_eq(session.describe_motion(first), "跟随类型：不参与物理（能穿过去）",
		"默认是跟随类型，而类型上写的是不参与物理")

	session.set_instance_motion(first.instance_id, PlacedEntity.MOTION_FALL)
	_check_eq(session.describe_motion(first), "已单独设置：会动、会往下掉",
		"改成「会掉」之后说明也跟着变")
	_check(second.motion.is_empty(), "另一枚没有被一起改掉")
	# 碰撞身份也能单独改：把这一枚改成"普通障碍"，说明行跟着变
	_check_eq(session.describe_collision_group(first), "跟随类型：拾取物（不挡人，只落在地面上）",
		"碰撞默认跟随类型")
	session.set_instance_collision_group(first.instance_id, EntityDef.COLLISION_SOLID)
	_check_eq(session.describe_collision_group(first),
		"已单独设置：普通障碍（挡得住人，掉落物会穿过去）", "改了碰撞说明跟着变")
	_check(second.collision_group.is_empty(), "另一枚的碰撞没有被一起改掉")
	session.set_instance_collision_group(first.instance_id, "")

	# 实例级覆盖要真的传到运行器：把这枚金币改成"普通障碍"，
	# 它就不再是拾取物那一层了（不再只和地面碰）
	# 注意先把"会动"恢复掉：会动的对象统一走"会动那一层"
	# （这样掉落物才不会粘在会动的小怪身上），这条优先级要在测试里写清楚
	session.set_instance_motion(first.instance_id, "")
	session.set_instance_collision_group(first.instance_id, EntityDef.COLLISION_SOLID)
	var probe := GameRuntime.new()
	probe.setup(session.project)
	root.add_child(probe)
	probe.start()
	await _step(2)
	var promoted := probe.actor_by_instance(first.instance_id) as Actor
	_check(promoted != null, "能找到那枚被改过碰撞的金币")
	if promoted != null:
		_check_eq(promoted.collision_layer, Actor.LAYER_SOLID,
			"被改成「普通障碍」之后，它换到普通障碍那一层")
		_check((promoted.collision_mask & Actor.LAYER_MOVING) != 0,
			"而且现在会和会动的对象碰（不再是拾取物）")
	await _dispose_runtime(probe)
	session.set_instance_collision_group(first.instance_id, "")

	session.set_instance_motion(first.instance_id, "")
	_check_eq(session.describe_motion(first), "跟随类型：不参与物理（能穿过去）",
		"清空之后恢复跟随类型")

	# 真正跑起来：会掉的那枚要掉，说会飘的那枚要原地不动
	session.set_instance_motion(first.instance_id, PlacedEntity.MOTION_FALL)
	session.set_instance_motion(second.instance_id, PlacedEntity.MOTION_FLOAT)
	var rt := GameRuntime.new()
	rt.setup(session.project)
	root.add_child(rt)
	rt.start()
	await _step(4)
	var falling := rt.actor_by_instance(first.instance_id) as Actor
	var floating := rt.actor_by_instance(second.instance_id) as Actor
	_check(falling != null and floating != null, "两个对象都在场景里")
	if falling != null and floating != null:
		var fall_y := falling.position.y
		var float_y := floating.position.y
		await _step(30)
		_check(falling.position.y > fall_y + 20.0,
			"改成「会掉」的那一枚真的在往下掉（%d → %d）" % [int(fall_y), int(falling.position.y)])
		_check(is_equal_approx(floating.position.y, float_y),
			"改成「会飘」的那一枚原地不动（y=%d）" % int(float_y))

	await _dispose_runtime(rt)


## 用户配了一条"永远不会生效"的规则，界面上却一个字都不提示。
##
## 校验器从很早就认得这类问题（在没有触发对象的事件里用了「自身」），
## 但结果只有自动化测试看得到。现在把它显示到逻辑界面上：
## 清单里那一条打 ⚠，详情里写出原因。
func _test_rule_warning_display() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("warn.ai2d.json"))
	await process_frame
	screen._set_rule_mode(true)
	await process_frame
	var editor := screen.rule_editor()

	# 造一条配错的：事件是「每一帧」（没有触发对象），动作却对着「自身」
	var rule := session.add_rule()
	_check(rule != null, "新建一条规则")
	if rule == null:
		screen.queue_free()
		return
	session.set_rule_trigger_type(rule.id, "every_frame")
	var index := session.add_rule_action(rule.id, "set_velocity")
	session.set_rule_action_param(rule.id, index, "target", "self")
	# 详情面板显示的是"当前选中的那条规则"，所以要把新建的这条选中
	editor._selected_rule_id = rule.id
	editor.rebuild()
	await process_frame

	var flagged := false
	for issue in ProjectValidator.validate(session.project):
		if issue.path.begins_with("rules/%s" % rule.id):
			flagged = true
	_check(flagged, "校验器认得出这条规则不会生效")
	_check(_find_label_prefix(editor, "⚠ %s" % rule.name) != null,
		"清单里那一条被打了 ⚠ 标记")
	_check(_find_label_prefix(editor, "⚠ 规则") != null,
		"详情里写出了原因")

	# 配对了就该消失：把事件换成碰撞（碰撞有触发对象）
	session.set_rule_trigger_type(rule.id, "collision")
	await process_frame
	_check(_find_label_prefix(editor, "⚠") == null, "改成有触发对象的事件之后提示消失")

	screen.queue_free()
	await process_frame


## 点素材栏里的一项 = 编辑"这一类"。这是"改不了实体类型"那笔老账的第一步。
##
## 两条东西必须同时成立，缺一个都会出事：
##   1. 改类型确实会影响**一整类**（不然改了半天没效果）
##   2. 界面上**说清楚**了这一点，并且给"只想改这一个"的人一条明路
##      （不然用户想改一枚金币，结果整场都变红了）
func _test_type_panel() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	# ---- 选中"这一类"和选中"这一个"互斥 ----
	session.select_entity("ent_coin")
	_check(session.selected_entity() != null, "能选中「金币」这一类")
	_check(session.selected_instance_id.is_empty(), "选中一类会清掉实例的选中")
	var first_coin := session.current_scene().instances[6]
	var second_coin := session.current_scene().instances[7]
	session.select_instance(first_coin.instance_id)
	_check(session.selected_entity_id.is_empty(), "选中一个实例会清掉类型的选中")

	# ---- 六项都能改，而且能撤销 ----
	session.select_entity("ent_coin")
	_check_eq(session.instance_count_of("ent_coin"), 5, "场上 5 枚金币")
	session.set_entity_name("ent_coin", "金币子")
	_check_eq(session.project.find_entity("ent_coin").name, "金币子", "能改名字")
	session.set_entity_tags("ent_coin", PackedStringArray(["coin", "pickup"]))
	_check(session.project.find_entity("ent_coin").has_tag("pickup"), "能改标签")
	session.set_entity_shape("ent_coin", EntityDef.SHAPE_RECT)
	_check_eq(session.project.find_entity("ent_coin").collider_shape, "rect", "能改形状")
	session.set_entity_size("ent_coin", 60.0, 60.0, 30.0)
	_check_eq(session.project.find_entity("ent_coin").collider_width, 60.0, "能改原始大小")
	session.set_entity_collision_group("ent_coin", EntityDef.COLLISION_PICKUP)
	_check_eq(session.project.find_entity("ent_coin").collision_group, "pickup", "能改碰撞")
	session.set_entity_motion("ent_coin", PlacedEntity.MOTION_FALL)
	var changed := session.project.find_entity("ent_coin")
	_check_eq(changed.physics_mode, "kinematic", "能改成「会掉的」")
	_check_eq(changed.gravity_scale, 1.0, "而且重力也跟着设好")
	_check_eq(session.entity_motion_preset(changed), PlacedEntity.MOTION_FALL,
		"面板要能回显现在是哪一档")
	_check(session.dirty, "改类型会标记为有未保存改动")

	session.undo()
	_check_eq(session.project.find_entity("ent_coin").physics_mode, "none",
		"一次撤销退回「不参与物理」")

	# ---- 改类型 = 影响一整类；自己设过的那个不受影响 ----
	session.set_instance_color(first_coin.instance_id, "")
	session.set_instance_color(second_coin.instance_id, "#ff0000")
	session.set_entity_color("ent_coin", "#22d3ee")
	var fresh_first := session.find_instance(first_coin.instance_id)
	var fresh_second := session.find_instance(second_coin.instance_id)
	_check_eq(session.effective_color(fresh_first), Color("#22d3ee"),
		"没自己设过颜色的，跟着类型一起变")
	_check_eq(session.effective_color(fresh_second), Color("#ff0000"),
		"自己设过颜色的那一个不受影响")
	_check_eq(session.overridden_count_of("ent_coin", "color"), 1,
		"面板标语要能算出「有几个不受影响」")

	# ---- 界面 ----
	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("typepanel.ai2d.json"))
	await process_frame
	var panel := screen.inspector()

	var coin_button := _find_button(screen, "  金币子")
	_check(coin_button != null, "素材栏里有这一项")
	if coin_button != null:
		coin_button.pressed.emit()
		await process_frame
	_check(session.selected_entity_id == "ent_coin", "点一下就选中这一类")
	_check(_labels_containing(panel, "正在编辑").size() > 0,
		"面板顶部标出正在编辑哪一类")
	_check(_labels_containing(panel, "场上摆了").size() > 0,
		"并且说清会影响几个")
	_check(_labels_containing(panel, "内部名").size() > 0, "顺手标出内部名")
	_check(_labels_containing(panel, "只想改某一个").size() > 0,
		"颜色那行给了「只想改这一个」的明路")

	# 选中一个实例 → 面板换成"这一个"，并且给出反方向的明路
	session.select_instance(fresh_first.instance_id)
	await process_frame
	_check(_labels_containing(panel, "想一次改一整类").size() > 0,
		"实例面板上给了「想改一整类」的明路")
	_check(_labels_containing(panel, "缩放").size() > 0,
		"实例那边叫「缩放」")
	# 注意：交叉指引那句话里也会提到"原始大小"，所以这里查的是"以小标题形式出现"
	_check(_find_label_prefix(panel, "原始大小") == null,
		"实例面板里没有叫「原始大小」的小节，免得和「缩放」混成一样")
	var to_type := _find_button(panel, "改这一类（金币子）")
	_check(to_type != null, "实例面板上有「改这一类」按钮")
	if to_type != null:
		to_type.pressed.emit()
		await process_frame
	_check(session.selected_entity_id == "ent_coin", "点它切到这一类")
	_check(session.selected_instance_id.is_empty(), "同时取消实例选中")

	screen.queue_free()
	await process_frame


## 老工程要能自动升级。
##
## 用户实测撞到过：他保存的工程里「地面」还是 1.0 时代的 `solid`，
## 而掉落物的掩码里只有"地面"那一层 —— 于是金币穿过一切掉出画面。
## 这类"看着没事、跑起来不对"的问题最难查，必须由加载时的一次升级挡住。
func _test_project_upgrade() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	_check(loaded.ok, "能读示例工程")
	if not loaded.ok:
		return

	# 把工程改回 1.0 时代的样子：版本写 1.0，地面写成 solid
	var old := loaded.project.to_dict()
	old["schema_version"] = "1.0"
	for item in old["entities"]:
		if (item.get("tags", []) as Array).has("ground"):
			item["collision_group"] = "solid"

	var upgraded := GameProject.from_dict(old)
	_check_eq(upgraded.schema_version, GameProject.SCHEMA_VERSION,
		"老工程升级到当前版本（%s）" % GameProject.SCHEMA_VERSION)
	var ground_def: EntityDef = null
	var spike_def: EntityDef = null
	for e in upgraded.entities:
		if e.has_tag("ground"):
			ground_def = e
		elif e.has_tag("hazard"):
			spike_def = e
	_check(ground_def != null and ground_def.is_ground(),
		"1.0 时代的地面被自动认成「地面」，掉落物才接得住")
	_check(spike_def != null and spike_def.collision_group == EntityDef.COLLISION_SOLID,
		"尖刺不会被顺手改掉（只认带 ground 标签的）")

	# 升级过的工程不该再报"版本不符"
	var warned := false
	for issue in ProjectValidator.validate(upgraded):
		if issue.code == "schema.version":
			warned = true
	_check(not warned, "升级后不再提示版本不符")

	# 已经是当前版本的工程不动它
	var current := GameProject.from_dict(loaded.project.to_dict())
	_check_eq(current.schema_version, GameProject.SCHEMA_VERSION, "当前版本的工程原样读出来")


## 工程级的提醒要显示在界面上，不能只在自动化测试里。
##
## 用户报过："拾取物没有落在地面上而是穿过了地面" —— 根因是他那份老工程里的
## 「地面」没标成"地面"，而校验器认得出这件事，只是从来没显示给用户看过。
func _test_project_warning_bar() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return
	# 把场景里所有"实际是地面"的对象改成普通障碍 —— 掉落物就没东西可落了
	for scene in session.project.scenes:
		for placed in scene.instances:
			var def := session.project.find_entity(placed.entity_id)
			if PlacedEntity.resolve_collision_group(def, placed) == EntityDef.COLLISION_GROUND:
				placed.collision_group = EntityDef.COLLISION_SOLID

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("warnbar.ai2d.json"))
	await process_frame

	var notes := _labels_containing(screen, "⚠")
	_check(not notes.is_empty(), "状态栏里确实显示出了工程级提醒")
	var mentions_ground := false
	for note in notes:
		if note.contains("地面"):
			mentions_ground = true
	_check(mentions_ground, "提醒里说清了是「地面」的问题（%s）" % (notes[0] if not notes.is_empty() else ""))

	screen.queue_free()
	await process_frame


## 找出所有包含某段文字的标签（用来验证"界面上真的显示了这句话"）
func _labels_containing(node: Node, needle: String) -> Array[String]:
	var out: Array[String] = []
	if node is Label and (node as Label).text.contains(needle):
		out.append((node as Label).text)
	for child in node.get_children():
		out.append_array(_labels_containing(child, needle))
	return out


## 在界面里找一个以某段文字开头的标签（用来验证"界面上真的显示了这句话"）
func _find_label_prefix(node: Node, prefix: String) -> Label:
	if node is Label and (node as Label).text.begins_with(prefix):
		return node
	for child in node.get_children():
		var found := _find_label_prefix(child, prefix)
		if found != null:
			return found
	return null


## AI 面板的界面：能不能点到、看懂、撤掉
func _test_ai_panel_ui() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("ai_ui.ai2d.json"))
	await process_frame

	var panel := screen.ai_panel()
	_check(panel != null, "编辑器里有 AI 面板")
	if panel == null:
		screen.queue_free()
		return
	_check(not panel.is_visible_in_tree(), "默认显示的是关卡编辑")

	var ai_button := _find_button(screen, "✨ AI")
	_check(ai_button != null, "顶栏有「✨ AI」按钮")
	if ai_button != null:
		ai_button.pressed.emit()
		await process_frame
	_check(panel.is_visible_in_tree(), "点一下就进 AI 界面")
	_check(not screen.canvas().is_visible_in_tree(), "这时关卡画布被收起")

	# 如实写出当前用的是哪一种 —— 不写的话用户会觉得"有时候灵有时候不灵"
	_check(panel.service.mode_label().contains("离线"),
		"界面上写着当前是离线生成（%s）" % panel.service.mode_label())
	var key_button := _find_button(panel, "填 key 变聪明")
	_check(key_button != null, "留了「填 key 变聪明」的入口")
	if key_button != null:
		_check(key_button.disabled, "但还没做，所以是灰的 —— 不放点了没反应的按钮")

	# 走真实路径：输入 → 生成 → 预览 → 应用
	# 注意：每点一次，面板会重建自己，所以按钮每次都要重新找一遍，
	# 不能拿着上一次找到的那个（它已经被回收了）。
	_check(panel.input_line() != null, "面板里有输入框")
	_check(_find_button(panel, "生成草稿") != null, "有「生成草稿」按钮")
	await _ai_type_and_generate(panel, "一个会飞的紫色小怪")
	_check(panel.current_draft() != null, "点一下真的生成了草稿")
	_check(panel.draft_steps().contains("新建一种对象"), "预览里列出了它要做的事（%s）" % panel.draft_steps())

	var entities_before := session.project.entities.size()
	var apply_button := _find_button(panel, "应用到工程")
	_check(apply_button != null, "有「应用到工程」按钮")
	if apply_button != null:
		apply_button.pressed.emit()
		await process_frame
	_check_eq(session.project.entities.size(), entities_before + 1, "点应用真的写进了工程")
	_check(panel.status_message().contains("Ctrl+Z"), "应用之后告诉用户能撤销")
	_check(panel.current_draft() == null, "应用过的草稿不会留在面板上重复应用")

	# 「算了」这条路：草稿丢掉，工程一点不动
	await _ai_type_and_generate(panel, "一个绿色的小怪")
	var still := session.project.entities.size()
	var discard := _find_button(panel, "算了，不要")
	_check(discard != null, "有「算了，不要」按钮")
	if discard != null:
		discard.pressed.emit()
		await process_frame
	_check(panel.current_draft() == null, "草稿被丢掉了")
	_check_eq(session.project.entities.size(), still, "工程没有被改动")

	# 回到关卡
	var back := _find_button(panel, "← 回到关卡")
	_check(back != null, "AI 界面里有「回到关卡」")
	if back != null:
		back.pressed.emit()
		await process_frame
	_check(not panel.is_visible_in_tree(), "能切回关卡编辑")
	_check(screen.canvas().is_visible_in_tree(), "画布回来了")

	screen.queue_free()
	await process_frame


## 在 AI 面板里输入一句话并点「生成草稿」。
## 每次都重新找控件：面板每次操作后会重建自己，旧引用会被回收。
func _ai_type_and_generate(panel: AIPanel, text: String) -> void:
	var line := panel.input_line()
	if line != null:
		line.text = text
	var generate := _find_button(panel, "生成草稿")
	if generate != null:
		generate.pressed.emit()
	await process_frame


## 属性面板是「改一下、立刻看到」的主角，必须验证它真的把改动写到了数据上。
func _test_inspector_panel() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("throwaway.ai2d.json"))
	await process_frame

	var panel := screen.inspector()
	_check(panel != null, "编辑器里有属性面板")
	if panel == null:
		screen.queue_free()
		return

	# 走真实路径：画布选中 → 通知面板
	var coin: PlacedEntity = session.current_scene().instances[6]
	session.selected_instance_id = coin.instance_id
	screen.canvas().selection_changed.emit(coin.instance_id)
	await process_frame

	_check_eq(session.selected_instance_id, coin.instance_id, "金币被选中")
	_check_eq(_find_spin_boxes(panel).size(), 4, "面板里有位置与大小共四个数字框")

	var picker := _find_color_picker(panel)
	_check(picker != null, "面板里有取色器")
	if picker != null:
		picker.color_changed.emit(Color("#ff0000"))
		_check_eq(coin.color, "#ff0000", "在面板里改颜色会写到这个对象上")
		_check_eq(session.effective_color(coin), Color("#ff0000"), "画布显示的颜色跟着变")

	# 改了一枚金币，别的金币不该跟着变
	var other: PlacedEntity = session.current_scene().instances[7]
	_check(other.color.is_empty(), "另一枚金币没有被一起改掉")

	# 撤销不能把选中一起清掉：用户按 Ctrl+Z 往往是想接着调，
	# 面板一关就得重新点一遍对象
	session.push_undo("改颜色")
	session.set_instance_color(coin.instance_id, "#00ff00")
	session.undo()
	_check_eq(session.selected_instance_id, coin.instance_id, "撤销之后对象仍然被选中")
	_check_eq(_find_spin_boxes(panel).size(), 4, "撤销之后属性面板还在，没有被关掉")

	# 撤销掉一次「新增属性」，面板上那一行也应该跟着消失
	session.push_undo("新增属性")
	session.set_instance_property(coin.instance_id, "score", 5)
	await process_frame
	_check_eq(panel.property_row_count(), 1, "新增属性后面板多出一行")
	session.undo()
	await process_frame
	_check_eq(panel.property_row_count(), 0, "撤销之后那一行跟着消失")

	# 撤销掉「放置对象」时，那个对象确实没了，选中就应该清空
	var placed := session.add_instance("ent_coin", Vector2(900, 200))
	session.undo()
	_check(placed != null and session.find_instance(placed.instance_id) == null,
		"撤销放置之后对象确实不见了")
	_check(session.selected_instance_id.is_empty(), "对象不存在了，选中被清空")

	# 屏幕按键归创作者管：选中一个键，面板里要能改它绑到哪个动作，
	# 而且写的得是"往左走"这种话，不是 ui_left。
	# 做游戏的人不该为了放一个左移键去查引擎的动作表。
	var btn := session.find_instance("i_btn_left")
	_check(btn != null, "示例里有一个左键")
	if btn != null:
		session.selected_instance_id = btn.instance_id
		screen.canvas().selection_changed.emit(btn.instance_id)
		await process_frame

		var bind_picker := _find_option_by_selected_text(panel, "往左走")
		_check(bind_picker != null, "按键的属性面板里有「按键绑定」，显示成人话")
		if bind_picker != null:
			_check_eq(_find_spin_boxes(panel).size(), 4,
				"按键跟别的对象一样，也能改位置和大小")

			var jump_index := -1
			for i in bind_picker.get_item_count():
				if bind_picker.get_item_text(i) == "跳跃":
					jump_index = i
			_check(jump_index >= 0, "下拉框里有「跳跃」这一项")
			if jump_index >= 0:
				bind_picker.item_selected.emit(jump_index)
				await process_frame
				_check_eq(session.effective_button_action(btn), "ui_accept",
					"在面板里选一下，这个键就改成跳跃了")
				_check_eq(btn.button_action, "ui_accept",
					"改的是这一个键，不是所有同类按键")
				var other_btn := session.find_instance("i_btn_right")
				_check_eq(session.effective_button_action(other_btn), "ui_right",
					"旁边的右键还是往右走")

	screen.queue_free()
	await process_frame


## 缩放如果只改视觉、不改碰撞体，那"把平台拉宽"就只是看起来宽，玩起来对不上。
func _test_runtime_instance_overrides() -> void:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	if not loaded.ok:
		_check(false, "示例工程读取失败")
		return
	var project := loaded.project
	var ground: PlacedEntity = project.scenes[0].instances[0]
	ground.scale_x = 2.0
	ground.color = "#ff0000"

	var coin: PlacedEntity = null
	for placed in project.scenes[0].instances:
		if placed.entity_id == "ent_coin":
			coin = placed
			break
	if coin != null:
		coin.scale_x = 2.0
		coin.scale_y = 1.0

	var rt := GameRuntime.new()
	rt.setup(project)
	root.add_child(rt)
	rt.start()
	await process_frame

	var actor: Actor = rt.actor_by_instance(ground.instance_id)
	_check(actor != null, "能找到被改过的地面")
	if actor != null:
		var shape_node := _find_direct_collision_shape(actor)
		_check(shape_node != null, "地面带实体碰撞体")
		if shape_node != null:
			var rect := shape_node.shape as RectangleShape2D
			_check(rect != null and is_equal_approx(rect.size.x, 256.0 * 2.0),
				"横向缩放把碰撞体也拉宽了（256 → 512）")

	# 圆形的对象横纵分别缩放之后，碰撞形状应该是椭圆而不是圆
	if coin != null:
		var coin_actor: Actor = rt.actor_by_instance(coin.instance_id)
		_check(coin_actor != null, "能找到被拉宽的金币")
		if coin_actor != null:
			var hit := _find_hitbox_shape(coin_actor)
			_check(hit != null, "金币带触发区")
			if hit != null:
				var poly := hit.shape as ConvexPolygonShape2D
				_check(poly != null, "横纵缩放不同时碰撞形状成为椭圆（多边形逼近）")
				if poly != null:
					var max_x := 0.0
					var max_y := 0.0
					for p in poly.points:
						max_x = maxf(max_x, absf(p.x))
						max_y = maxf(max_y, absf(p.y))
					_check(max_x > max_y * 1.5,
						"椭圆横向明显比纵向宽（%.1f 对 %.1f）" % [max_x, max_y])

	rt.stop()
	root.remove_child(rt)
	rt.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# 编辑器界面
# --------------------------------------------------------------------------

## 界面本身没法在无窗口环境下"看"，但可以把它的接线测出来：
## 素材栏有没有按实体列全、拖放信号有没有接到会话上。
## 这类接线一旦断了，画面看起来一切正常，就是点了没反应 —— 最难查。
func _test_editor_screen() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "编辑器能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("throwaway.ai2d.json"))
	await process_frame

	var ids := screen.palette_entity_ids()
	_check_eq(ids.size(), 7, "素材栏列出了全部 7 种实体")
	_check(ids.has("ent_player"), "素材栏里有玩家")
	_check(ids.has("ent_coin"), "素材栏里有金币")

	# 模拟从素材栏拖一个金币到画布上
	var before := session.current_scene().instances.size()
	screen.canvas().instance_placed.emit("ent_coin", Vector2(1000, 120))
	_check_eq(session.current_scene().instances.size(), before + 1, "拖放后场景里多了一个对象")
	_check_eq(session.selected_instance_id,
		session.current_scene().instances[before].instance_id, "新放下的对象自动被选中")
	_check(session.dirty, "拖放后工程标记为有未保存改动")

	screen.canvas().instance_placed.emit("ent_ground", Vector2(600, 400))
	_check_eq(session.current_scene().instances.size(), before + 2, "还能继续放别的对象")

	# 运行按钮和 F5 都必须发出 request_play。
	# 这条曾经被我写成「连了监听却什么都没断言」的假测试，
	# 结果漏掉了 app_main 里信号没接的真实故障，这里补成真检查。
	var play_requests := [0]
	screen.request_play.connect(func() -> void: play_requests[0] += 1)

	var play_button := _find_button(screen, "▶ 运行")
	_check(play_button != null, "界面上有「运行」按钮")
	if play_button != null:
		play_button.pressed.emit()
		_check_eq(play_requests[0], 1, "点「运行」按钮会发出运行请求")

	var f5 := InputEventKey.new()
	f5.keycode = KEY_F5
	f5.pressed = true
	screen._unhandled_input(f5)
	_check_eq(play_requests[0], 2, "按 F5 也会发出运行请求")

	var ctrl_z := InputEventKey.new()
	ctrl_z.keycode = KEY_Z
	ctrl_z.pressed = true
	ctrl_z.ctrl_pressed = true
	var count_before := session.current_scene().instances.size()
	screen._unhandled_input(ctrl_z)
	_check_eq(session.current_scene().instances.size(), count_before - 1, "Ctrl+Z 会撤销上一步")

	screen.queue_free()
	await process_frame


## Delete 键必须真的能删对象。
## 「处理函数写得对」和「按键真的送得到」是两回事 ——
## 前面几轮 bug 全栽在这个差别上，所以这里走真实输入管线。
func _test_delete_key() -> void:
	var session := EditSession.new()
	_check(session.open(SAMPLE_PATH), "能打开示例工程")
	if session.project == null:
		return

	var screen := EditorScreen.new()
	root.add_child(screen)
	screen.setup(session, OS.get_temp_dir().path_join("throwaway.ai2d.json"))
	await process_frame

	var victim := session.add_instance("ent_coin", Vector2(1000, 600))
	_check(victim != null, "先放一个对象作为目标")
	if victim == null:
		screen.queue_free()
		return
	session.selected_instance_id = victim.instance_id
	screen.canvas().selection_changed.emit(victim.instance_id)
	# 真实操作里一定是"先点对象、再按 Delete"，而点击会让画布拿到焦点。
	# 上一版测试漏了这一步，所以它显示"通过"却和真实情况不符。
	screen.canvas().grab_focus()
	await process_frame
	_check_eq(session.selected_instance_id, victim.instance_id, "目标已被选中")
	_check(screen.canvas().has_focus(), "画布持有焦点（与真实点击之后一致）")

	_press_key(KEY_DELETE)
	for i in 3:
		await process_frame
	_check_eq(session.find_instance(victim.instance_id), null, "按 Delete 键删掉了选中的对象")

	screen.queue_free()
	await process_frame


## 从整体上验证：启动进编辑器，发出运行请求后切到运行器。
## 这一条要是早写了，就不会出现「信号没人接」那种界面正常、点了没反应的故障。
func _test_mode_switch() -> void:
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	await process_frame
	await process_frame

	var editor := _find_editor(boot)
	_check(editor != null, "启动后默认进入编辑器")
	_check(_find_runtime(boot) == null, "此时还没有运行器")
	if editor == null:
		boot.queue_free()
		return

	# 记下编辑模式下的窗口尺寸，用来验证切换模式不会改它。
	# 中途改窗口尺寸会让 Godot 的视口和系统窗口对不上，
	# 屏幕上残留半屏旧画面，要最小化再还原才刷新 —— 用户实际遇到过。
	var size_when_editing := root.size

	# 用真实的输入管线注入一次 F5，走完整链路：
	# 按键 → 输入系统 → 编辑器 → request_play 信号 → app_main 切模式
	var f5 := InputEventKey.new()
	f5.keycode = KEY_F5
	f5.pressed = true
	Input.parse_input_event(f5)
	for i in 4:
		await process_frame
	_check(_find_runtime(boot) != null, "按 F5 之后运行器上场")
	_check(_find_editor(boot) == null, "编辑器同时退场")
	_check_eq(root.size, size_when_editing, "进入试玩不会改变窗口尺寸")

	# 光有运行器还不够 —— 场景里的对象必须真的生成了。
	# 用户报过「试玩里什么都没有，只有分数和生命」，所以这里数一数。
	var runtime := _find_runtime(boot)
	if runtime != null:
		_check_eq(runtime.alive_count(), 13, "试玩场景里生成了全部 13 个对象")
		# 游戏一律从窗口左上角画起。曾经为"居中好看"算过偏移量，
		# 而窗口尺寸在显示缩放/最大化时可能虚大，偏移会把画面推出可视区。
		_check_eq(runtime.position, Vector2.ZERO, "试玩画面不做偏移，保证一定在可视区内")

	boot.queue_free()
	await process_frame


func _find_editor(node: Node) -> EditorScreen:
	if node is EditorScreen:
		return node
	for child in node.get_children():
		var found := _find_editor(child)
		if found != null:
			return found
	return null


## 用户报「试玩之后按 Esc 回不到编辑器」。
## 看着像小事，实际是主流程卡死：回不去就再也改不了东西，只能关掉重开。
func _test_escape_returns_to_editor() -> void:
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	await process_frame
	await process_frame

	_press_key(KEY_F5)
	for i in 4:
		await process_frame
	_check(_find_runtime(boot) != null, "F5 之后进入试玩")

	_press_key(KEY_ESCAPE)
	for i in 4:
		await process_frame
	_check(_find_runtime(boot) == null, "按 Esc 之后运行器退场")
	_check(_find_editor(boot) != null, "按 Esc 之后回到编辑器")

	# 再来一遍，确认能反复来回切
	_press_key(KEY_F5)
	for i in 4:
		await process_frame
	_check(_find_runtime(boot) != null, "第二次按 F5 仍然能进试玩")
	_press_key(KEY_ESCAPE)
	for i in 4:
		await process_frame
	_check(_find_editor(boot) != null, "第二次按 Esc 仍然能回编辑")

	# 游戏结算后（屏幕上盖着结算横幅）也必须能回去
	_press_key(KEY_F5)
	for i in 4:
		await process_frame
	var runtime := _find_runtime(boot)
	if runtime != null:
		runtime.end_game("win", "测试结算")
		await process_frame
		_press_key(KEY_ESCAPE)
		for i in 4:
			await process_frame
		_check(_find_editor(boot) != null, "结算画面下按 Esc 也能回编辑")

	# 屏幕上那个按钮也必须能用 —— 演示时按快捷键容易紧张，
	# 有个点一下就能回去的按钮，比记住快捷键可靠
	_press_key(KEY_F5)
	for i in 4:
		await process_frame
	var back := _find_button(boot, "← 返回编辑  (Esc)")
	_check(back != null, "试玩界面上有「返回编辑」按钮")
	if back != null:
		back.pressed.emit()
		for i in 4:
			await process_frame
		_check(_find_editor(boot) != null, "点「返回编辑」按钮能回到编辑器")

	boot.queue_free()
	await process_frame


func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)


func _find_runtime(node: Node) -> GameRuntime:
	if node is GameRuntime:
		return node
	for child in node.get_children():
		var found := _find_runtime(child)
		if found != null:
			return found
	return null


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _make_runtime() -> GameRuntime:
	var loaded := ProjectIO.load_from_file(SAMPLE_PATH)
	var rt := GameRuntime.new()
	rt.setup(loaded.project)
	root.add_child(rt)
	rt.start()
	return rt


func _dispose_runtime(rt: GameRuntime) -> void:
	if rt == null or not is_instance_valid(rt):
		return
	rt.shutdown()
	root.remove_child(rt)
	await process_frame


func _player(rt: GameRuntime) -> Actor:
	return rt.actor_by_instance("i_player")


func _test_runtime_scene_build() -> void:
	var rt := _make_runtime()
	_check(rt.is_running(), "运行器已启动")
	_check_eq(rt.alive_count(), 13, "场景里生成了 13 个对象（5 地面 + 1 玩家 + 5 金币 + 2 尖刺）")
	_check_eq(rt.alive_count("coin"), 5, "其中金币 5 枚")
	_check(_player(rt) != null, "能按实例 ID 定位到玩家")

	await _step(60)
	var player := _player(rt)
	_check(player.is_grounded(), "玩家受重力下落后站在地面上")
	_check(player.global_position.y < 620.0, "玩家停在地面之上，没有穿过去")

	# 地面由 5 块拼成，玩家必须能平稳跨过接缝，
	# 否则平台上的一切玩法都不成立。
	# 走 300 像素后停在尖刺（x=580）之前，避免把「踩到陷阱」误判成「掉下去了」。
	# 注意要通过按键驱动，而不是直接设速度 —— 示例里有「松开方向键就停下」的规则，
	# 直接设速度会在下一帧被规则清零。
	Input.action_press("ui_right")
	await _step(60)
	Input.action_release("ui_right")
	_check(player.global_position.x > 400.0, "玩家水平移动跨过了多块地面的接缝")
	_check(player.is_grounded(), "跨过接缝后依然站在地面上，没有卡住或掉落")

	await _dispose_runtime(rt)


func _test_runtime_jump() -> void:
	var rt := _make_runtime()
	await _step(60)
	var player := _player(rt)
	_check(player.is_grounded(), "起跳前玩家在地面上")

	rt.engine_emit("tap", {})
	_check(player.velocity.y < -100.0, "点击屏幕后玩家获得向上的速度")

	await _step(12)
	_check(player.global_position.y < 570.0, "玩家确实离开了地面")

	var vy_before: float = player.velocity.y
	rt.engine_emit("tap", {})
	_check(is_equal_approx(player.velocity.y, vy_before), "空中再次点击不会二段跳")

	await _dispose_runtime(rt)


func _test_runtime_collect_and_win() -> void:
	var rt := _make_runtime()
	_last_result = ""
	_last_message = ""
	rt.game_ended.connect(_on_test_game_ended)
	await _step(30)

	_check_eq(rt.query_property("tag:player", "score"), 0, "开局分数为 0")
	_check_eq(rt.query_property("tag:player", "hp"), 3, "开局生命为 3")

	var player := _player(rt)
	var coins := rt.actors_with_tag("coin")
	_check_eq(coins.size(), 5, "开局有 5 枚金币")

	for i in coins.size():
		var coin: Actor = coins[i]
		if not is_instance_valid(coin):
			continue
		player.global_position = coin.global_position
		await _step(4)

	_check_eq(rt.query_property("tag:player", "score"), 5, "吃满 5 枚金币后分数为 5")
	_check_eq(rt.alive_count("coin"), 0, "吃过的金币都被删除了")
	_check_eq(_last_result, "win", "触发胜利结算")
	_check_eq(_last_message, "金币全部收集完成！", "结算文案来自规则里的提示文字")
	_check(not rt.is_running(), "结算后运行器停止")

	await _dispose_runtime(rt)


func _test_runtime_hazard() -> void:
	var rt := _make_runtime()
	await _step(60)
	var player := _player(rt)
	var spike := rt.actor_by_instance("i_spike_1") as Actor
	_check(spike != null, "场景里有尖刺")
	_check_eq(rt.query_property("tag:player", "hp"), 3, "开始前满血 3 点")

	# 把玩家贴到尖刺左侧：两个实体本身不重叠（不会被物理弹开），
	# 但外扩后的触发区已经相交 —— 这正是「碰到即触发」应有的判定方式。
	var body_gap := 28.0 + 24.0
	player.global_position = Vector2(spike.global_position.x - body_gap - 4.0, player.global_position.y)
	await _step(4)

	_check(rt.query_property("tag:player", "hp") < 3, "碰到尖刺后生命值下降")

	await _dispose_runtime(rt)


func _on_test_game_ended(result: String, message: String) -> void:
	_last_result = result
	_last_message = message


func _test_input_configuration() -> void:
	# 桌面端靠「鼠标模拟触摸」让鼠标点击变成触摸事件，
	# 这样鼠标与真机触屏走的是同一条代码路径。
	# 这个开关一旦被改掉，点击跳跃会静默失效，因此必须有测试守着。
	_check(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false) == true,
		"已开启鼠标模拟触摸")


func _test_runtime_background() -> void:
	var rt := _make_runtime()
	# 工程配置里是 #0b1220，场景没有单独覆盖，应当直接沿用
	var expected := Color(rt.project.config.background_color)
	_check(rt.background_color().is_equal_approx(expected),
		"运行器应用了工程配置的背景色 %s" % rt.project.config.background_color)
	await _dispose_runtime(rt)


func _test_runtime_input_path() -> void:
	var rt := _make_runtime()
	await _step(60)
	var player := _player(rt)
	_check(player.is_grounded(), "起跳前玩家在地面上")

	# 推一个真实的触摸事件进引擎，验证「输入 → 事件 → 规则 → 物理」整条链路，
	# 而不是绕过输入直接调用引擎。
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(640.0, 360.0)
	Input.parse_input_event(touch)
	await _step(3)

	_check(player.velocity.y < -100.0, "真实触摸事件能触发跳跃规则")
	_check(not player.is_grounded(), "玩家离开地面")

	# 必须配对松开，否则这个触摸索引会一直被认为处于按下状态，
	# 后续用例再推同样索引的事件就会被引擎忽略。
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = Vector2(640.0, 360.0)
	Input.parse_input_event(release)
	await _step(2)

	await _dispose_runtime(rt)


func _test_runtime_movement() -> void:
	var rt := _make_runtime()
	await _step(60)
	var player := _player(rt)
	var start_x: float = player.global_position.x
	_check(is_equal_approx(player.velocity.x, 0.0), "没有按键时水平速度为 0")

	Input.action_press("ui_right")
	await _step(30)
	_check(player.velocity.x > 0.0, "按住右键后获得向右的速度")
	_check(player.global_position.x > start_x + 100.0, "玩家确实向右移动了足够距离")
	_check(player.is_grounded(), "水平移动过程中始终站在地面上")
	Input.action_release("ui_right")

	await _step(5)
	_check(is_equal_approx(player.velocity.x, 0.0), "松开按键后立刻停下，不会一直滑行")

	Input.action_press("ui_left")
	await _step(20)
	_check(player.velocity.x < 0.0, "按住左键后获得向左的速度")
	Input.action_release("ui_left")
	await _step(5)

	await _dispose_runtime(rt)
