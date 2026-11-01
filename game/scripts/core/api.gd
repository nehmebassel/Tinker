class_name Api
extends Node
## Api — thin async wrapper over the backend (server/src/app.js). One HTTPRequest per call.
## Every call returns {"ok": bool, "status": int, "body": Variant, "error": String}.

const TIMEOUT_S := 90.0  # score submissions wait for the server-side replay

var settings: Settings


func _init(p_settings: Settings) -> void:
	settings = p_settings


func get_json(path: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, null)


func post_json(path: String, body: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, path, body)


func _request(method: int, path: String, body: Variant) -> Dictionary:
	var base := settings.base_url()
	if base == "":
		return {"ok": false, "status": 0, "body": null, "error": "No server set. Open Settings."}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	add_child(http)
	var headers := PackedStringArray(["content-type: application/json", "accept: application/json"])
	var data := JSON.stringify(body) if body != null else ""
	var err := http.request(base + path, headers, method, data)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "body": null, "error": "request failed (%d)" % err}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "body": null, "error": "network error (%d)" % result}
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	var ok := code >= 200 and code < 300
	var msg := ""
	if not ok:
		msg = str(parsed.get("error", "HTTP %d" % code)) if parsed is Dictionary else "HTTP %d" % code
	return {"ok": ok, "status": code, "body": parsed, "error": msg}
