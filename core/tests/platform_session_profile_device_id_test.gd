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

	NetContext.player_profile["name"] = "MyNick"
	PlatformSession._apply_auth({"user_id": "u_test_1234", "session_id": "s_test_1234"}, true)

	if str(NetContext.player_profile.get("name", "")) != "MyNick":
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest)
		return Result.failure("登录后不应覆盖 NetContext.player_profile.name")
	if str(NetContext.player_profile.get("user_id", "")) != "u_test_1234":
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest)
		return Result.failure("登录后应写入 NetContext.player_profile.user_id")

	var did: String = str(PlatformSession._generate_device_id())
	if did.length() != 32:
		_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest)
		return Result.failure("device_id 长度应为 32 hex，实际=%d" % did.length())
	for ch in did.to_lower():
		if "0123456789abcdef".find(ch) == -1:
			_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest)
			return Result.failure("device_id 非 hex: %s" % did)

	_restore(prev_profile, prev_user_id, prev_session_id, prev_is_guest)
	return Result.success()

static func _restore(prev_profile: Dictionary, prev_user_id: String, prev_session_id: String, prev_is_guest: bool) -> void:
	if NetContext != null:
		NetContext.player_profile = prev_profile.duplicate(true)
	if PlatformSession != null:
		PlatformSession.user_id = prev_user_id
		PlatformSession.session_id = prev_session_id
		PlatformSession.is_guest = prev_is_guest
