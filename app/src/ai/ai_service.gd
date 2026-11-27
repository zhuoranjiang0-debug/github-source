## AI 服务的统一入口。上层只认这一层，不关心背后是谁在算。
##
## 为什么要有这一层：
##
## 1. **断网也能演。** 离线生成器永远在，联网只会让它更聪明，不会让它变成必需。
## 2. **换模型不改上层。** 主流厂商（智谱 / 通义 / DeepSeek…）和本地跑的
##    llama.cpp 都给 OpenAI 兼容的 HTTP 接口，将来接真模型时，
##    上层这一套调用方式一个字都不用改。
## 3. **key 的边界很清楚。** 在线那条路用的是使用者自己填的 key，
##    只存在他的本机，绝不写进工程文件、也绝不打进分发的程序里。
class_name AIService
extends RefCounted

const MODE_OFFLINE := "offline"
## 在线模型这一版还没接（排在 M4-c）。位置先留好，别让上层以为它不存在。
const MODE_REMOTE := "remote"

var mode: String = MODE_OFFLINE

var _offline := OfflineProvider.new()


## 界面上要如实写出"现在用的是哪一种"。
## 不写的话，用户会觉得"这工具怎么有时候灵有时候不灵"。
func mode_label() -> String:
	if mode == MODE_REMOTE:
		return "在线模型"
	return "离线生成（不联网、不花钱）"


## 状态行下面那行小字：说清现在的能力边界，以及怎么变强。
func mode_hint() -> String:
	if mode == MODE_REMOTE:
		return "用的是你自己填的 key，不写进工程、不外传"
	return "接在线模型需要填自己的 key —— 这一版还没做（排在后面）"


func is_remote() -> bool:
	return mode == MODE_REMOTE


## 唯一的对外入口：一句人话 + 当前工程 → 一份草稿。
##
## 传 project 进来是有意的：生成器要看工程里已经有什么，
## 能复用的就复用（例如工程里已有"碰到危险物扣血"，新敌人才不用再配一条）。
func draft(prompt: String, project: GameProject) -> AIDraft:
	# 在线那条路以后在这里分叉：失败、超时、没填 key，全都落回离线，
	# 用户顶多感觉"今天它笨一点"，不会卡住、也不会看到报错弹窗。
	var result := _offline.draft(prompt, project)
	result.source = mode
	return result
