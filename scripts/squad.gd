class_name Squad
extends RefCounted
## A group of soldiers that take orders together.

var name := ""
var team := 0
var faction := ""
var members: Array[Soldier] = []
var selected := false
var focus: Soldier = null
var fire_point = null  # a wall the squad has been told to shell (Vector2), or null
var running := false
var start_size := 0
var facing := Vector2.ZERO  # the direction the squad watches (ZERO = no order)
var sub: Array = []          # soldiers picked out individually (Alt+click); orders go to them only
var think_timer := randf() * 1.2

## Squad coherency, as in Epik: every soldier must be within this distance of
## another, forming one connected group. Stragglers make their way back.
const COH := 72.0


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


## Can this squad blow holes in walls (does it have explosive weapons)?
func can_breach() -> bool:
	for m in members:
		if m.is_alive() and m.can_breach():
			return true
	return false


func order_fire_at(p: Vector2) -> void:
	focus = null
	fire_point = p


## The soldiers an order applies to: the picked-out ones if any, otherwise all.
func movers() -> Array:
	var live := sub.filter(func(m): return is_instance_valid(m) and m.is_alive() and m.state != Soldier.State.ROUTING)
	if live.is_empty():
		sub.clear()
		return members.filter(func(m): return m.is_alive() and m.state != Soldier.State.ROUTING)
	return live


## Keeps a picked-out soldier's destination within reach of the rest of the squad.
func clamp_coherent(m: Soldier, target: Vector2) -> Vector2:
	var anchors := members.filter(func(o): return o != m and o.is_alive() and not sub.has(o))
	if anchors.is_empty():
		return target
	var best: Soldier = anchors[0]
	for a in anchors:
		if a.position.distance_to(target) < best.position.distance_to(target):
			best = a
	if best.position.distance_to(target) <= COH * 0.9:
		return target
	return best.position + (target - best.position).limit_length(COH * 0.9)


func order_move(map: BattleMap, pos: Vector2, run: bool) -> void:
	running = run
	fire_point = null
	var v = vehicle()
	if v != null:
		v.go_to(pos, run)
		return
	for m in members:
		m.board_vehicle = null
	var ms := movers()
	if ms.is_empty():
		return
	var c := center()
	if pos.distance_to(c) > 40.0:
		facing = (pos - c).normalized()  # look the way you're going
	if not sub.is_empty():
		for m in ms:
			m.go_to(clamp_coherent(m, pos + Vector2(randf_range(-6, 6), randf_range(-6, 6))), run)
		return
	var slots := pick_slots(map, pos, ms.size(), facing)
	_assign(ms, slots, run)


func _assign(ms: Array, slots: Array, run: bool) -> void:
	var targets: Array = slots.duplicate()
	var centre := Vector2.ZERO
	for t in targets:
		centre += t
	centre /= maxi(targets.size(), 1)
	ms.sort_custom(func(a, b): return a.position.distance_squared_to(centre) > b.position.distance_squared_to(centre))
	for m in ms:
		var best := 0
		for i in targets.size():
			if m.position.distance_squared_to(targets[i]) < m.position.distance_squared_to(targets[best]):
				best = i
		m.go_to(targets[best], run)
		targets.remove_at(best)


## Spread out along the line a-b, each man taking the best cover near his spot,
## then watch towards face.
func order_line(map: BattleMap, a: Vector2, b: Vector2, face: Vector2, run: bool) -> void:
	running = run
	fire_point = null
	if vehicle() != null:
		return
	for m in members:
		m.board_vehicle = null
	var ms := movers()
	if ms.is_empty():
		return
	facing = face
	var slots := line_positions(map, a, b, ms.size(), face)
	if not sub.is_empty():
		for i in ms.size():
			ms[i].go_to(clamp_coherent(ms[i], slots[i]), run)
		return
	_assign(ms, slots, run)


## Where n soldiers would stand along a-b. The line is shortened if needed so
## they stay in contact, and each spot snaps to nearby cover facing face.
func line_positions(map: BattleMap, a: Vector2, b: Vector2, n: int, face: Vector2) -> Array[Vector2]:
	var dir := (b - a).normalized()
	var max_len := (n - 1) * COH * 0.8
	if a.distance_to(b) > max_len:
		b = a + dir * max_len
	var taken := {}
	var out: Array[Vector2] = []
	for i in n:
		var p := a.lerp(b, 0.5 if n == 1 else float(i) / (n - 1))
		var c0 := map.cell_of(p)
		var best := Vector2i(-999, -999)
		var best_score := -INF
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c := c0 + Vector2i(dx, dy)
				if not map.walkable(c) or map.get_t(c) == BattleMap.T.LOW or taken.has(c):
					continue
				var score := map.cell_cover_dir(c, face) * 3.0 - map.center_of(c).distance_to(p) * 0.06
				if score > best_score:
					best_score = score
					best = c
		if best.x == -999:
			best = map.nearest_walkable(c0)
		taken[best] = true
		out.append(map.center_of(best))
	return out


func order_face(dir: Vector2) -> void:
	facing = dir.normalized()


## Groups of soldiers that are in contact with each other.
func groups() -> Array:
	var live := members.filter(func(m): return m.is_alive() and m.state != Soldier.State.ROUTING)
	var seen := {}
	var out: Array = []
	for m in live:
		if seen.has(m):
			continue
		var group: Array = [m]
		seen[m] = true
		var i := 0
		while i < group.size():
			for o in live:
				if not seen.has(o) and group[i].position.distance_to(o.position) <= COH:
					seen[o] = true
					group.append(o)
			i += 1
		out.append(group)
	return out


func is_coherent() -> bool:
	return groups().size() <= 1


## Runs about once a second: stragglers rejoin the squad, and idle soldiers
## caught in the open hop into nearby cover facing the threat.
func think(main: Node, dt: float) -> void:
	think_timer -= dt
	if think_timer > 0.0 or vehicle() != null:
		return
	think_timer = 1.2
	var map: BattleMap = main.map
	var gs := groups()
	if gs.size() > 1:
		gs.sort_custom(func(x, y): return x.size() > y.size())
		var main_group: Array = gs[0]
		for k in range(1, gs.size()):
			for m in gs[k]:
				if m.moving or m.state != Soldier.State.READY:
					continue
				var near: Soldier = main_group[0]
				for o in main_group:
					if o.position.distance_to(m.position) < near.position.distance_to(m.position):
						near = o
				m.go_to(near.position + (m.position - near.position).normalized() * COH * 0.5, false)
	var c := center()
	var threat := facing
	var enemy: Soldier = main.nearest_seen_enemy(team, c)
	if enemy != null and enemy.position.distance_to(c) < 650.0:
		threat = (enemy.position - c).normalized()
	for m in members:
		if not m.is_alive():
			continue
		var cell := map.cell_of(m.position)
		var cur := map.cell_cover_dir(cell, threat)
		m.in_cover = threat != Vector2.ZERO and cur >= 0.6
		if threat == Vector2.ZERO or m.moving or m.state != Soldier.State.READY or m.burst_left > 0 or cur >= 0.55:
			continue
		var best := cell
		var best_score := cur
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var n := cell + Vector2i(dx, dy)
				if not map.walkable(n) or map.get_t(n) == BattleMap.T.LOW:
					continue
				var p := map.center_of(n)
				var crowded := false
				var in_reach := false
				for o in members:
					if o == m or not o.is_alive():
						continue
					var op: Vector2 = o.position if o.path_i >= o.path.size() else o.path[o.path.size() - 1]
					if op.distance_to(p) < 12.0:
						crowded = true
					if o.position.distance_to(p) <= COH:
						in_reach = true
				if crowded or (not in_reach and members.size() > 1):
					continue
				var score := map.cell_cover_dir(n, threat) - Vector2(dx, dy).length() * 0.08
				if score > best_score + 0.3:
					best_score = score
					best = n
		if best != cell:
			m.go_to(map.center_of(best), false)


func halt() -> void:
	focus = null
	fire_point = null
	for m in members:
		m.board_vehicle = null
		m.halt()


func order_board(v) -> void:
	focus = null
	for m in members:
		if m.is_alive() and m.state != Soldier.State.ROUTING:
			m.board_vehicle = v
			m.halt()


## Spots around pos for n soldiers, preferring cover (from dir, if given) and
## keeping them spread out.
func pick_slots(map: BattleMap, pos: Vector2, n: int, dir := Vector2.ZERO) -> Array[Vector2]:
	var c0 := map.nearest_walkable(map.cell_of(pos))
	var cands: Array = []
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var c := c0 + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length()
			if d > 4.5 or not map.walkable(c) or map.get_t(c) == BattleMap.T.LOW:
				continue
			cands.append([map.cell_cover_dir(c, dir) * 4.0 - d * 0.6 + randf() * 0.3, c])
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
