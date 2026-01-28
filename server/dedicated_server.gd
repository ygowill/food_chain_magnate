# Dedicated Server 入口（Headless）
extends Node

const DEFAULT_PORT := 7000
const DEFAULT_BIND_ADDRESS := "*"

func _ready() -> void:
	var port := DEFAULT_PORT
	var bind_address := DEFAULT_BIND_ADDRESS

	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a := str(args[i])
		if a == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif a.begins_with("--port="):
			port = int(a.split("=", false, 1)[1])
		elif a == "--bind" and i + 1 < args.size():
			bind_address = str(args[i + 1]).strip_edges()
		elif a.begins_with("--bind="):
			bind_address = str(a.split("=", false, 1)[1]).strip_edges()

	var r: Result = NetClient.start_server(port, bind_address)
	if not r.ok:
		GameLog.error("DedicatedServer", r.error)
		get_tree().quit(1)
		return

	GameLog.info("DedicatedServer", "Running. args=%s" % str(args))

