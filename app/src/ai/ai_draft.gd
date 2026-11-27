## AI 给出的一份「草稿」：还没进工程，等人点了「应用」才生效。
##
## 为什么非要有这一层：AI 的产出必须能被否决。要是它直接改工程，
## 用户既看不懂它做了什么，也没机会在动手之前先看一眼 ——
## 对着一个自己没看懂的结果按"撤销"，是种很糟的体验。
##
## 草稿是可以读、可以扔的。人点头，它才变成工程里的一部分。
class_name AIDraft
extends RefCounted

## 给用户看的一句话标题，例如「紫色飞行小怪」
var title: String = ""
## 人话预告：我打算往工程里加什么。一行一条，按顺序念给用户听。
var steps: PackedStringArray = PackedStringArray()
## 要新增的实体定义。结构就是 JSON 里 `entities` 那一项的样子。
var entities: Array[Dictionary] = []
## 要新增的规则。结构就是 JSON 里 `rules` 那一项的样子。
var rules: Array[Dictionary] = []
## 要在当前关卡里摆出来的对象：{ "entity_id": ..., "x": ..., "y": ... }
var placements: Array[Dictionary] = []
## 生成不出来的原因（"这句我没听懂"之类）。非空就表示这份草稿不能用。
var error: String = ""
## 来自哪里：offline / remote。界面上要如实标出来。
var source: String = "offline"


## 这份草稿能不能用。空草稿（什么都没生成）也算不能用。
func ok() -> bool:
	if not error.is_empty():
		return false
	return not (entities.is_empty() and rules.is_empty() and placements.is_empty())


## 草稿的内容（给测试用来比较"两次生成是不是一模一样"，也方便调试打印）
func to_dict() -> Dictionary:
	return {
		"title": title,
		"steps": Array(steps),
		"entities": entities.duplicate(true),
		"rules": rules.duplicate(true),
		"placements": placements.duplicate(true),
		"error": error,
	}


## 生成一份"我做不到"的草稿，把原因说清楚。
static func failure(reason: String) -> AIDraft:
	var draft := AIDraft.new()
	draft.error = reason
	return draft
