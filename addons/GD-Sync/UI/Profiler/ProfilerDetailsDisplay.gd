@tool
extends Control

#Copyright (c) 2026 GD-Sync.
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

@export var type_sort_button : Button
@export var object_sort_button : Button
@export var target_sort_button : Button
@export var count_sort_button : Button
@export var usage_sort_button : Button
@export var percent_sort_button : Button
@export var listen_key : String = "up"
@export var profiler : Node = null
@export var label_template : Node = null

var existing_labels : Dictionary = {}
var current_sort_key : String = "total_bytes"
var sort_reversed : bool = false
var sorted_keys : Array = []
var data_cache : Dictionary = {}

var sort_thread : Thread
var data_mutex : Mutex
var pending_data_update : Dictionary = {}
var pending_remove_keys : Array = []
var has_pending_changes : bool = false
var should_stop_thread : bool = false

func _ready() -> void:
	data_mutex = Mutex.new()
	
	if label_template:
		label_template.visible = false
	
	if profiler:
		_connect_signals()
	
	_connect_sort_buttons()
	_update_button_states()

func _exit_tree() -> void:
	_stop_thread()
	_disconnect_signals()

func _stop_thread() -> void:
	should_stop_thread = true
	if sort_thread and sort_thread.is_started():
		sort_thread.wait_to_finish()

func _start_thread_if_needed() -> void:
	if not sort_thread or not sort_thread.is_started():
		sort_thread = Thread.new()
		should_stop_thread = false
		sort_thread.start(_thread_process)

func _thread_process() -> void:
	while not should_stop_thread:
		data_mutex.lock()
		var has_changes = has_pending_changes
		var local_data_update = pending_data_update.duplicate(true)
		var local_remove_keys = pending_remove_keys.duplicate()
		var local_data_cache = data_cache.duplicate(true)
		var local_existing_keys = existing_labels.keys()
		var local_sort_key = current_sort_key
		var local_sort_reversed = sort_reversed
		
		if has_changes:
			pending_data_update.clear()
			pending_remove_keys.clear()
			has_pending_changes = false
		data_mutex.unlock()
		
		if has_changes:
			var new_data_cache = local_data_cache.duplicate(true)
			
			for key in local_data_update.keys():
				new_data_cache[key] = {
					"type":        local_data_update[key].type,
					"object":      local_data_update[key].object,
					"target":      local_data_update[key].target,
					"count":       local_data_update[key].count,
					"total_bytes": local_data_update[key].total_bytes,
					"percent":     local_data_update[key].percent
				}
			
			for key in local_remove_keys:
				new_data_cache.erase(key)
			
			var new_sorted_keys = local_existing_keys.duplicate()
			
			if not local_sort_key.is_empty():
				new_sorted_keys.sort_custom(func(a, b):
					var va = _get_raw_sort_value_thread(a, new_data_cache, local_sort_key)
					var vb = _get_raw_sort_value_thread(b, new_data_cache, local_sort_key)

					if va == vb:
						return a < b

					if local_sort_reversed:
						return va > vb
					else:
						return va < vb
				)
			else:
				new_sorted_keys.sort()
			
			call_deferred("_apply_thread_results", new_sorted_keys, new_data_cache)
		
		OS.delay_msec(16)

func _get_raw_sort_value_thread(key : String, cache : Dictionary, sort_key : String) -> Variant:
	if not cache.has(key):
		return key
	var e = cache[key]
	match sort_key:
		"type":        return e.type
		"object":      return e.object
		"target":      return e.target
		"count":       return e.count
		"total_bytes": return e.total_bytes
		"percent":     return e.percent
		_:             return key

func _apply_thread_results(new_sorted_keys : Array, new_data_cache : Dictionary) -> void:
	data_mutex.lock()
	data_cache = new_data_cache
	sorted_keys = new_sorted_keys
	data_mutex.unlock()
	
	_reorder_labels_ui()

# -------------------------------------------------------------------------
#  Signal handling
# -------------------------------------------------------------------------
func _connect_signals() -> void:
	if profiler.has_signal("message_details_updated") and not profiler.message_details_updated.is_connected(_on_message_details):
		profiler.message_details_updated.connect(_on_message_details)
	if profiler.has_signal("profiler_cleared") and not profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.connect(_on_clear)

func _disconnect_signals() -> void:
	if profiler and profiler.message_details_updated.is_connected(_on_message_details):
		profiler.message_details_updated.disconnect(_on_message_details)
	if profiler and profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.disconnect(_on_clear)

func _on_clear() -> void:
	data_mutex.lock()
	for l in existing_labels.values():
		l.queue_free()
	existing_labels.clear()
	data_cache.clear()
	sorted_keys.clear()
	pending_data_update.clear()
	pending_remove_keys.clear()
	has_pending_changes = false
	data_mutex.unlock()
	
	current_sort_key = "total_bytes"
	sort_reversed = false
	_update_button_states()

# -------------------------------------------------------------------------
#  Sort-button handling
# -------------------------------------------------------------------------
func _connect_sort_buttons() -> void:
	var map = {
		"type":        type_sort_button,
		"object":      object_sort_button,
		"target":      target_sort_button,
		"count":       count_sort_button,
		"total_bytes": usage_sort_button,
		"percent":     percent_sort_button
	}
	for k in map.keys():
		var btn = map[k]
		if btn and btn.pressed.get_connections().size() == 0:
			btn.pressed.connect(func(): _sort_by(k))

func _sort_by(key : String) -> void:
	if current_sort_key == key:
		sort_reversed = !sort_reversed          # toggle direction
	else:
		current_sort_key = key
		sort_reversed = false                  # default = descending (biggest on top)
	_update_button_states()
	_schedule_rebuild()

func _update_button_states() -> void:
	var map = {
		"type":        type_sort_button,
		"object":      object_sort_button,
		"target":      target_sort_button,
		"count":       count_sort_button,
		"total_bytes": usage_sort_button,
		"percent":     percent_sort_button
	}
	for k in map.keys():
		var btn = map[k]
		if btn:
			btn.text = _get_button_text(k)

func _get_button_text(key : String) -> String:
	var base = key.capitalize()
	if current_sort_key == key:
		return base + (" (descending)" if !sort_reversed else " (ascending)")
	return base

# -------------------------------------------------------------------------
#  Data → UI
# -------------------------------------------------------------------------
func _on_message_details(details : Dictionary) -> void:
	if !details.has(listen_key): return
	var data : Dictionary = details[listen_key]

	data_mutex.lock()
	
	var changed = false
	for k in data.keys():
		if not existing_labels.has(k):
			changed = true
			# Create label immediately on main thread
			var label = label_template.duplicate()
			add_child(label)
			label.visible = true
			existing_labels[k] = label
		
		# Update UI immediately
		_populate_label(k, data[k])
		
		# Queue data for thread processing
		pending_data_update[k] = {
			"type":        data[k].type,
			"object":      data[k].object,
			"target":      data[k].target,
			"count":       data[k].count,
			"total_bytes": data[k].total_bytes,
			"percent":     data[k].percent
		}

	# Find keys to remove
	var current_keys = data.keys()
	var to_remove = []
	for k in existing_labels.keys():
		if !current_keys.has(k):
			to_remove.append(k)
			changed = true
	
	# Remove labels immediately from UI but keep in cache for thread
	for k in to_remove:
		existing_labels[k].queue_free()
		existing_labels.erase(k)
		pending_remove_keys.append(k)

	if changed:
		has_pending_changes = true
		_start_thread_if_needed()
	
	data_mutex.unlock()

func _populate_label(key : String, data : Dictionary) -> void:
	var label = existing_labels.get(key)
	if not label:
		return

	label.get_node("Data/Object").text = get_final_segment(data["object"])
	label.get_node("Data/Object").tooltip_text = data["object"]
	label.get_node("Data/Target").text = data["target"]
	label.get_node("Data/Count").text = _format_number(data["count"])
	label.get_node("Data/Count").tooltip_text = "This message was sent %s times." % [_format_number(data["count"])]
	label.get_node("Data/Usage").text = _format_bytes(data["total_bytes"])
	label.get_node("Data/Usage").tooltip_text = "These messages have used %s of transfer." % [_format_bytes(data["total_bytes"])]
	
	var percent : float = data["percent"]
	var color_value_yellow : float = percent / 100.0
	var color_value_red : float = color_value_yellow*2.0-1.0
	color_value_yellow = min(color_value_yellow*2.0, 1.0)
	color_value_red = max(color_value_red, 0.0)
	
	var color = Color.CHARTREUSE.lerp(Color.GOLD, color_value_yellow).lerp(Color.TOMATO, color_value_red)
	var color_hex = color.to_html(false)
	
	var percent_text = "[color=%s]%.*f%%[/color]" % [color_hex, 2, percent]
	label.get_node("Data/Percentage").text = percent_text
	label.get_node("Data/Percentage").tooltip_text = "These messages contributed %.*f%% of the total %s transfer." % [2, percent, "incoming" if listen_key == "down" else "outgoing"]
	
	var type_tooltip : String = data["type"]
	var type_color : String = Color.WHITE.to_html(false)
	match(data["type"]):
		"internal":
			type_tooltip = "An internal message of GD-Sync which may provide extra functionality or optimizations."
			type_color = "#f5c2e7"
		"call_func":
			type_tooltip = "A script used call_func, call_func_on or call_func_all to remotely call a function on a Node or Resource."
			type_color = "#a6e3a1"
		"call_func optimized":
			type_tooltip = "A script used call_func, call_func_on or call_func_all to remotely call a function on a Node or Resource. \nThis is an optimized version which caches caches the NodePath and function name and replaces them with integers to save transfer."
			type_color = "#a6e3a1"
		"sync_var":
			type_tooltip = "A script used sync_var or sync_var_on to synchronize the value of a property on all clients."
			type_color = "#89b4fa"
		"sync_var optimized":
			type_tooltip = "A script used sync_var or sync_var_on to synchronize the value of a property on all clients. \nThis is an optimized version which caches caches the NodePath and property name and replaces them with integers to save transfer."
			type_color = "#89b4fa"
	label.get_node("Data/Type").text = "[color=%s]%s[/color]" % [type_color, data["type"]]
	label.get_node("Data/Type").tooltip_text = type_tooltip
	
	var target_node = label.get_node("Data/Target")
	if data.has("last_details") and data["last_details"] is Array and not data["last_details"].is_empty():
		var details_list = data["last_details"]
		var tooltip_text = data["target"]
		tooltip_text += "\n\nLast messages:\n" + "─".repeat(20) + "\n"
		
		for i in range(details_list.size() - 1, -1, -1):
			tooltip_text += details_list[i] + "\n"
			if i > 0:
				tooltip_text += "─".repeat(20) + "\n"
		
		target_node.tooltip_text = tooltip_text
	else:
		target_node.tooltip_text = data["target"]

func get_final_segment(path: String) -> String:
	var parts = path.strip_edges().split("/")
	return parts[-1] if parts.size() > 0 else path

func _format_number(n : int) -> String:
	var s = str(abs(n))
	var result = ""
	for i in range(s.length() - 1, -1, -1):
		if (s.length() - 1 - i) % 3 == 0 and i < s.length() - 1:
			result = "." + result
		result = s[i] + result
	return ("-" if n < 0 else "") + result

func _format_bytes(b : int) -> String:
	if b <= 0: return "0 B"
	var u = ["B","KB","MB","GB"]
	var i = 0
	var v = float(b)
	while v >= 1000.0 and i < 3:
		v /= 1000.0
		i += 1
	return "%.*f %s" % [1 if i > 0 else 0, v, u[i]]

func _schedule_rebuild() -> void:
	data_mutex.lock()
	has_pending_changes = true
	data_mutex.unlock()
	_start_thread_if_needed()

func _reorder_labels_ui() -> void:
	data_mutex.lock()
	var local_sorted_keys = sorted_keys.duplicate()
	data_mutex.unlock()

	var idx = get_child_count() - 1
	for k in local_sorted_keys:
		var label = existing_labels.get(k)
		if label and label.get_index() != idx:
			move_child(label, idx)
		idx -= 1
