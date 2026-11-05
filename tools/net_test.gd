extends SceneTree
# اختبار الشبكة: مضيف + عميل على نفس الجهاز (ENet). يتحقق من اللقطات والمدخلات والمصالحة.

var role := "host"
var lan: Lan
var isl: Island
var m: BRMatch
var started := false
var t := 0.0
var clock := 0.0
var snaps := 0
var inputs_in := 0
var evs_seen := 0
var max_diff := 0.0
var sum_diff := 0.0
var diff_n := 0
var remote_moves := 0.0
var frame := 0
var host_started := false
var tick_host := 0.0
var fails := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	isl = Island.new()
	root.add_child(isl)
	isl.build()
	lan = Lan.new()
	lan.name = "Lan"
	root.add_child(lan)
	lan.started.connect(_on_started)
	lan.snapshot_in.connect(_on_snap)
	lan.events_in.connect(_on_events)
	lan.input_in.connect(_on_input)

func _on_started(seed_v: int, names: PackedStringArray, slot: int) -> void:
	m = BRMatch.new()
	m.is_client = role == "client"
	root.add_child(m)
	m.setup(isl, names.size(), names, seed_v, slot)
	m.start()
	started = true
	print("STARTED role=%s slot=%d humans=%d seed=%d" % [role, slot, names.size(), seed_v])

func _on_snap(d: PackedFloat32Array) -> void:
	snaps += 1
	if m == null or role != "client" or m.human == null:
		return
	var b := Cfg.NET_SNAP_HEADER + m.human.id * Cfg.NET_SNAP_STRIDE
	var hp := Vector3(d[b], d[b + 1], d[b + 2])
	if m.human.state != Fighter.St.PLANE and int(d[b + 6]) & 7 != Fighter.St.PLANE:
		var df := m.human.position.distance_to(hp)
		max_diff = maxf(max_diff, df)
		sum_diff += df
		diff_n += 1
	m.apply_snapshot(d, m.human.id)

func _on_events(evs: Array) -> void:
	evs_seen += evs.size()
	if m != null:
		m.events.append_array(evs)

var jumped := false

func _want_jump() -> bool:
	if jumped or m == null or m.human == null:
		return false
	if m.human.state == Fighter.St.PLANE and m.plane_t > 0.3:
		jumped = true
		return true
	return false

func _on_input(slot: int, d: PackedFloat32Array) -> void:
	inputs_in += 1
	if m != null:
		m.merge_remote(slot, d)

func _process(delta: float) -> bool:
	frame += 1
	clock += delta
	if frame == 2:
		if role == "host":
			print("HOST_LISTEN ", lan.host("H"))
		else:
			print("CLIENT_JOIN ", lan.join("127.0.0.1", "C"))
	if role == "host" and not host_started and lan.peers.size() >= 1 and clock > 1.0:
		host_started = true
		lan.start_all()
	if role == "host" and not host_started and clock > 20.0:
		print("HOST_TIMEOUT no client")
		quit(1)
		return true
	if not started or m == null:
		if role == "client" and clock > 25.0:
			print("CLIENT_TIMEOUT")
			quit(1)
			return true
		return false
	var dt := minf(delta, 0.05)
	t += dt
	var inp := {"move": Vector2(0, 1), "fire": (frame % 90) < 50, "ads": false, "crouch": false, "sprint": true,
		"dyaw": 0.012, "dpitch": 0.0, "jump": _want_jump(), "reload": false, "pickup": (frame % 120 == 0), "switch": false, "fire_edge": (frame % 10 == 0)}
	if role == "host":
		m.update(dt, inp)
		lan.host_tick(dt, m, m.events.duplicate())
		m.events.clear()
		if t > 4.0:
			tick_host = t
	else:
		m.update(dt, inp)
		lan.client_input(dt, inp)
		m.events.clear()
	if t >= 32.0:
		if role == "host":
			print("HOST_DONE inputs_in=%d alive=%d phase=%d" % [inputs_in, m.alive, m.phase])
			var ok := inputs_in > 100
			print("NET_HOST ", "PASS" if ok else "FAIL")
			quit(0 if ok else 1)
		else:
			var avg := sum_diff / maxf(1.0, float(diff_n))
			print("CLIENT_DONE snaps=%d evs=%d diffs=%d max_diff=%.3f avg_diff=%.3f alive=%d phase=%d" % [snaps, evs_seen, diff_n, max_diff, avg, m.alive, m.phase])
			var ok2 := snaps > 100 and diff_n > 50 and avg < 1.0 and max_diff < 3.0
			print("NET_CLIENT ", "PASS" if ok2 else "FAIL")
			quit(0 if ok2 else 1)
		return true
	return false
