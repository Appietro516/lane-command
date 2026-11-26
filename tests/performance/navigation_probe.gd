extends RefCounted
## Injected callers are only present in the scratch project.

var active := false
var timings: Dictionary = {}
var counts: Dictionary = {}
var stack: Array[Array] = []


func reset() -> void:
	timings.clear()
	counts.clear()
	stack.clear()


func count(key: String) -> void:
	if active:
		counts[key] = counts.get(key, 0) + 1


func caller() -> String:
	return "external" if stack.is_empty() else stack[-1][0]


func begin(key: String) -> void:
	stack.append([key, Time.get_ticks_usec(), 0])


func end() -> void:
	var started: Array = stack.pop_back()
	var elapsed: int = Time.get_ticks_usec() - started[1]
	var total: Array = timings.get_or_add(started[0], [0, 0, 0, 0])
	total[0] += 1
	total[1] += elapsed
	total[2] += elapsed - started[2]
	total[3] = maxi(total[3], elapsed)
	if not stack.is_empty():
		stack[-1][2] += elapsed


# Async jobs are measured from submission until the simulation can publish.
func record(key: String, elapsed: int) -> void:
	var total: Array = timings.get_or_add(key, [0, 0, 0, 0])
	total[0] += 1
	total[1] += elapsed
	total[3] = maxi(total[3], elapsed)
