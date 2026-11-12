class_name Settings
extends RefCounted
## Switches that can be set from the web page address (e.g. ?safe or ?shadows=0)
## or the command line (--shadows=0), for trying the game on weaker devices.
##   detail=low|medium   lighter map textures
##   shadows=0|1         walls casting shadows from fires and explosions (off by default on phones)
##   normals=0           no normal maps (flat lighting)
##   lights=0            no combat lights or moonlight
##   bake=0              no detailed map at all: a plain flat one (no off-screen drawing)
##   batch=N             map tiles drawn per frame (default 4, 1 on phones)
## Most can also be chosen in the game's Options menu and are saved on the device.
##   sound=0             no sound effects
##   safe                all of the above off

static var _query := ""
static var _read := false
## Choices made in the game's Options menu, kept on the device (user://settings.cfg).
## The address / command line still wins over them.
static var _cfg: ConfigFile = null
## Carried over when the scene is reloaded to restart a battle.
static var next_faction := ""
static var next_seed := -1


static func _saved() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load("user://settings.cfg")
	return _cfg


static func saved(name: String, default_value):
	return _saved().get_value("options", name, default_value)


static func save_option(name: String, value) -> void:
	_saved().set_value("options", name, value)
	_cfg.save("user://settings.cfg")


static func _q() -> String:
	if not _read:
		_read = true
		if OS.has_feature("web"):
			var v = JavaScriptBridge.eval("window.location.search", true)
			_query = str(v) if v != null else ""
		for a in OS.get_cmdline_user_args():
			_query += " " + a
	return _query


static func is_phone() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")


static func safe() -> bool:
	return _q().contains("safe")


## A 0/1 switch: explicit "name=0" / "name=1" wins, then safe mode, then the default.
static func on(name: String, default_on: bool) -> bool:
	var q := _q()
	if q.contains(name + "=0"):
		return false
	if q.contains(name + "=1"):
		return true
	if _saved().has_section_key("options", name):
		return bool(_cfg.get_value("options", name))
	if safe():
		return false
	return default_on


static func detail() -> float:
	var q := _q()
	if q.contains("detail=low") or safe():
		return 1.0
	if q.contains("detail=medium"):
		return 1.5
	return float(saved("detail", 2.0))


## Breadcrumbs for crashes we can't see: the last step reached is kept in the
## browser's storage, so the next visit can show where the previous one stopped.
static func stage(msg: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('starfront_stage', %s)}catch(e){}" % JSON.stringify(msg))


static func last_stage() -> String:
	if not OS.has_feature("web"):
		return ""
	var v = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('starfront_stage')||''}catch(e){return ''}})()", true)
	return str(v) if v != null else ""


static func batch() -> int:
	var q := _q()
	for n in [1, 2, 4, 8]:
		if q.contains("batch=%d" % n):
			return n
	# one at a time on phones (browser or app): four at once crashed the Android app (v0.50)
	return 1 if is_phone() else 4


static func summary() -> String:
	var oo := func(b: bool) -> String: return "on" if b else "off"
	return "detail %sx, shadows %s, normal maps %s, lights %s, map drawing %s, %d tile(s)/frame" % [detail(), oo.call(on("shadows", not is_phone())),
			oo.call(on("normals", true)), oo.call(on("lights", true)), oo.call(on("bake", true)), batch()]
