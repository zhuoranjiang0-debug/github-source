## 屏幕按键的显示。
##
## 只负责画，不负责判定 —— 按下的判定在 GameRuntime 里，
## 因为那里才知道每一根手指落在哪、以及要不要吞掉这次触摸。
class_name ScreenButtons
extends Node2D

const FONT_SIZE := 34
## 方向键画成箭头而不是文字 —— 箭头是通用的，不用认识字也知道往哪走
const ARROW_COLOR := Color(1, 1, 1, 0.92)

## 每个元素：{ action, label, color, rect, pressed }
var buttons: Array[Dictionary] = []


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for button in buttons:
		var rect: Rect2 = button["rect"]
		var style: StyleBoxFlat = button["style"]
		# 圆角、边框、以及按下时提亮，全都写在样式里，由数据层维护。
		# 触屏上没有按下的反馈，用户会怀疑自己到底按到没有 —— 这点反馈很值钱。
		draw_style_box(style, rect)

		match String(button.get("arrow", "")):
			"left":
				_draw_arrow(rect.get_center(), Vector2.LEFT, rect.size.y * 0.22)
			"right":
				_draw_arrow(rect.get_center(), Vector2.RIGHT, rect.size.y * 0.22)
			"up":
				_draw_arrow(rect.get_center(), Vector2.UP, rect.size.y * 0.22)
			"down":
				_draw_arrow(rect.get_center(), Vector2.DOWN, rect.size.y * 0.22)
			_:
				_draw_label(font, rect, String(button.get("label", "")))


func _draw_label(font: Font, rect: Rect2, text: String) -> void:
	if text.is_empty() or font == null:
		return
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var baseline := rect.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.35)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ARROW_COLOR)


## 一个实心三角。用多边形画，比塞个图标资源轻，也省得依赖素材。
func _draw_arrow(center: Vector2, direction: Vector2, size: float) -> void:
	var tip := center + direction * size
	var side := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([
		tip,
		center - direction * size * 0.55 + side * size * 0.85,
		center - direction * size * 0.55 - side * size * 0.85,
	])
	draw_colored_polygon(points, ARROW_COLOR)
