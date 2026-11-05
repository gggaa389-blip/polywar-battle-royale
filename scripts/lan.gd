class_name Lan
extends Node
# الشبكة المحلية (ENet UDP): المضيف هو المرجع. العملاء يرسلون مدخلاتهم 30 مرة/ث،
# والمضيف يرسل لقطات الحالة 20 مرة/ث وأحداث المباراة بشكل موثوق.

signal lobby_changed(names: PackedStringArray)
signal connect_ok
signal connect_failed
signal server_gone
signal started(seed_v: int, names: PackedStringArray, slot: int)
signal snapshot_in(data: PackedFloat32Array)
signal events_in(evs: Array)
signal input_in(slot: int, data: PackedFloat32Array)
signal peer_left(slot: int)

const ROLE_NONE := 0
const ROLE_HOST := 1
const ROLE_CLIENT := 2

var role := ROLE_NONE
var peers: Array = []           # معرّفات الأقران بترتيب الانضمام (بدون المضيف)
var pnames := {}                # معرّف -> اسم
var slot_of := {}               # معرّف -> رقم الخانة في المباراة
var my_name := "لاعب"
var my_slot := 0
var snap_acc := 0.0
var inp_acc := 0.0
var acc_dyaw := 0.0
var acc_dpitch := 0.0
var acc_edges := 0
var last_move := Vector2.ZERO
var last_fire := false
var last_ads := false
var last_crouch := false
var last_sprint := false
var stats_snap := 0
var stats_bytes := 0

func _ready() -> void:
	set_process(false)

func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.contains(":"):
			continue
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	return out

func host(nm: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(Cfg.NET_PORT, 16)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	role = ROLE_HOST
	my_name = nm
	peers.clear()
	pnames.clear()
	slot_of.clear()
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_send_lobby()
	return true

func join(ip: String, nm: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, Cfg.NET_PORT)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	role = ROLE_CLIENT
	my_name = nm
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_failed)
		multiplayer.server_disconnected.connect(_on_server_gone)
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	role = ROLE_NONE
	peers.clear()
	pnames.clear()
	slot_of.clear()

func _on_connected() -> void:
	hello_rpc.rpc_id(1, my_name)
	connect_ok.emit()

func _on_failed() -> void:
	role = ROLE_NONE
	multiplayer.multiplayer_peer = null
	connect_failed.emit()

func _on_server_gone() -> void:
	role = ROLE_NONE
	multiplayer.multiplayer_peer = null
	server_gone.emit()

func _on_peer_connected(id: int) -> void:
	if role != ROLE_HOST:
		return
	peers.append(id)
	pnames[id] = "لاعب"
	_send_lobby()

func _on_peer_disconnected(id: int) -> void:
	if role != ROLE_HOST:
		return
	var idx := peers.find(id)
	if idx >= 0:
		peers.remove_at(idx)
	pnames.erase(id)
	if slot_of.has(id):
		peer_left.emit(int(slot_of[id]))
		slot_of.erase(id)
	_send_lobby()

func lobby_names() -> PackedStringArray:
	var out := PackedStringArray([my_name])
	for p in peers:
		out.append(String(pnames.get(p, "لاعب")))
	return out

func _send_lobby() -> void:
	var names := lobby_names()
	lobby_changed.emit(names)
	for p in peers:
		lobby_rpc.rpc_id(p, names)

func start_all() -> void:
	if role != ROLE_HOST:
		return
	var names := lobby_names()
	var seed_v := randi() % 1000000 + 1
	slot_of.clear()
	for i in peers.size():
		slot_of[peers[i]] = i + 1
	for i in peers.size():
		start_rpc.rpc_id(peers[i], seed_v, names, i + 1)
	my_slot = 0
	started.emit(seed_v, names, 0)

# ---------- RPC ----------

@rpc("any_peer", "reliable")
func hello_rpc(nm: String) -> void:
	if role != ROLE_HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	pnames[sender] = nm
	_send_lobby()

@rpc("authority", "reliable")
func lobby_rpc(names: PackedStringArray) -> void:
	lobby_changed.emit(names)

@rpc("authority", "reliable")
func start_rpc(seed_v: int, names: PackedStringArray, slot: int) -> void:
	my_slot = slot
	started.emit(seed_v, names, slot)

@rpc("authority", "unreliable")
func snap_rpc(d: PackedFloat32Array) -> void:
	stats_snap += 1
	stats_bytes += d.size() * 4
	snapshot_in.emit(d)

@rpc("authority", "reliable")
func evs_rpc(b: PackedByteArray) -> void:
	var evs: Array = bytes_to_var(b)
	events_in.emit(evs)

@rpc("any_peer", "unreliable")
func inp_rpc(d: PackedFloat32Array) -> void:
	if role != ROLE_HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not slot_of.has(sender):
		return
	input_in.emit(int(slot_of[sender]), d)

# ---------- إرسال (المضيف) ----------

func host_tick(dt: float, m: BRMatch, evs: Array) -> void:
	if role != ROLE_HOST or peers.is_empty():
		return
	if not evs.is_empty():
		evs_rpc.rpc(var_to_bytes(evs))
	snap_acc += dt
	if snap_acc < 1.0 / Cfg.NET_SNAP_HZ:
		return
	snap_acc = 0.0
	var base := m.build_snapshot_base()
	for p in peers:
		if not slot_of.has(p):
			continue
		var pkt := base.duplicate()
		pkt.append_array(m.build_tail(int(slot_of[p])))
		snap_rpc.rpc_id(p, pkt)

# ---------- إرسال (العميل) ----------

func client_input(dt: float, inp: Dictionary) -> void:
	if role != ROLE_CLIENT:
		return
	acc_dyaw += float(inp.get("dyaw", 0.0))
	acc_dpitch += float(inp.get("dpitch", 0.0))
	if bool(inp.get("jump", false)):
		acc_edges |= 1
	if bool(inp.get("reload", false)):
		acc_edges |= 2
	if bool(inp.get("pickup", false)):
		acc_edges |= 4
	if bool(inp.get("switch", false)):
		acc_edges |= 8
	if bool(inp.get("fire_edge", false)):
		acc_edges |= 16
	last_move = inp.get("move", Vector2.ZERO)
	last_fire = bool(inp.get("fire", false))
	last_ads = bool(inp.get("ads", false))
	last_crouch = bool(inp.get("crouch", false))
	last_sprint = bool(inp.get("sprint", false))
	inp_acc += dt
	if inp_acc < 1.0 / Cfg.NET_INPUT_HZ:
		return
	var send_dt := inp_acc
	inp_acc = 0.0
	var d := PackedFloat32Array([last_move.x, last_move.y, 1.0 if last_fire else 0.0, 1.0 if last_ads else 0.0,
		1.0 if last_crouch else 0.0, 1.0 if last_sprint else 0.0, acc_dyaw, acc_dpitch, float(acc_edges), send_dt])
	inp_rpc.rpc_id(1, d)
	acc_dyaw = 0.0
	acc_dpitch = 0.0
	acc_edges = 0
