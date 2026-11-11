class_name Squad
extends RefCounted
## A group of soldiers that take orders together.

var name := ""
var team := 0
var faction := ""
var members: Array[Soldier] = []
var selected := false
var focus: Soldier = null
var running := false
var start_size := 0


func leader() -> Soldier:
	for m in members:
		if m.is_leader and m.is_effective():
			return m
	return null


func vehicle():
	return members[0] if members.size() > 0 and members[0].is_vehicle else null


## The carrier this squad is riding in, if every surviving man is aboard.
func carrier():
	var c = null
	for m in members:
		if m.is_alive():
			return null
		if m.state == Soldier.State.EMBARKED:
			c = m.carrier
	return c


func present() -> Array:
	return members.filter(func(m): return m.is_present())


func alive() -> Array:
	return members.filter(func(m): return m.is_alive())


func effective() -> Array:
	return members.filter(func(m): return m.is_effective())


func center() -> Vector2:
	var al := alive()
	if al.is_empty():
		var c = carrier()
		return c.position if c != null else members[0].position
	var c := Vector2.ZERO
	for m in al:
		c += m.position
	return c / al.size()


## 1 when this soldier's leader is close by and steady, which steadies them.
func leader_bonus(s: Soldier) -> float:
	var l := leader()
	if l == null or l == s:
		return 0.5 if l == s else 0.0
	return 1.0 if l.position.distance_to(s.position) < 130.0 else 0.0


func avg_morale() -> float:
	var v = vehicle()
	if v != null:
		return float(maxi(v.hp, 0)) / v.max_hp
	var al := alive()
	if al.is_empty():
		return 0.0
	var t := 0.0
	for m in al:
		t += clampf(m.morale / m.max_morale, 0.0, 1.0)
	return t / al.size()


func status() -> String:
	var v = vehicle()
	if v != null:
		if not v.is_alive():
			return "Destroyed"
		if v.shaken > 0.0:
			return "Shaken"
		if v.moving:
			return "Moving"
		return "Firing" if v.is_firing() else "Ready"
	var al := alive()
	if al.is_empty():
		return "Aboard" if carrier() != null else "Lost"
	var rout := 0
	var pinned := 0
	var mov := false
	for m in al:
		if m.state == Soldier.State.ROUTING:
			rout += 1
		elif m.state == Soldier.State.PINNED:
			pinned += 1
		if m.moving:
			mov = true
	if rout * 2 >= al.size():
		return "Routing"
	if pinned * 2 >= al.size():
		return "Pinned"
	if mov:
		return "Running" if running else "Moving"
	for m in al:
		if m.burst_left > 0 or m.flash > 0.0:
			return "Firing"
	return "Ready"


func order_move(map: BattleMap, pos: Vector2, run: bool) -> void:
	running = run
	var v = vehicle()
	if v != null:
		v.go_to(pos, run)
		return
	for m in members:
		m.board_vehicle = null
	var ms: Array = members.filter(func(m): return m.is_alive() and m.state != Soldier.State.ROUTING)
	if ms.is_empty():
		return
	var slots := pick_slots(map, pos, ms.size())
	ms.sort_custom(func(a, b): return a.position.distance_squared_to(pos) < b.position.distance_squared_to(pos))
	for m in ms:
		var best := 0
		for i in slots.size():
			if m.position.distance_squared_to(slots[i]) < m.position.distance_squared_to(slots[best]):
				best = i
		m.go_to(slots[best], run)
		slots.remove_at(best)


func halt() -> void:
	focus = null
	for m in members:
		m.board_vehicle = null
		m.halt()


func order_board(v) -> void:
	focus = null
	for m in members:
		if m.is_alive() and m.state != Soldier.State.ROUTING:
			m.board_vehicle = v
			m.halt()


## Spots around pos for n soldiers, preferring cover and keeping them spread out.
func pick_slots(map: BattleMap, pos: Vector2, n: int) -> Array[Vector2]:
	var c0 := map.nearest_walkable(map.cell_of(pos))
	var cands: Array = []
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var c := c0 + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length()
			if d > 4.5 or not map.walkable(c):
				continue
			cands.append([map.cell_cover(c) * 4.0 - d * 0.6 + randf() * 0.3, c])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var chosen: Array[Vector2i] = []
	for cand in cands:
		if chosen.size() >= n:
			break
		var ok := true
		for ch in chosen:
			if (ch - cand[1]).length_squared() < 2:
				ok = false
				break
		if ok:
			chosen.append(cand[1])
	while chosen.size() < n:
		chosen.append(c0)
	var out: Array[Vector2] = []
	for c in chosen:
		out.append(map.center_of(c) + Vector2(randf_range(-2, 2), randf_range(-2, 2)))
	return out
