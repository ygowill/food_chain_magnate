# Connect Token (HMAC-SHA256)
# Token format: <base64url(payload_json)>.<hex(hmac_sha256(payload_json, secret))>
extends RefCounted

static func create_token(payload: Dictionary, secret: String) -> Result:
	var raw_json := _canonical_json(payload)
	if raw_json.is_empty():
		return Result.failure("connect_token payload is empty")
	var raw: PackedByteArray = raw_json.to_utf8_buffer()
	var b64 := _to_base64url(raw)
	if b64.is_empty():
		return Result.failure("connect_token base64 failed")
	var sig := _hmac_sha256_hex(raw, secret)
	if sig.is_empty():
		return Result.failure("connect_token hmac failed")
	return Result.success("%s.%s" % [b64, sig])

static func verify_token(token: String, secret: String) -> Result:
	var s := str(token).strip_edges()
	if s.is_empty():
		return Result.failure("connect_token is empty")

	var dot := s.rfind(".")
	if dot <= 0 or dot >= s.length() - 1:
		return Result.failure("connect_token malformed")

	var b64 := s.substr(0, dot)
	var sig := s.substr(dot + 1)
	if b64.is_empty() or sig.is_empty():
		return Result.failure("connect_token malformed")

	var raw := _from_base64url(b64)
	if raw.is_empty():
		return Result.failure("connect_token payload decode failed")

	var expected := _hmac_sha256_hex(raw, secret)
	if expected.is_empty():
		return Result.failure("connect_token hmac failed")
	if expected != sig:
		return Result.failure("connect_token signature mismatch")

	var json_text := raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("connect_token payload is not a Dictionary")
	var payload: Dictionary = Dictionary(parsed)

	var exp_val = payload.get("exp", null)
	if not (exp_val is int or exp_val is float):
		return Result.failure("connect_token missing exp")
	var exp := int(exp_val)
	var now := int(Time.get_unix_time_from_system())
	if exp < now:
		return Result.failure("connect_token expired")

	return Result.success(payload)

static func _hmac_sha256_hex(raw: PackedByteArray, secret: String) -> String:
	var key := str(secret).to_utf8_buffer()
	if key.is_empty():
		return ""
	var ctx := HMACContext.new()
	var err := ctx.start(HashingContext.HASH_SHA256, key)
	if err != OK:
		return ""
	ctx.update(raw)
	return ctx.finish().hex_encode()

static func _to_base64url(raw: PackedByteArray) -> String:
	var b64 := Marshalls.raw_to_base64(raw)
	return str(b64).replace("+", "-").replace("/", "_")

static func _from_base64url(b64url: String) -> PackedByteArray:
	var s := str(b64url).strip_edges().replace("-", "+").replace("_", "/")
	var pad := s.length() % 4
	if pad != 0:
		s += "=".repeat(4 - pad)
	return Marshalls.base64_to_raw(s)

static func _canonical_json(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var dict: Dictionary = Dictionary(value)
			var keys: Array = dict.keys()
			keys.sort()
			var parts: Array[String] = []
			for k in keys:
				var key_str := str(k)
				parts.append("%s:%s" % [JSON.stringify(key_str), _canonical_json(dict.get(k, null))])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var arr: Array = Array(value)
			var parts2: Array[String] = []
			for item in arr:
				parts2.append(_canonical_json(item))
			return "[%s]" % ",".join(parts2)
		_:
			return JSON.stringify(value)

