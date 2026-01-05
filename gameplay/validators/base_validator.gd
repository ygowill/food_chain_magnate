# 校验器基类
# 为招聘、培训等动作提供公共校验逻辑
class_name BaseValidator
extends RefCounted

# 校验方法，子类必须实现
# 返回 Result.success() 表示校验通过
# 返回 Result.failure(msg) 表示校验失败
func validate(_state: GameState, _player_id: int, _params: Dictionary) -> Result:
	return Result.failure("BaseValidator.validate() 未实现")

# 批量校验多个校验器
static func validate_all(validators: Array, state: GameState, player_id: int, params: Dictionary) -> Result:
	for validator in validators:
		if validator is BaseValidator:
			var result: Result = validator.validate(state, player_id, params)
			if not result.ok:
				return result
	return Result.success()
