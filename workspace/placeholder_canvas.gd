@tool
extends Control
class_name EditorPlaceholderCanvas

## 中央占位区域的纯视觉背景。
##
## 这个控件只绘制网格和中心参考线，用来观察中央 Workspace 的边界和伸缩行为。
## 它不代表 Node Map，也不包含任何领域对象或编辑操作。

var line_color: Color = Color("#26343d")
var major_line_color: Color = Color("#31434d")
var center_line_color: Color = Color("#4e6874")

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#10171c"))
    var grid_step := 32.0
    var major_step := grid_step * 4.0
    var x := 0.0
    while x <= size.x:
        var is_major := is_zero_approx(fmod(x, major_step))
        draw_line(Vector2(x, 0), Vector2(x, size.y), major_line_color if is_major else line_color, 1.0)
        x += grid_step

    var y := 0.0
    while y <= size.y:
        var is_major := is_zero_approx(fmod(y, major_step))
        draw_line(Vector2(0, y), Vector2(size.x, y), major_line_color if is_major else line_color, 1.0)
        y += grid_step

    var center := size * 0.5
    draw_line(Vector2(center.x, 0), Vector2(center.x, size.y), center_line_color, 1.0)
    draw_line(Vector2(0, center.y), Vector2(size.x, center.y), center_line_color, 1.0)
