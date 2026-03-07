@tool
extends EditorPlugin

# Copyright (c) 2026 GD-Sync.
# All rights reserved.
#
# Redistribution and use in source form, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Neither the name of GD-Sync nor the names of its contributors may be used
#    to endorse or promote products derived from this software without specific
#    prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
# SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

#region GD-Sync

const CSHARP_URL : String = "https://raw.githubusercontent.com/GD-Sync/GD-SyncCSharp/main/GDSync.cs"
const PLUGIN_PATH : String = "res://addons/GD-Sync"
const CSHARP_PATH : String = "res://addons/GD-Sync/GDSync.cs"

var load_balancers : PackedStringArray = [
	"lb1.gd-sync.com",
	"lb2.gd-sync.com",
	"lb3.gd-sync.com",
]

var version : String = "0.14"

var debugger = GDSyncProfiler.new()

func _enable_plugin() -> void:
	add_autoload_singleton("GDSync", "res://addons/GD-Sync/MultiplayerClient.gd")
	
	print_rich("[color=#408EAB]	- Please visit our website for more info (https://www.gd-sync.com)[/color]")
	print_rich("[color=#408EAB]	- The plugin configuration menu can be found under Project > Tools > GD-Sync.[/color]")
	
	show_message("[b]GD-Sync version "+version+" enabled.[/b]
	
Please visit our website for more info ([color=#408EAB][url=https://www.gd-sync.com]gd-sync.com[/url][/color])", 10.0)
	

var config_menu : Control
func _enter_tree() -> void:
	config_menu = load("res://addons/GD-Sync/UI/ConfigMenu/ConfigMenu.tscn").instantiate()
	config_menu.plugin = self
	get_editor_interface().get_base_control().add_child(config_menu)
	add_tool_menu_item("GD-Sync", config_selected)
	
	var previous_version : String = ProjectSettings.get_setting("GD-Sync/version", version)
	ProjectSettings.set_setting("GD-Sync/version", version)
	
	print_rich("[color=#408EAB][b]GD-Sync version "+version+" enabled.[/b][/color]")
	
	if FileAccess.file_exists(CSHARP_PATH):
		print_rich("[color=#408EAB]	- GD-Sync C# API detected and enabled.[/color]")
	
	if Engine.has_singleton("Steam"):
		print_rich("[color=#408EAB]	- Steam integration detected and enabled.[/color]")
	
	check_for_updates_and_news()
	_initialize_remote_call_validator()
	add_debugger_plugin(debugger)

func _exit_tree() -> void:
	config_menu.free()
	remove_debugger_plugin(debugger)

func config_selected() -> void:
	config_menu.open()

func enable_csharp_api() -> void:
	if FileAccess.file_exists(CSHARP_PATH): return
	
	var request : HTTPRequest = HTTPRequest.new()
	add_child(request)
	
	request.download_file = CSHARP_PATH
	request.request(CSHARP_URL)
	var result = await request.request_completed
	
	if result[1] == 200:
		add_autoload_singleton("GDSyncSharp", CSHARP_PATH)
		show_message("[b]GD-Sync C# API installed. Please restart and build your project.[/b]")
	else:
		show_message("[color=indianred][b]GD-Sync C# API failed to download. Please disable and enable C# support to try again.[/b][/color]")
	
	request.queue_free()

func disable_csharp_api() -> void:
	if !FileAccess.file_exists(CSHARP_PATH): return
	show_message("[b]GD-Sync C# API removed.[/b]")
	
	var dir : DirAccess = DirAccess.open(PLUGIN_PATH)
	dir.remove("GDSync.cs")
	
	remove_autoload_singleton("GDSyncSharp")

func check_for_updates_and_news() -> void:
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
	var url : String = "https://www.gd-sync.com/version"
	request.request(
		url,
		[],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var html : String = result[3].get_string_from_ascii()
		var data : Dictionary = extract_data_from_html(html)
		
		var new_version : String = data.get("version", version)
		if is_version_newer(version, new_version):
			config_menu.update_ready()
			show_message("[color=#61ff71][b]A new version of GD-Sync is available.[/b][/color]
[color=#61ff71]You can upgrade to version "+new_version+" in the configuration menu (Project -> Tools -> GD-Sync).[/color]

[color=#61ff71][url=https://www.gd-sync.com/news]Click here for the patch notes.[/url][/color]", 10.0)
		print("")
		for news in data.get("news", []):
			print_rich(news)

func extract_data_from_html(html: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("<p[^>]*class=['\\\"]paragraph['\\\"][^>]*>(.*?)</p>")
	var m := re.search(html)
	if m == null:
		return {}
	var txt := m.get_string(1).strip_edges().replace("&quot;", "\"")
	var v := JSON.parse_string(txt)
	if typeof(v) == TYPE_DICTIONARY:
		return v
	if typeof(v) == TYPE_ARRAY and v.size() > 0 and typeof(v[0]) == TYPE_DICTIONARY:
		return v[0]
	return {}

func is_version_newer(current_version: String, new_version: String) -> bool:
	var current_nums : PackedStringArray = current_version.split(".")
	var new_nums : PackedStringArray = new_version.split(".")
	for i in range(new_nums.size()):
		var new : int = int(new_nums[i])
		var current : int = 0 if i >= current_nums.size() else int(current_nums[i])
		if new > current:
			return true
	
	return false


func _disable_plugin() -> void:
	_disable_remote_call_validator()
	remove_tool_menu_item("GD-Sync")
	remove_autoload_singleton("GDSync")
	if FileAccess.file_exists(CSHARP_PATH): 
		remove_autoload_singleton("GDSyncSharp")

#endregion


#region CodeParser
# ==============================================================================
# Remote Call Validation
# ==============================================================================

var _script_editor: ScriptEditor
var _file_system: EditorFileSystem

func _initialize_remote_call_validator() -> void:
	_script_editor = get_editor_interface().get_script_editor()
	_file_system = get_editor_interface().get_resource_filesystem()
	
	if _script_editor.has_signal("editor_script_changed"):
		_script_editor.connect("editor_script_changed", _on_editor_script_changed)
	
	if _script_editor.has_signal("editor_script_saved"):
		_script_editor.connect("editor_script_saved", _on_script_saved)
	
	_file_system.connect("filesystem_changed", _on_filesystem_changed)

func _on_editor_script_changed(script: Script) -> void:
	if script:
		_analyze_script_for_remote_calls(script, true)
		_start_text_change_monitoring(script)

func _on_script_saved(script: Script) -> void:
	_analyze_script_for_remote_calls(script, true)

func _on_filesystem_changed() -> void:
	var current_script = _script_editor.get_current_script()
	if current_script:
		_analyze_script_for_remote_calls(current_script, true)

var _monitored_script: Script = null
var _validation_timer: Timer = null
var _last_validated_sources: Dictionary = {}

func _start_text_change_monitoring(script: Script) -> void:
	_monitored_script = script
	
	if not _validation_timer:
		_validation_timer = Timer.new()
		_validation_timer.one_shot = true
		_validation_timer.timeout.connect(_validate_monitored_script)
		add_child(_validation_timer)
	
	var editor = _script_editor.get_current_editor()
	if editor:
		var code_edit = editor.get_base_editor() as CodeEdit
		if code_edit:
			_last_validated_sources[script.resource_path] = code_edit.text
			
			if not code_edit.text_changed.is_connected(_on_code_edit_text_changed):
				code_edit.text_changed.connect(_on_code_edit_text_changed.bind(code_edit))

func _on_code_edit_text_changed(code_edit: CodeEdit) -> void:
	if not _monitored_script or _script_editor.get_current_script() != _monitored_script:
		return
	
	var current_source = code_edit.text
	_last_validated_sources[_monitored_script.resource_path] = current_source
	
	if _validation_timer:
		_validation_timer.stop()
		_validation_timer.start(1.0)

func _validate_monitored_script() -> void:
	if _monitored_script:
		_analyze_script_for_remote_calls(_monitored_script, false)

func _analyze_script_for_remote_calls(script: Script, console : bool) -> void:
	var script_validation_enabled : bool = true
	if ProjectSettings.has_setting("GD-Sync/scriptValidation"):
		script_validation_enabled = ProjectSettings.get_setting("GD-Sync/scriptValidation")
	
	if not script or not script is GDScript:
		return
	
	var script_path: String = script.resource_path
	if not script_path.ends_with(".gd"):
		return
	
	var editor = _script_editor.get_current_editor()
	if not editor:
		return
	
	var code_edit = editor.get_base_editor() as CodeEdit
	if not code_edit:
		return
	
	var parser = RemoteCallParser.new()
	var issues: PackedStringArray = parser.parse_script(code_edit.text)
	
	if console and script_validation_enabled:
		for issue in issues:
			push_warning("[GD-Sync] %s: %s" % [script_path, issue])
		
		if issues.size() > 0:
			print_rich("[color=orange][b]GD-Sync found %d issue(s) in %s[/b][/color]" % [issues.size(), script_path.get_file()])
	else:
		_set_editor_issues(issues, script_validation_enabled)

func _set_editor_issues(issues : PackedStringArray, script_validation_enabled : bool) -> void:
	var current_editor = _script_editor.get_current_editor()
	if current_editor == null:
		return
	
	var label : RichTextLabel
	
	var vsplitcontainer = find_node_of_type(current_editor, "VSplitContainer").get_parent()
	if vsplitcontainer.has_node("GDSyncWarning"):
		label = vsplitcontainer.get_node("GDSyncWarning")
	else:
		label = RichTextLabel.new()
		vsplitcontainer.add_child(label)
		label.name = "GDSyncWarning"
		label.bbcode_enabled = true
		label.scroll_active = true
	label.custom_minimum_size = Vector2(0, get_viewport().get_window().size.y*0.05)
	
	if issues.size() > 0:
		label.text = (
			"[color=#408EAB][b]GD-Sync Warnings: [/b][/color][color=gold] \n - " +
			"\n - ".join(issues)
		)
		
		label.visible = script_validation_enabled
	else:
		label.visible = false

static func find_node_of_type(node: Node, type: String, index: int = 0) -> Node:
	var found_nodes := []
	_find_nodes_of_type_recursive(node, type, found_nodes)
	
	if index < found_nodes.size():
		return found_nodes[index]
	return null

static func _find_nodes_of_type_recursive(node: Node, type: String, found_nodes: Array) -> void:
	if node.is_class(type):
		found_nodes.append(node)
	
	for child in node.get_children():
		_find_nodes_of_type_recursive(child, type, found_nodes)

class RemoteCallParser:
	func parse_script(source_code: String) -> PackedStringArray:
		var issues: PackedStringArray = []
		var lines: PackedStringArray = source_code.split("\n")
		
		if _has_expose_node(lines):
			return issues
		
		var exposed_functions: Array = _find_exposed_functions(lines)
		var exposed_variables: Array = _find_exposed_variables(lines)
		var exposed_signals : Array = _find_exposed_signals(lines)
		var remote_calls: Dictionary = _find_remote_calls(lines)
		var sync_var_calls: Dictionary = _find_sync_var_calls(lines)
		var signal_emissions : Dictionary = _find_signal_emissions(lines)
		
		for call_name in remote_calls.keys():
			if call_name not in exposed_functions:
				var line_num = remote_calls[call_name]
				issues.append("Line %d: Remote function call to '%s' but function is not exposed with GDSync.expose_func(%s)" % [line_num, call_name, call_name])
		
		for var_name in sync_var_calls.keys():
			if var_name not in exposed_variables:
				var line_num = sync_var_calls[var_name]
				issues.append("Line %d: sync_var call for '%s' but variable is not exposed with GDSync.expose_var(self, \"%s\")" % [line_num, var_name, var_name])
		
		for signal_name in signal_emissions.keys():
			if signal_name not in exposed_signals:
				var line_num = signal_emissions[signal_name]
				issues.append("Line %d: Remote signal emission '%s' but signal is not exposed with GDSync.expose_signal(%s)" % [line_num, signal_name, signal_name])
		
		return issues
	
	func _has_expose_node(lines: PackedStringArray) -> bool:
		var expose_node_pattern: RegEx = RegEx.new()
		expose_node_pattern.compile("GDSync\\.expose_node\\((self)")
		
		for line in lines:
			var comment_pos = line.find("#")
			var clean_line: String = line
			if comment_pos != -1:
				clean_line = line.substr(0, comment_pos)
			
			var result = expose_node_pattern.search(clean_line)
			if result:
				return true
		
		return false
	
	func _find_exposed_functions(lines: PackedStringArray) -> Array:
		var functions: Array = []
		var expose_func_pattern: RegEx = RegEx.new()
		expose_func_pattern.compile("GDSync\\.expose_func\\(([a-zA-Z_][a-zA-Z0-9_]*)\\)")
		
		for line in lines:
			var comment_pos = line.find("#")
			var clean_line: String = line
			if comment_pos != -1:
				clean_line = line.substr(0, comment_pos)
			
			var result = expose_func_pattern.search(clean_line)
			if result:
				var func_name: String = result.get_string(1)
				functions.append(func_name)
		
		return functions
	
	func _find_exposed_variables(lines: PackedStringArray) -> Array:
		var variables: Array = []
		var expose_var_pattern: RegEx = RegEx.new()
		expose_var_pattern.compile("GDSync\\.expose_var\\(\\s*self\\s*,\\s*\"([^\"]+)\"\\)")
		
		for line in lines:
			var comment_pos = line.find("#")
			var clean_line: String = line
			if comment_pos != -1:
				clean_line = line.substr(0, comment_pos)
			
			var result = expose_var_pattern.search(clean_line)
			if result:
				variables.append(result.get_string(1))
		
		return variables
	
	func _find_exposed_signals(lines: PackedStringArray) -> Array:
		var functions: Array = []
		var expose_func_pattern: RegEx = RegEx.new()
		expose_func_pattern.compile("GDSync\\.expose_signal\\(([a-zA-Z_][a-zA-Z0-9_]*)\\)")
		
		for line in lines:
			var comment_pos = line.find("#")
			var clean_line: String = line
			if comment_pos != -1:
				clean_line = line.substr(0, comment_pos)
			
			var result = expose_func_pattern.search(clean_line)
			if result:
				var func_name: String = result.get_string(1)
				functions.append(func_name)
		
		return functions
	
	func _find_remote_calls(lines: PackedStringArray) -> Dictionary:
		var calls: Dictionary = {}
		var call_patterns: Array = [
			RegEx.new(),
			RegEx.new(),
			RegEx.new(),
		]
		
		
		call_patterns[0].compile("GDSync\\.call_func_all\\(\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*[,\\)]")
		call_patterns[1].compile("GDSync\\.call_func\\(\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*[,\\)]")
		call_patterns[2].compile("GDSync\\.call_func_on\\(\\s*[^,]+\\s*,\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*[,\\)]")
		
		for line_num in range(lines.size()):
			var line = lines[line_num]
			
			var comment_pos = line.find("#")
			var clean_line: String = line
			if comment_pos != -1:
				clean_line = line.substr(0, comment_pos)
			
			for pattern in call_patterns:
				var result = pattern.search(clean_line)
				while result:
					var function_name: String = result.get_string(1)
					if function_name not in calls:
						calls[function_name] = line_num + 1
					result = pattern.search(clean_line, result.get_end())
		
		return calls
	
	func _find_sync_var_calls(lines: PackedStringArray) -> Dictionary:
		var vars: Dictionary = {}
		var sync_var_pattern: RegEx = RegEx.new()
		sync_var_pattern.compile("GDSync\\.sync_var\\(\\s*self\\s*,\\s*\"([^\"]+)\"\\s*[,\\)]")
		
		for line_num in range(lines.size()):
			var line = lines[line_num]
			var comment_pos = line.find("#")
			var clean_line: String = line
			if comment_pos != -1:
				clean_line = line.substr(0, comment_pos)
			
			var result = sync_var_pattern.search(clean_line)
			while result:
				var var_name: String = result.get_string(1)
				if var_name not in vars:
					vars[var_name] = line_num + 1
				result = sync_var_pattern.search(clean_line, result.get_end())
		
		return vars
	
	func _find_signal_emissions(lines: PackedStringArray) -> Dictionary:
		var calls: Dictionary = {}
		var call_patterns: Array = [
			RegEx.new(),
			RegEx.new(),
			RegEx.new(),
		]
		
		
		call_patterns[0].compile("GDSync\\.emit_signal_remote_all\\(\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*[,\\)]")
		call_patterns[1].compile("GDSync\\.emit_signal_remote\\(\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*[,\\)]")
		call_patterns[2].compile("GDSync\\.emit_signal_remote_on\\(\\s*[^,]+\\s*,\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*[,\\)]")
		
		for line_num in range(lines.size()):
			var line = lines[line_num]
			
			var comment_pos = line.find("#")
			var clean_line: String = line
			if comment_pos != -1:
				clean_line = line.substr(0, comment_pos)
			
			for pattern in call_patterns:
				var result = pattern.search(clean_line)
				while result:
					var function_name: String = result.get_string(1)
					if function_name not in calls:
						calls[function_name] = line_num + 1
					result = pattern.search(clean_line, result.get_end())
		
		return calls

func _disable_remote_call_validator() -> void:
	if _script_editor and _script_editor.has_signal("editor_script_saved"):
		_script_editor.disconnect("editor_script_saved", Callable(self, "_on_script_saved"))
	
	if _file_system and _file_system.has_signal("filesystem_changed"):
		_file_system.disconnect("filesystem_changed", Callable(self, "_on_filesystem_changed"))

#endregion


#region GD-SyncProfiler
class GDSyncProfiler extends EditorDebuggerPlugin:
	var profilers : Dictionary = {}
	var message_history : Dictionary = {}

	func _has_capture(capture):
		return capture == "gdsyncprofiler"

	func _capture(message : String, data : Array, session_id : int) -> bool:
		if !("gdsyncprofiler" in message): return false
		
		var profiler = profilers[session_id]
		if !is_instance_valid(profiler):
			return false
		
		if message == "gdsyncprofiler:registertransfer":
			profiler.callv("register_transfer_usage", data)
			return true
		
		message_history[session_id].append([message, data.duplicate(true), session_id])
		
		if message == "gdsyncprofiler:setdata":
			profiler.callv("register_custom_data", data)
		elif message == "gdsyncprofiler:pingmeasured":
			data.push_front("ping_measured")
			profiler.callv("emit_signal", data)
		elif message == "gdsyncprofiler:clientjoined":
			data.push_front("client_joined")
			profiler.callv("emit_signal", data)
		elif message == "gdsyncprofiler:clientleft":
			data.push_front("client_left")
			profiler.callv("emit_signal", data)
		elif message == "gdsyncprofiler:gamestart":
			profiler.game_started()
		return true

	func _setup_session(session_id : int):
		var profiler_scene : PackedScene = load("res://addons/GD-Sync/UI/Profiler/GDSyncProfiler.tscn")
		if profiler_scene == null: return
		var profiler : Control = profiler_scene.instantiate()
		profiler.name = "GD-Sync Profiler"
		var session = get_session(session_id)
		
		message_history[session_id] = []
		
		session.started.connect(func ():
			profiler.validate_session()
			message_history[session_id].clear()
			profiler.clear())
		session.stopped.connect(func (): 
			profiler.stop()
			profiler.invalidate_session())
		
		profiler.profiler_cleared.connect(func ():
			var history : Array = message_history[session_id].duplicate(true)
			await profiler.get_tree().process_frame
			
			for message in history:
				_capture.callv(message)
			
			message_history[session_id] = history
		)
		profiler.profiler_started.connect(func ():
			get_session(session_id).send_message("gdsyncprofiler:start", [])
		)
		profiler.profiler_stopped.connect(func ():
			get_session(session_id).send_message("gdsyncprofiler:stop", [])
		)
		
		profiler.start_monitoring_connections.connect(func ():
			get_session(session_id).send_message("gdsyncprofiler:start_monitoring_connections", [])
		)
		profiler.stop_monitoring_connections.connect(func ():
			get_session(session_id).send_message("gdsyncprofiler:stop_monitoring_connections", [])
		)
		
		session.add_session_tab(profiler)
		profilers[session_id] = profiler

#endregion


#region ToastMessages
var message_count : int = 0

func show_message(message : String, duration : float = 5.0) -> void:
	var message_packed : PackedScene = load("res://addons/GD-Sync/UI/Messages/ToastMessage.tscn")
	if message_packed == null: return
	
	var message_scene : Control = message_packed.instantiate()
	message_scene.name = "GDSyncMessage"+str(message_count)
	message_count += 1
	
	get_editor_interface().get_base_control().add_child(message_scene)
	message_scene.set_message(message, true, duration)
	message_scene.tree_exiting.connect(_on_message_destroyed)
	
	_update_all_message_positions()

func _on_message_destroyed() -> void:
	await get_tree().process_frame
	_update_all_message_positions()

func _update_all_message_positions() -> void:
	var messages : Array = []
	for child in get_editor_interface().get_base_control().get_children():
		if "GDSyncMessage" in child.name and child.has_method("get_height"):
			messages.append(child)
	
	var cumulative_height : float = 0.0
	for i in range(messages.size() - 1, -1, -1):
		var message = messages[i]
		if i == messages.size()-1:
			cumulative_height += message.get_height()*0.5
		else:
			cumulative_height += message.get_height()
		message.update_position(cumulative_height)
#endregion
