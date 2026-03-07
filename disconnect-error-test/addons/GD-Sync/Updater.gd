@tool
class_name Updater
extends Node

const API_ROOT : String = "https://api.github.com/repos/GD-Sync/GD-Sync/contents/"
const LOCAL_ROOT : String = "res://"

var _busy_counter : int = 0
var _error_count : int = 0

func update_repo(path:String = "", tries : int = 0) -> bool:
	if tries > 5:
		_error_count += 1
	
	_busy_counter += 1
	
	var http := HTTPRequest.new()
	add_child(http)
	var headers := [
		"User-Agent: GD-Sync-Updater",
		"Accept: application/vnd.github.v3+json"
	]

	http.request(API_ROOT + path, headers, HTTPClient.METHOD_GET)
	var res : Array = await http.request_completed
	
	http.queue_free()
	if res[1] != 200:
		await get_tree().create_timer(1.0).timeout
		update_repo(path)
		
	var entries = JSON.parse_string(res[3].get_string_from_utf8())
	if typeof(entries) == TYPE_ARRAY:
		for e in entries:
			if e["type"] == "file" and !"template" in e["name"].to_lower():
				_download(e["download_url"], e["path"], 0)
			elif e["type"] == "dir":
				update_repo(e["path"], tries)
	elif typeof(entries) == TYPE_DICTIONARY and entries.get("type") == "file" and !"template" in entries["name"].to_lower():
		_download(entries["download_url"], entries["path"], 0)
	
	_busy_counter -= 1
	
	while _busy_counter > 0:
		await get_tree().create_timer(1.0).timeout
		
		if _error_count > 0:
			return false
	
	return true

func _download(url:String, rel:String, tries : int) -> void:
	if tries > 5:
		_error_count += 1
		return
	
	_busy_counter += 1
	
	var dst := LOCAL_ROOT + rel
	print_rich("[color=#8b8d8f]- Updating file " + dst + "[/color]")
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var http := HTTPRequest.new()
	add_child(http)
	http.download_file = dst
	http.request(url, [], HTTPClient.METHOD_GET)
	var res : Array = await http.request_completed
	http.queue_free()
	if res[1] != 200:
		await get_tree().create_timer(1.0).timeout
		_download(url, rel, tries)
	
	_busy_counter -= 1
