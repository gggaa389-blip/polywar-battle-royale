class_name Island
extends Node3D
# الجزيرة: تضاريس Terrain3D المُصدَّرة (GLB) + مياه + منازل قابلة للدخول + أشجار وصخور + نقاط الغنائم

const GRID := 513
const STEP := 4.0
const HALF := 1024.0
const CELL := 40.0
const WALL_H := 3.4
const WALL_T := 0.3
const DOOR_W := 2.0

var heights := PackedFloat32Array()
var root_gltf: Node3D
var cities: Array = []        # {x,z,r,name}
var houses: Array = []        # {x,z,sx,sz,y0,minx,maxx,minz,maxz}
var loot_spots: Array = []    # Vector3
var grid := {}                # Vector2i -> Array[Dictionary] (obstacles)
var obstacle_count := 0
var rng := RandomNumberGenerator.new()

func build() -> void:
	rng.seed = 20261105
	var ps := load("res://assets/map/island.glb") as PackedScene
	root_gltf = ps.instantiate() as Node3D
	add_child(root_gltf)
	_read_heights()
	_add_water()
	_load_meta()
	_build_houses()
	_build_nature()
	_build_loot_spots()

func _largest_mesh(n: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_n := -1
	var stack: Array = [n]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var cnt: int = (c as MeshInstance3D).mesh.surface_get_array_len(0)
			if cnt > best_n:
				best_n = cnt
				best = c
		for k in c.get_children():
			stack.append(k)
	return best

func _read_heights() -> void:
	heights.resize(GRID * GRID)
	heights.fill(0.0)
	var mi := _largest_mesh(root_gltf)
	if mi == null:
		push_error("island mesh missing")
		return
	var arrs: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var xf := mi.transform
	for v in verts:
		var w: Vector3 = xf * v
		var ix := clampi(int(round((w.x + HALF) / STEP)), 0, GRID - 1)
		var iz := clampi(int(round((w.z + HALF) / STEP)), 0, GRID - 1)
		heights[iz * GRID + ix] = w.y

func height_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, GRID - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, GRID - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[iz * GRID + ix]
	var h10 := heights[iz * GRID + ix + 1]
	var h01 := heights[(iz + 1) * GRID + ix]
	var h11 := heights[(iz + 1) * GRID + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func slope_at(x: float, z: float) -> float:
	var a := height_at(x + 3.0, z) - height_at(x - 3.0, z)
	var b := height_at(x, z + 3.0) - height_at(x, z - 3.0)
	return sqrt(a * a + b * b) / 6.0

func _add_water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4400, 4400)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.38, 0.58, 0.92)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.1
	mi.material_override = m
	mi.position = Vector3(0, 0.0, 0)
	add_child(mi)

func _load_meta() -> void:
	var f := FileAccess.open("res://assets/map/map_meta.json", FileAccess.READ)
	if f == null:
		push_error("map_meta missing")
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for c in d.get("cities", []):
		cities.append({"x": float(c["x"]), "z": float(c["z"]), "r": float(c.get("radius", 90.0)), "name": String(c.get("name", "city"))})

func _wall_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

func _add_obstacle_box(mn: Vector3, mx: Vector3) -> void:
	var o := {"t": 0, "minx": mn.x, "maxx": mx.x, "miny": mn.y, "maxy": mx.y, "minz": mn.z, "maxz": mx.z}
	_insert(o, mn.x, mx.x, mn.z, mx.z)

func _add_obstacle_circle(cx: float, cz: float, r: float, top: float) -> void:
	var o := {"t": 1, "cx": cx, "cz": cz, "r": r, "miny": 0.0, "maxy": top}
	_insert(o, cx - r, cx + r, cz - r, cz + r)

func _insert(o: Dictionary, x0: float, x1: float, z0: float, z1: float) -> void:
	obstacle_count += 1
	var ix0 := int(floor(x0 / CELL))
	var ix1 := int(floor(x1 / CELL))
	var iz0 := int(floor(z0 / CELL))
	var iz1 := int(floor(z1 / CELL))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var k := Vector2i(ix, iz)
			if not grid.has(k):
				grid[k] = []
			(grid[k] as Array).append(o)

func obstacles_near(x: float, z: float, rad: float) -> Array:
	var out: Array = []
	var ix0 := int(floor((x - rad) / CELL))
	var ix1 := int(floor((x + rad) / CELL))
	var iz0 := int(floor((z - rad) / CELL))
	var iz1 := int(floor((z + rad) / CELL))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var k := Vector2i(ix, iz)
			if grid.has(k):
				out.append_array(grid[k])
	return out

func _build_houses() -> void:
	var wall_cols := [Color(0.82, 0.76, 0.66), Color(0.66, 0.72, 0.78), Color(0.78, 0.6, 0.45), Color(0.7, 0.78, 0.66)]
	var roof_mat := _wall_mat(Color(0.42, 0.2, 0.16))
	var floor_mat := _wall_mat(Color(0.5, 0.42, 0.34))
	var houses_root := Node3D.new()
	houses_root.name = "Houses"
	add_child(houses_root)
	for c in cities:
		var cx: float = c["x"]
		var cz: float = c["z"]
		var cr: float = c["r"]
		var n := 12 + int(cr / 12.0)
		var placed := 0
		var tries := 0
		while placed < n and tries < 1500:
			tries += 1
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * (cr - 14.0)
			var x := cx + cos(ang) * rad
			var z := cz + sin(ang) * rad
			var ok := true
			for h in houses:
				if Vector2(h["x"] - x, h["z"] - z).length() < 19.0:
					ok = false
					break
			if not ok:
				continue
			var sx := rng.randf_range(8.0, 11.0)
			var sz := rng.randf_range(7.0, 9.0)
			if rng.randf() < 0.5:
				var t := sx
				sx = sz
				sz = t
			# أرض مستوية تحت المنزل: نرفض الأرض المائلة، والأرضية تُرفع لأعلى نقطة تحت البيت
			var mn := 1e9
			var mx := -1e9
			var fx := x - sx * 0.5
			while fx <= x + sx * 0.5:
				var fz := z - sz * 0.5
				while fz <= z + sz * 0.5:
					var hy := height_at(fx, fz)
					mn = minf(mn, hy)
					mx = maxf(mx, hy)
					fz += 1.0
				fx += 1.0
			if mx - mn > 0.35 or mn < 2.0:
				continue
			var y0 := mx
			var hs := _house(x, z, sx, sz, y0, wall_cols[rng.randi() % wall_cols.size()], roof_mat, floor_mat, houses_root)
			houses.append(hs)
			placed += 1

func _house(x: float, z: float, sx: float, sz: float, y0: float, wall_col: Color, roof_mat: Material, floor_mat: Material, parent: Node3D) -> Dictionary:
	var wm := _wall_mat(wall_col)
	var root := Node3D.new()
	root.position = Vector3(x, y0, z)
	parent.add_child(root)
	var t := WALL_T
	var H := WALL_H
	# أرضية وسقف
	_box(root, Vector3(sx, 0.2, sz), Vector3(0, 0.1, 0), floor_mat)
	_box(root, Vector3(sx + 0.6, 0.35, sz + 0.6), Vector3(0, H + 0.17, 0), roof_mat)
	# جدار شمالي وجنوبي وشرقي وغربي، مع فتحة باب في الجدار الجنوبي (z = -sz/2)
	_box(root, Vector3(sx, H, t), Vector3(0, H * 0.5, sz * 0.5 - t * 0.5), wm)
	_add_obstacle_box(Vector3(x - sx * 0.5, y0, z + sz * 0.5 - t), Vector3(x + sx * 0.5, y0 + H, z + sz * 0.5))
	var seg := (sx - DOOR_W) * 0.5
	var lx := -sx * 0.5 + seg * 0.5
	var rx := sx * 0.5 - seg * 0.5
	_box(root, Vector3(seg, H, t), Vector3(lx, H * 0.5, -sz * 0.5 + t * 0.5), wm)
	_box(root, Vector3(seg, H, t), Vector3(rx, H * 0.5, -sz * 0.5 + t * 0.5), wm)
	_add_obstacle_box(Vector3(x - sx * 0.5, y0, z - sz * 0.5), Vector3(x - DOOR_W * 0.5, y0 + H, z - sz * 0.5 + t))
	_add_obstacle_box(Vector3(x + DOOR_W * 0.5, y0, z - sz * 0.5), Vector3(x + sx * 0.5, y0 + H, z - sz * 0.5 + t))
	_box(root, Vector3(DOOR_W, H - 2.6, t), Vector3(0, 2.6 + (H - 2.6) * 0.5, -sz * 0.5 + t * 0.5), wm)
	_box(root, Vector3(t, H, sz), Vector3(-sx * 0.5 + t * 0.5, H * 0.5, 0), wm)
	_add_obstacle_box(Vector3(x - sx * 0.5, y0, z - sz * 0.5 + t), Vector3(x - sx * 0.5 + t, y0 + H, z + sz * 0.5 - t))
	_box(root, Vector3(t, H, sz), Vector3(sx * 0.5 - t * 0.5, H * 0.5, 0), wm)
	_add_obstacle_box(Vector3(x + sx * 0.5 - t, y0, z - sz * 0.5 + t), Vector3(x + sx * 0.5, y0 + H, z + sz * 0.5 - t))
	# نوافذ بسيطة (ألواح داكنة) على الجدار الشرقي
	_box(root, Vector3(0.05, 1.0, 1.4), Vector3(sx * 0.5 + 0.02, 1.7, 0), _wall_mat(Color(0.18, 0.24, 0.3)))
	return {"x": x, "z": z, "sx": sx, "sz": sz, "y0": y0,
		"minx": x - sx * 0.5, "maxx": x + sx * 0.5, "minz": z - sz * 0.5, "maxz": z + sz * 0.5}

func house_at(x: float, z: float) -> Dictionary:
	for h in houses:
		if x >= h["minx"] and x <= h["maxx"] and z >= h["minz"] and z <= h["maxz"]:
			return h
	return {}

func _build_nature() -> void:
	var trunk_mm := MultiMeshInstance3D.new()
	var canopy_mm := MultiMeshInstance3D.new()
	var rock_mm := MultiMeshInstance3D.new()
	add_child(trunk_mm)
	add_child(canopy_mm)
	add_child(rock_mm)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.3
	cyl.height = 3.4
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.0
	cone.height = 4.6
	var rock := SphereMesh.new()
	rock.radius = 1.2
	rock.height = 1.8
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.mesh = cyl
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.mesh = cone
	var rm := MultiMesh.new()
	rm.transform_format = MultiMesh.TRANSFORM_3D
	rm.mesh = rock
	var trees: Array = []
	var rocks: Array = []
	var tries := 0
	while (trees.size() < 1100 or rocks.size() < 260) and tries < 40000:
		tries += 1
		var x := rng.randf_range(-HALF + 20.0, HALF - 20.0)
		var z := rng.randf_range(-HALF + 20.0, HALF - 20.0)
		var h := height_at(x, z)
		if h < 2.0 or slope_at(x, z) > 0.8:
			continue
		if _in_city(x, z, 24.0):
			continue
		if rocks.size() < 260 and rng.randf() < 0.2 and slope_at(x, z) > 0.3:
			rocks.append(Vector3(x, h, z))
		elif trees.size() < 1100:
			trees.append(Vector3(x, h, z))
	tm.instance_count = trees.size()
	cm.instance_count = trees.size()
	for i in trees.size():
		var p: Vector3 = trees[i]
		var s := rng.randf_range(0.8, 1.3)
		tm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(p.x, p.y + 1.7 * s, p.z)))
		cm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(p.x, p.y + 4.3 * s, p.z)))
		_add_obstacle_circle(p.x, p.z, 0.45, 3.0)
	rm.instance_count = rocks.size()
	for i in rocks.size():
		var p: Vector3 = rocks[i]
		var s := rng.randf_range(0.8, 1.6)
		rm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), Vector3(p.x, p.y + 0.4 * s, p.z)))
		_add_obstacle_circle(p.x, p.z, 1.0 * s, 1.2)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.28, 0.2, 0.12)
	trunk_mm.multimesh = tm
	trunk_mm.material_override = gm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.13, 0.42, 0.16)
	canopy_mm.multimesh = cm
	canopy_mm.material_override = lm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.45, 0.45, 0.43)
	rock_mm.multimesh = rm
	rock_mm.material_override = sm

func _in_city(x: float, z: float, pad: float) -> bool:
	for c in cities:
		if Vector2(x - c["x"], z - c["z"]).length() < float(c["r"]) + pad:
			return true
	return false

func _build_loot_spots() -> void:
	for h in houses:
		var k := 1 + rng.randi() % 3
		for i in k:
			var x: float = h["x"] + rng.randf_range(-h["sx"] * 0.3, h["sx"] * 0.3)
			var z: float = h["z"] + rng.randf_range(-h["sz"] * 0.3, h["sz"] * 0.3)
			loot_spots.append(Vector3(x, h["y0"], z))
	var tries := 0
	while loot_spots.size() < 520 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-HALF + 30.0, HALF - 30.0)
		var z := rng.randf_range(-HALF + 30.0, HALF - 30.0)
		if height_at(x, z) < 1.5 or slope_at(x, z) > 0.5:
			continue
		loot_spots.append(Vector3(x, height_at(x, z), z))

func blocked(x: float, z: float, y: float, r: float) -> bool:
	# يتحقق من الاصطدام الأفقي لجسم عند (x,y,z) بنصف قطر r
	if y < -0.5:
		return false
	for o in obstacles_near(x, z, r + 1.0):
		if float(o["maxy"]) <= y + 0.05 or float(o["miny"]) >= y + 1.7:
			continue
		if o["t"] == 0:
			if x > float(o["minx"]) - r and x < float(o["maxx"]) + r and z > float(o["minz"]) - r and z < float(o["maxz"]) + r:
				return true
		else:
			if Vector2(x - float(o["cx"]), z - float(o["cz"])).length() < float(o["r"]) + r:
				return true
	return false

func push_out(p: Vector3, r: float, y_top: float) -> Vector3:
	# يدفع النقطة خارج العوائق الأفقية (لا تأثير على الأجسام فوق الارتفاع)
	var out := p
	for _iter in 2:
		for o in obstacles_near(out.x, out.z, r + 1.0):
			if float(o["maxy"]) <= out.y + 0.05 or float(o["miny"]) >= y_top:
				continue
			if o["t"] == 0:
				var mnx := float(o["minx"]) - r
				var mxx := float(o["maxx"]) + r
				var mnz := float(o["minz"]) - r
				var mxz := float(o["maxz"]) + r
				if out.x > mnx and out.x < mxx and out.z > mnz and out.z < mxz:
					var d := [out.x - mnx, mxx - out.x, out.z - mnz, mxz - out.z]
					var m := 0
					for i in 4:
						if d[i] < d[m]:
							m = i
					match m:
						0: out.x = mnx
						1: out.x = mxx
						2: out.z = mnz
						3: out.z = mxz
			else:
				var cxx := float(o["cx"])
				var czz := float(o["cz"])
				var rr := float(o["r"]) + r
				var v := Vector2(out.x - cxx, out.z - czz)
				var l := v.length()
				if l < rr:
					var dir := v / l if l > 0.0001 else Vector2(1, 0)
					out.x = cxx + dir.x * rr
					out.z = czz + dir.y * rr
	return out

func solid_at(x: float, y: float, z: float) -> bool:
	# هل النقطة داخل عائق صلب (جدار/صخرة/جذع)؟ تُستخدم لتتبع الرصاص
	for o in obstacles_near(x, z, 0.2):
		if y < float(o["miny"]) or y > float(o["maxy"]):
			continue
		if o["t"] == 0:
			if x >= float(o["minx"]) and x <= float(o["maxx"]) and z >= float(o["minz"]) and z <= float(o["maxz"]):
				return true
		else:
			if Vector2(x - float(o["cx"]), z - float(o["cz"])).length() <= float(o["r"]):
				return true
	return false
