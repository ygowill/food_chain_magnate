# 联机恢复：错误分类策略
class_name OnlineResumeErrorPolicyTest
extends RefCounted

const PolicyClass = preload("res://ui/scenes/online/online_resume_error_policy.gd")

static func run() -> Result:
	var room_missing := PolicyClass.classify_resume_failure({
		"_http_status": 404,
		"detail": "room not found",
	})
	if not bool(room_missing.get("clear_resume_context", false)):
		return Result.failure("room not found 应清理 resume 上下文")

	var ended := PolicyClass.classify_resume_failure({
		"_http_status": 409,
		"detail": "room already ended",
	})
	if not bool(ended.get("clear_resume_context", false)):
		return Result.failure("room already ended 应清理 resume 上下文")

	var membership := PolicyClass.classify_resume_failure({
		"_http_status": 403,
		"detail": "room membership not found",
	})
	if not bool(membership.get("clear_resume_context", false)):
		return Result.failure("room membership not found 应清理 resume 上下文")

	var transient := PolicyClass.classify_resume_failure({
		"_http_result_name": "cant_connect",
		"detail": "network request failed",
	})
	if bool(transient.get("clear_resume_context", false)):
		return Result.failure("网络错误不应清理 resume 上下文")

	var mismatch := PolicyClass.classify_user_mismatch("u_old", "u_new")
	if not bool(mismatch.get("clear_resume_context", false)):
		return Result.failure("user mismatch 应清理 resume 上下文")

	return Result.success()
