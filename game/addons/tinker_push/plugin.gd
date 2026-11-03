@tool
extends EditorPlugin
## Adds the TinkerPush Android library (built from android/tinker_push) and firebase-messaging to
## Gradle-based Android exports. Other platforms are untouched.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = TinkerPushExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class TinkerPushExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "TinkerPush"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(["tinker_push/bin/tinker_push-release.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.firebase:firebase-messaging:24.1.0", "androidx.core:core-ktx:1.13.1",
			"com.android.billingclient:billing-ktx:8.3.0"])
