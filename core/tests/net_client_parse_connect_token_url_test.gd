# NetClient：解析 URL query 中的 connect_token
class_name NetClientParseConnectTokenUrlTest
extends RefCounted

static func run() -> Result:
	if NetClient == null:
		return Result.failure("NetClient autoload missing")

	var cases: Array[Dictionary] = [
		{
			"in": "ws://localhost:7000",
			"url": "ws://localhost:7000",
			"token": "",
		},
		{
			"in": "ws://localhost:7000?connect_token=abc",
			"url": "ws://localhost:7000",
			"token": "abc",
		},
		{
			"in": "ws://localhost:7000?token=abc",
			"url": "ws://localhost:7000",
			"token": "abc",
		},
		{
			"in": "ws://localhost:7000?foo=bar&connect_token=abc&x=y",
			"url": "ws://localhost:7000?foo=bar&x=y",
			"token": "abc",
		},
		{
			"in": "ws://localhost:7000?foo=bar&token=a%2Bb&x=y",
			"url": "ws://localhost:7000?foo=bar&x=y",
			"token": "a+b",
		},
	]

	for c in cases:
		var parsed: Dictionary = NetClient._parse_connect_token_from_url(str(c.get("in", "")))
		var got_url := str(parsed.get("url", ""))
		var got_token := str(parsed.get("connect_token", ""))
		var want_url := str(c.get("url", ""))
		var want_token := str(c.get("token", ""))
		if got_url != want_url:
			return Result.failure("url parse mismatch: got=%s want=%s in=%s" % [got_url, want_url, str(c.get("in", ""))])
		if got_token != want_token:
			return Result.failure("connect_token parse mismatch: got=%s want=%s in=%s" % [got_token, want_token, str(c.get("in", ""))])

	return Result.success()

