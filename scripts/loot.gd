class_name LootItem
extends Node3D
# غنيمة على الأرض: سلاح / ذخيرة / طبي / ضماد

var kind := ""
var id := ""
var n := 0
var uid := 0

const COLORS := {
	"weapon": Color(0.95, 0.7, 0.15),
	"ammo": Color(0.3, 0.6, 0.95),
	"med": Color(0.95, 0.25, 0.3),
	"band": Color(0.95, 0.9, 0.9),
}

static func make(parent: Node, p_kind: String, p_id: String, p_n: int, p: Vector3) -> LootItem:
	var li := LootItem.new()
	li.kind = p_kind
	li.id = p_id
	li.n = p_n
	li.position = Vector3(p.x, p.y + 0.15, p.z)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.22, 0.38)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS.get(p_kind, Color.WHITE)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.35
	mi.material_override = mat
	li.add_child(mi)
	var lb := Label3D.new()
	lb.text = li.display_name()
	lb.font_size = 40
	lb.pixel_size = 0.007
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.position = Vector3(0, 0.6, 0)
	li.add_child(lb)
	parent.add_child(li)
	return li

func display_name() -> String:
	match kind:
		"weapon":
			return String(Cfg.WEAPONS[id]["name"]) + " (" + str(n) + ")"
		"ammo":
			return String(Cfg.AMMO_NAMES[id]) + " x" + str(n)
		"med":
			return "حقيبة إسعاف"
		"band":
			return "ضماد"
	return kind

func refresh() -> void:
	var lb := get_child(1) as Label3D
	if lb != null:
		lb.text = display_name()
