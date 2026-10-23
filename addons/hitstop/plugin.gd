@tool
extends EditorPlugin
## Registers the Hitstop autoload, so Hitstop.freeze() works anywhere.

const NAME: String = "Hitstop"


func _enable_plugin() -> void:
	add_autoload_singleton(NAME, "res://addons/hitstop/hitstop.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton(NAME)
