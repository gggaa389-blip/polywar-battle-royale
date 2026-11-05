class_name MenuUI
extends CanvasLayer
# القوائم: الرئيسية (فردي / أصدقاء)، الشبكة (استضافة/انضمام)، الغرفة، ولوحات النتائج

signal start_pressed
signal host_pressed
signal join_pressed(ip: String)
signal start_net_pressed
signal leave_pressed
signal back_pressed
signal continue_pressed
signal sens_changed(v: float)

var root: Control
var main_panel: VBoxContainer
var net_panel: VBoxContainer
var lobby_panel: VBoxContainer
var end_panel: PanelContainer
var end_title: Label
var end_body: Label
var end_btn: Button
var cont_btn: Button
var bg: ColorRect
var status: Label
var ip_edit: LineEdit
var lobby_list: Label
var lobby_info: Label
var start_net_btn: Button

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	bg = ColorRect.new()
	bg.color = Color(0.05, 0.09, 0.12, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	main_panel = _column(Vector2(-220, -250))
	main_panel.add_child(_lbl("باتل رويال — الجزيرة", 40))
	main_panel.add_child(_lbl("50 لاعباً ينزلون من الطائرة — الأخير على قيد الحياة يفوز", 18))
	var b1 := _btn("لعب فردي ضد 49 لاعباً")
	b1.pressed.connect(func(): start_pressed.emit())
	main_panel.add_child(b1)
	var b2 := _btn("مع الأصدقاء (شبكة محلية)")
	b2.pressed.connect(func(): _show(net_panel))
	main_panel.add_child(b2)
	var row := HBoxContainer.new()
	row.add_child(_lbl("الحساسية", 18))
	var sl := HSlider.new()
	sl.min_value = 0.3
	sl.max_value = 2.0
	sl.step = 0.05
	sl.value = 1.0
	sl.custom_minimum_size = Vector2(260, 30)
	sl.value_changed.connect(func(v: float): sens_changed.emit(v))
	row.add_child(sl)
	main_panel.add_child(row)
	main_panel.add_child(_lbl("اللمس: اسحب يساراً للحركة، ويميناً للنظر. الفأرة: WASD + Space، مسار الفأرة للنظر، زر أيسر للإطلاق، أيمن للتصويب، R تعبئة، F التقاط، C جلوس، Q تبديل.", 14))

	net_panel = _column(Vector2(-220, -200))
	net_panel.add_child(_lbl("اللعب مع الأصدقاء عبر نفس الواي فاي", 26))
	net_panel.add_child(_lbl("شخص واحد يضغط استضافة، والباقون يدخلون عنوان IP للجهاز المضيف (يظهر في الغرفة).", 16))
	var hb := _btn("استضافة مباراة")
	hb.pressed.connect(func(): host_pressed.emit())
	net_panel.add_child(hb)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "عنوان المضيف مثل 192.168.1.5"
	ip_edit.custom_minimum_size = Vector2(440, 48)
	net_panel.add_child(ip_edit)
	var jb := _btn("انضمام")
	jb.pressed.connect(func(): join_pressed.emit(ip_edit.text.strip_edges()))
	net_panel.add_child(jb)
	var bk := _btn("رجوع")
	bk.pressed.connect(func(): show_main())
	net_panel.add_child(bk)
	status = _lbl("", 16)
	net_panel.add_child(status)

	lobby_panel = _column(Vector2(-220, -200))
	lobby_panel.add_child(_lbl("غرفة المباراة", 30))
	lobby_info = _lbl("", 16)
	lobby_panel.add_child(lobby_info)
	lobby_list = _lbl("", 22)
	lobby_panel.add_child(lobby_list)
	start_net_btn = _btn("ابدأ المباراة")
	start_net_btn.pressed.connect(func(): start_net_pressed.emit())
	lobby_panel.add_child(start_net_btn)
	var lb := _btn("مغادرة الغرفة")
	lb.pressed.connect(func(): leave_pressed.emit())
	lobby_panel.add_child(lb)

	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.custom_minimum_size = Vector2(480, 0)
	end_panel.position = Vector2(-240, -150)
	end_panel.visible = false
	root.add_child(end_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	end_panel.add_child(v)
	end_title = _lbl("", 34)
	v.add_child(end_title)
	end_body = _lbl("", 20)
	v.add_child(end_body)
	cont_btn = _btn("متابعة المشاهدة")
	cont_btn.pressed.connect(func(): continue_pressed.emit())
	v.add_child(cont_btn)
	end_btn = _btn("العودة للقائمة")
	end_btn.pressed.connect(func(): back_pressed.emit())
	v.add_child(end_btn)
	show_main()

func _column(pos: Vector2) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.custom_minimum_size = Vector2(440, 0)
	c.position = pos
	c.add_theme_constant_override("separation", 14)
	c.visible = false
	root.add_child(c)
	return c

func _lbl(t: String, sz: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _btn(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(440, 56)
	b.add_theme_font_size_override("font_size", 22)
	return b

func _show(p: Control) -> void:
	bg.visible = true
	main_panel.visible = p == main_panel
	net_panel.visible = p == net_panel
	lobby_panel.visible = p == lobby_panel
	end_panel.visible = false

func show_main() -> void:
	_show(main_panel)

func show_net() -> void:
	_show(net_panel)

func set_status(t: String) -> void:
	status.text = t

func show_lobby(is_host: bool, ips: PackedStringArray) -> void:
	_show(lobby_panel)
	start_net_btn.visible = is_host
	if is_host:
		lobby_info.text = "أنت المضيف. عناوين الشبكة: " + (", ".join(ips) if ips.size() > 0 else "غير معروفة")
	else:
		lobby_info.text = "بانتظار المضيف لبدء المباراة..."

func update_lobby(names: PackedStringArray) -> void:
	lobby_list.text = "اللاعبون (%d):\n%s" % [names.size(), "\n".join(names)]

func show_hud_overlay(title: String, body: String, can_continue: bool) -> void:
	bg.visible = false
	main_panel.visible = false
	net_panel.visible = false
	lobby_panel.visible = false
	end_panel.visible = true
	end_title.text = title
	end_body.text = body
	cont_btn.visible = can_continue
	end_btn.text = "العودة للقائمة"

func hide_overlay() -> void:
	bg.visible = false
	main_panel.visible = false
	net_panel.visible = false
	lobby_panel.visible = false
	end_panel.visible = false

func show_end(title: String, body: String) -> void:
	show_hud_overlay(title, body, false)
