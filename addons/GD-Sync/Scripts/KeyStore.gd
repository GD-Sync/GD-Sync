@tool
extends RefCounted

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

const KEYS_PATH : String = "res://addons/GD-Sync/keys.cfg"
const KEYS_SECTION : String = "keys"
const PUBLIC_ENTRY : String = "publicKey"
const PRIVATE_ENTRY : String = "privateKey"

const GITIGNORE_PATH : String = "res://.gitignore"
const GITIGNORE_ENTRY : String = "addons/GD-Sync/keys.cfg"
const GITIGNORE_COMMENT : String = "# GD-Sync API keys. Never commit these."

const PUBLIC_KEY_ENV : String = "GDSYNC_PUBLIC_KEY"
const PRIVATE_KEY_ENV : String = "GDSYNC_PRIVATE_KEY"
const PROJECT_FILE : String = "res://project.godot"
const PROJECT_PUBLIC : String = "GD-Sync/publicKey"
const PROJECT_PRIVATE : String = "GD-Sync/privateKey"

static func load_keys() -> Dictionary:
	var keys : Dictionary = {"PublicKey" : "", "PrivateKey" : ""}
	var config : ConfigFile = ConfigFile.new()
	if config.load(KEYS_PATH) == OK or config.load(_os(KEYS_PATH)) == OK:
		keys["PublicKey"] = str(config.get_value(KEYS_SECTION, PUBLIC_ENTRY, ""))
		keys["PrivateKey"] = str(config.get_value(KEYS_SECTION, PRIVATE_ENTRY, ""))
	if keys["PublicKey"].is_empty():
		keys["PublicKey"] = OS.get_environment(PUBLIC_KEY_ENV)
	if keys["PrivateKey"].is_empty():
		keys["PrivateKey"] = OS.get_environment(PRIVATE_KEY_ENV)
	return keys

static func save_keys(public_key : String, private_key : String) -> void:
	var config : ConfigFile = ConfigFile.new()
	config.load(KEYS_PATH)
	config.set_value(KEYS_SECTION, PUBLIC_ENTRY, public_key)
	config.set_value(KEYS_SECTION, PRIVATE_ENTRY, private_key)
	if config.save(KEYS_PATH) != OK and config.save(_os(KEYS_PATH)) != OK:
		push_error("GD-Sync was unable to save the API keys to "+KEYS_PATH+".")

static func has_keys() -> bool:
	var keys : Dictionary = load_keys()
	return !keys["PublicKey"].is_empty() and !keys["PrivateKey"].is_empty()

static func encode_keys(public_key : String, private_key : String) -> PackedByteArray:
	var config : ConfigFile = ConfigFile.new()
	config.set_value(KEYS_SECTION, PUBLIC_ENTRY, public_key)
	config.set_value(KEYS_SECTION, PRIVATE_ENTRY, private_key)
	return config.encode_to_text().to_utf8_buffer()

static func needs_migrate() -> bool:
	if ProjectSettings.has_setting(PROJECT_PUBLIC) or ProjectSettings.has_setting(PROJECT_PRIVATE):
		return true
	var project : ConfigFile = ConfigFile.new()
	if project.load(PROJECT_FILE) != OK:
		project.load(_os(PROJECT_FILE))
	return project.has_section_key("GD-Sync", PUBLIC_ENTRY) or project.has_section_key("GD-Sync", PRIVATE_ENTRY)

static func migrate() -> bool:
	if !needs_migrate():
		return false
	
	var existing : Dictionary = load_keys()
	var public_key : String = str(ProjectSettings.get_setting(PROJECT_PUBLIC, existing["PublicKey"]))
	var private_key : String = str(ProjectSettings.get_setting(PROJECT_PRIVATE, existing["PrivateKey"]))
	
	var project : ConfigFile = ConfigFile.new()
	if project.load(PROJECT_FILE) == OK or project.load(_os(PROJECT_FILE)) == OK:
		if public_key.is_empty():
			public_key = str(project.get_value("GD-Sync", PUBLIC_ENTRY, ""))
		if private_key.is_empty():
			private_key = str(project.get_value("GD-Sync", PRIVATE_ENTRY, ""))
	
	save_keys(public_key, private_key)
	
	if ProjectSettings.has_setting(PROJECT_PUBLIC):
		ProjectSettings.clear(PROJECT_PUBLIC)
	if ProjectSettings.has_setting(PROJECT_PRIVATE):
		ProjectSettings.clear(PROJECT_PRIVATE)
	_strip_keys_from_project_file()
	ProjectSettings.save()
	return true

static func ensure_gitignore() -> void:
	var path : String = _os(GITIGNORE_PATH)
	var content : String = _read_text(path)
	if content.is_empty():
		content = _read_text(GITIGNORE_PATH)
	if _gitignore_has_entry(content):
		return
	if !content.is_empty() and !content.ends_with("\n"):
		content += "\n"
	if !content.is_empty():
		content += "\n"
	content += GITIGNORE_COMMENT+"\n"+GITIGNORE_ENTRY+"\n"
	if !_write_text(path, content):
		_write_text(GITIGNORE_PATH, content)

static func _os(res_path : String) -> String:
	return ProjectSettings.globalize_path(res_path)

static func _read_text(path : String) -> String:
	if !FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

static func _write_text(path : String, content : String) -> bool:
	var file : FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true

static func _gitignore_has_entry(content : String) -> bool:
	for line in content.split("\n"):
		var trimmed : String = line.strip_edges()
		if trimmed.begins_with("#") or trimmed.is_empty():
			continue
		if trimmed == GITIGNORE_ENTRY or trimmed == "/"+GITIGNORE_ENTRY:
			return true
	return false

static func _strip_keys_from_project_file() -> void:
	var path : String = _os(PROJECT_FILE)
	var text : String = _read_text(path)
	if text.is_empty():
		text = _read_text(PROJECT_FILE)
		path = PROJECT_FILE
	if text.is_empty():
		return
	
	var section : String = ""
	var kept : PackedStringArray = PackedStringArray()
	var removed : bool = false
	for line in text.split("\n"):
		var trimmed : String = line.strip_edges()
		if trimmed.begins_with("[") and trimmed.ends_with("]"):
			section = trimmed.substr(1, trimmed.length() - 2)
			kept.append(line)
			continue
		if section == "GD-Sync" and (trimmed.begins_with("publicKey=") or trimmed.begins_with("privateKey=")):
			removed = true
			continue
		kept.append(line)
	
	if removed:
		_write_text(path, "\n".join(kept))
