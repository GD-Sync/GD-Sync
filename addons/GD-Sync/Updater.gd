@tool
class_name Updater
extends Node

#Copyright (c) 2023-present GD-Sync.
#All rights reserved.
#
#Redistribution and use in source form, with or without modification,
#are permitted provided that the following conditions are met:
#
#1. Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
#
#2. Neither the name of GD-Sync nor the names of its contributors may be used
#   to endorse or promote products derived from this software without specific
#   prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
#EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
#OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
#SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
#TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
#BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#SUCH DAMAGE.

const API_ROOT : String = "https://api.github.com/repos/GD-Sync/GD-Sync/contents/"
const API_REF : String = "main"
const LOCAL_ROOT : String = "res://"
const PLUGIN_PATH : String = "addons/GD-Sync"

const MAX_TRIES : int = 5
const RETRY_DELAY : float = 1.0
const REQUEST_TIMEOUT : float = 20.0

const API_HEADERS : Array = [
	"User-Agent: GD-Sync-Updater",
	"Accept: application/vnd.github.v3+json"
]

const EXCLUDED_FILES : Array = [
	PLUGIN_PATH+"/GDSync.cs",
	PLUGIN_PATH+"/GDSync.cs.uid",
	PLUGIN_PATH+"/keys.cfg",
]

func update_repo(path : String = PLUGIN_PATH) -> bool:
	if path.is_empty(): path = PLUGIN_PATH
	
	var files : Array = []
	if not await _collect_files(path, files):
		return false
	
	if files.is_empty():
		push_error("GD-Sync failed to update, no files were found at "+path+".")
		return false
	
	for file in files:
		if not await _download(file[0], file[1], file[2]):
			return false
	
	return true

func _collect_files(path : String, files : Array) -> bool:
	var entries = await _request_json(API_ROOT+path+"?ref="+API_REF)
	if entries == null: return false
	
	if typeof(entries) == TYPE_DICTIONARY: entries = [entries]
	if typeof(entries) != TYPE_ARRAY:
		push_error("GD-Sync failed to update, unexpected response for "+path+".")
		return false
	
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY: continue
		
		var entry_path : String = str(entry.get("path", ""))
		if _is_excluded(entry_path): continue
		
		match str(entry.get("type", "")):
			"file":
				if entry.get("download_url") == null: continue
				files.append([
					str(entry["download_url"]),
					entry_path,
					int(entry.get("size", 0))
				])
			"dir":
				if not await _collect_files(entry_path, files):
					return false
	
	return true

func _is_excluded(path : String) -> bool:
	if !path.begins_with(PLUGIN_PATH): return true
	if EXCLUDED_FILES.has(path): return true
	return "template" in path.to_lower()

func _download(url : String, rel : String, expected_size : int) -> bool:
	var dst : String = LOCAL_ROOT+rel
	print_rich("[color=#8b8d8f]- Updating file " + dst + "[/color]")
	
	var body : PackedByteArray = await _request_bytes(url, [])
	if body.is_empty(): return false
	
	if expected_size > 0 and body.size() != expected_size:
		push_error("GD-Sync failed to update, "+rel+" was downloaded incompletely ("+str(body.size())+" of "+str(expected_size)+" bytes).")
		return false
	
	if DirAccess.make_dir_recursive_absolute(dst.get_base_dir()) != OK:
		push_error("GD-Sync failed to update, could not create directory "+dst.get_base_dir()+".")
		return false
	
	var file : FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if file == null:
		push_error("GD-Sync failed to update, could not write to "+dst+".")
		return false
	
	file.store_buffer(body)
	file.close()
	return true

func _request_json(url : String):
	var body : PackedByteArray = await _request_bytes(url, API_HEADERS)
	if body.is_empty(): return null
	return JSON.parse_string(body.get_string_from_utf8())

func _request_bytes(url : String, headers : Array) -> PackedByteArray:
	var last_code : int = 0
	
	for attempt in range(MAX_TRIES):
		if attempt > 0:
			await get_tree().create_timer(RETRY_DELAY).timeout
		
		var http : HTTPRequest = HTTPRequest.new()
		http.timeout = REQUEST_TIMEOUT
		add_child(http)
		
		var result : Array = []
		if http.request(url, headers, HTTPClient.METHOD_GET) == OK:
			result = await http.request_completed
		
		if is_instance_valid(http): http.queue_free()
		
		if result.size() < 4:
			continue
		
		last_code = result[1]
		if last_code == 200:
			return result[3]
		
		if last_code == 403 or last_code == 404 or last_code == 429:
			break
	
	if last_code == 403 or last_code == 429:
		push_error("GD-Sync failed to update, the GitHub API rate limit was reached. Please try again later or download the plugin from the Godot Asset Library.")
	else:
		push_error("GD-Sync failed to update, could not download "+url+" (status "+str(last_code)+").")
	
	return PackedByteArray()
