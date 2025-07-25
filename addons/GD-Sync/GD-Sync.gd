@tool
extends EditorPlugin

#Copyright (c) 2025 GD-Sync.
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

const CSHARP_URL : String = "https://raw.githubusercontent.com/GD-Sync/GD-SyncCSharp/main/GDSync.cs"
const PLUGIN_PATH : String = "res://addons/GD-Sync"
const CSHARP_PATH : String = "res://addons/GD-Sync/GDSync.cs"

var load_balancers : PackedStringArray = [
	"lb1.gd-sync.com",
	"lb2.gd-sync.com",
	"lb3.gd-sync.com",
]

var version : String = "0.11"

func _enable_plugin() -> void:
	add_autoload_singleton("GDSync", "res://addons/GD-Sync/MultiplayerClient.gd")
	
	print_rich("[color=#408EAB]	- Please visit our website for more info (https://www.gd-sync.com)[/color]")
	print_rich("[color=#408EAB]	- The plugin configuration menu can be found under Project > Tools > GD-Sync.[/color]")

func _disable_plugin() -> void:
	remove_tool_menu_item("GD-Sync")
	remove_autoload_singleton("GDSync")
	if FileAccess.file_exists(CSHARP_PATH): remove_autoload_singleton("GDSyncSharp")

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

func _exit_tree() -> void:
	config_menu.free()

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
		print_rich("[color=#408EAB][b]GD-Sync C# API installed. Please restart and build your project.[/b][/color]")
	else:
		print_rich("[color=indianred][b]GD-Sync C# API failed to download. Please disable and enable C# support to try again.[/b][/color]")
	
	request.queue_free()

func disable_csharp_api() -> void:
	if !FileAccess.file_exists(CSHARP_PATH): return
	print_rich("[color=#408EAB][b]GD-Sync C# API removed.[/b][/color]")
	
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
			print("")
			print_rich("[color=#61ff71][b]A new version of GD-Sync is available.[/b][/color]")
			print_rich("[color=#61ff71]	- You can upgrade to version "+new_version+" in the configuration menu (Project -> Tools -> GD-Sync).[/color]")
			print_rich("[color=#61ff71]	- [url=https://www.gd-sync.com/news]Click here for the patch notes.[/url][/color]")
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
