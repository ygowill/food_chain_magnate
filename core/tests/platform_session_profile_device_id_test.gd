# PlatformSession：不覆盖昵称 + device_id 使用强随机
extends RefCounted

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")

	var prev_profile: Dictionary = NetContext.player_profile.duplicate(true)
	var prev_user_id := str(PlatformSession.user_id)
	var prev_session_id := str(PlatformSession.session_id)
	var prev_is_guest := bool(PlatformSession.is_guest)
	var prev_display_name := str(PlatformSession.display_name)

	NetContext.player_profile["name"] = "MyNick"
	PlatformSession._apply_auth({"user_id": "u_test_1234", "session_id": "s_test_1234"}, true)

	if str(NetContext.player_profile.get("name", "")) != "MyNick":
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
		return Result.failure("登录后不应覆盖 NetContext.player_profile.name")
	if str(NetContext.player_profile.get("user_id", "")) != "u_test_1234":
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
		return Result.failure("登录后应写入 NetContext.player_profile.user_id")
	if str(PlatformSession.display_name).strip_edges().is_empty():
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
		return Result.failure("登录后应写入 PlatformSession.display_name")

	var did: String = str(PlatformSession._generate_device_id())
	if did.length() != 32:
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
		return Result.failure("device_id 长度应为 32 hex，实际=%d" % did.length())
	for ch in did.to_lower():
		if "0123456789abcdef".find(ch) == -1:
			_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
			return Result.failure("device_id 非 hex: %s" % did)

	var p0 := str(PlatformSession._build_save_path(""))
	if p0 != "user://platform_session.cfg":
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
		return Result.failure("默认 profile save_path 错误：%s" % p0)

	var p1 := str(PlatformSession._build_save_path("A"))
	if p1 != "user://platform_session_A.cfg":
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
		return Result.failure("profile save_path 错误：%s" % p1)

	_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest, prev_display_name)
	return Result.success()

static func _restore(prev_profile: Dictionary, prev_user_id: String, prev_session_id: String, prev_is_guest: bool, prev_display_name: String) -> void:
	if NetContext != null:
		NetContext.player_profile = prev_profile.duplicate(true)
	if PlatformSession != null:
		PlatformSession.user_id = prev_user_id
		PlatformSession.session_id = prev_session_id
		PlatformSession.is_guest = prev_is_guest
		PlatformSession.display_name = prev_display_name
