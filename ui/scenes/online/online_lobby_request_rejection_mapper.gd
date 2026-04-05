# OnlineLobby：请求失败码 -> 弹窗标题/文案
extends RefCounted

static func get_dialog_text(code: String, message: String) -> Dictionary:
	var title := "请求失败"
	var body := ""
	var c := str(code).strip_edges()
	var m := str(message).strip_edges()

	match c:
		"protocol_version_mismatch":
			title = "协议版本不匹配"
			body = "客户端与服务器版本不一致，请更新后重试。"
		"server_misconfigured":
			title = "服务器配置错误"
			body = "Game Server 未配置 HMAC_SECRET，无法验证 connect_token。\n\n本地启动时请设置 HMAC_SECRET（需与后端一致；backend 默认值为 dev-secret-change-in-production）。"
		"missing_connect_token":
			title = "连接失败"
			body = "缺少 connect_token：请通过平台后端创建/加入房间后再连接。"
		"invalid_connect_token":
			title = "连接失败"
			body = "connect_token 无效或已过期。\n\n%s" % m
		"platform_join_failed":
			title = "加入房间失败"
			if m == "Seat already occupied":
				body = "座位已被占用。\n\n常见原因：同一台机器多开时两个客户端共享了同一个游客账号。\n\n解决：启动客户端时指定不同 profile（例如：`-- --platform-profile=A` / `-- --platform-profile=B`），让它们使用不同的 user:// 会话文件。"
			else:
				body = m
		"missing_client_hello":
			title = "连接未完成"
			body = "请先连接服务器后再重试。"
		"invalid_player_count":
			title = "创建房间失败"
			body = "玩家人数不合法。"
		"invalid_params":
			title = "请求参数错误"
			body = m
		"create_room_failed":
			title = "创建房间失败"
			body = m
		"join_room_failed":
			title = "加入房间失败"
			match m:
				"Missing room_code":
					body = "请填写房间码。"
				"Room not found":
					body = "房间不存在或已解散。"
				"Invalid room_password":
					body = "房间密码错误，请重试。"
				"Room is full":
					body = "房间已满。"
				_:
					body = m
		"leave_room_failed":
			title = "离开房间失败"
			body = m
		"start_game_failed":
			title = "开始游戏失败"
			body = m
		"assign_seat_failed":
			title = "分配座位失败"
			body = m
		"update_config_failed":
			title = "配置同步失败"
			body = m
		"not_in_room":
			title = "操作失败"
			body = "你当前不在房间内。"
		"not_in_game":
			title = "操作失败"
			body = "房间不在对局中。"
		"not_host":
			title = "操作失败"
			body = "仅房主可以执行该操作。"
		"spectator_readonly":
			title = "只读模式"
			body = "旁观者无法执行该操作。"
		"forfeited_readonly":
			title = "只读模式"
			body = "你已弃权，当前为只读旁观模式。"
		_:
			title = "请求失败"
			if not m.is_empty():
				body = m
			else:
				body = "%s" % c

	return {
		"title": title,
		"body": body,
	}
