class_name Fx
extends RefCounted
# مؤثرات بصرية: دم، شرر، خط الرصاصة. كلها تُحذف تلقائياً.

static func blood_burst(parent: Node3D, p: Vector3, headshot: bool) -> void:
	var pa := CPUParticles3D.new()
	pa.position = p
	pa.amount = 24 if headshot else 14
	pa.one_shot = true
	pa.explosiveness = 1.0
	pa.lifetime = 0.6
	pa.direction = Vector3(0, 1, 0)
	pa.spread = 180.0
	pa.initial_velocity_min = 1.5
	pa.initial_velocity_max = 4.0
	pa.gravity = Vector3(0, -9.8, 0)
	pa.scale_amount_min = 0.6
	pa.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.02, 0.02)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.0, 0.0)
	sm.material = mat
	pa.mesh = sm
	parent.add_child(pa)
	pa.emitting = true
	_free_later(pa, 1.2)

static func blood_pool(parent: Node3D, p: Vector3, gy: float) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	var r := randf_range(0.5, 0.9)
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = 0.02
	cy.radial_segments = 14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.02, 0.02, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cy.material = mat
	mi.mesh = cy
	mi.position = Vector3(p.x, gy + 0.02, p.z)
	mi.rotation.y = randf() * TAU
	parent.add_child(mi)
	_free_later(mi, 60.0)

static func spark(parent: Node3D, p: Vector3) -> void:
	var pa := CPUParticles3D.new()
	pa.position = p
	pa.amount = 8
	pa.one_shot = true
	pa.explosiveness = 1.0
	pa.lifetime = 0.35
	pa.spread = 180.0
	pa.initial_velocity_min = 1.0
	pa.initial_velocity_max = 2.5
	pa.gravity = Vector3(0, -6.0, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.8, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	sm.material = mat
	pa.mesh = sm
	parent.add_child(pa)
	pa.emitting = true
	_free_later(pa, 0.8)

static func tracer(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.2:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, L)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	parent.add_child(mi)
	var up := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(d.normalized(), up), (a + b) * 0.5)
	_free_later(mi, 0.07)

static func _free_later(n: Node, secs: float) -> void:
	var tw := n.create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(n.queue_free)
