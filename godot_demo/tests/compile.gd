extends Node
## Loads every script so parse errors show up with file and line (autoloads active).
## Prints "COMPILE DONE" and exits 0 only when every script loads; otherwise
## "COMPILE FAILED <n>" and exit code 1.
func _ready() -> void:
	var fails := 0
	for d in ["res://scripts", "res://scripts/campaign", "res://tests"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				var s = load(d + "/" + f)
				if s == null:
					print("COMPILE FAIL ", f)
					fails += 1
	if fails > 0:
		print("COMPILE FAILED %d" % fails)
	else:
		print("COMPILE DONE")
	get_tree().quit(1 if fails > 0 else 0)
