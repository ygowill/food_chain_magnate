extends RefCounted

static func dump(emp) -> String:
	var output := "=== EmployeeDef: %s ===\n" % emp.id
	output += "Name: %s\n" % emp.name
	output += "Description: %s\n" % emp.description
	output += "Salary: %s | Unique: %s\n" % [emp.salary, emp.unique]
	if emp.mandatory:
		output += "Mandatory Action: %s\n" % emp.mandatory_action_id
	output += "Manager Slots: %d\n" % emp.manager_slots
	output += "Range: %s (%d)\n" % [emp.range_type, emp.range_value]
	output += "Train To: %s\n" % str(emp.train_to)
	output += "Train Capacity: %d\n" % emp.train_capacity
	output += "Tags: %s\n" % str(emp.tags)
	output += "Usage Tags: %s\n" % str(emp.usage_tags)
	if emp.marketing_max_duration > 0:
		output += "Marketing Max Duration: %d\n" % emp.marketing_max_duration
	if emp.can_produce():
		output += "Produces: %d x %s\n" % [emp.produces_amount, emp.produces_food_type]
	return output

