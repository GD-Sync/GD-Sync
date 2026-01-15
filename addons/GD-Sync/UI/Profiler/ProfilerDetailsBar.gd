@tool
extends HBoxContainer

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

@export var profiler : Node = null
@export var listen_key : String = "up"
@export var other_threshold : float = 2.0
@export var bar_segment_template : Control = null
@export var other_color : Color = Color("#888888")
@export var color_palette : Array[Color] = [
	Color("#e6194b"), Color("#3cb44b"), Color("#ffe119"), Color("#4363d8"),
	Color("#f58231"), Color("#911eb4"), Color("#46f0f0"), Color("#f032e6"),
	Color("#bcf60c"), Color("#fabebe"), Color("#008080"), Color("#e6beff")
]

var segment_cache : Dictionary = {}
var data_cache : Dictionary = {}
var rebuild_scheduled : bool = false

func _ready() -> void:
	if bar_segment_template:
		bar_segment_template.visible = false
	
	if profiler:
		_connect_signals()

func _connect_signals() -> void:
	if profiler.has_signal("message_details_updated") and not profiler.message_details_updated.is_connected(_on_details):
		profiler.message_details_updated.connect(_on_details)
	if profiler.has_signal("profiler_cleared") and not profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.connect(_on_clear)

func _disconnect_signals() -> void:
	if profiler and profiler.message_details_updated.is_connected(_on_details):
		profiler.message_details_updated.disconnect(_on_details)
	if profiler and profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.disconnect(_on_clear)

func _on_clear() -> void:
	for seg in segment_cache.values():
		seg.queue_free()
	segment_cache.clear()
	data_cache.clear()
	_schedule_rebuild()

func _on_details(details : Dictionary) -> void:
	if !details.has(listen_key): return
	var raw_data : Dictionary = details[listen_key]
	
	var object_stats : Dictionary = {}
	for key in raw_data.keys():
		var entry = raw_data[key]
		var obj = entry.object
		if not object_stats.has(obj):
			object_stats[obj] = { "total_bytes": 0, "percent": 0.0, "keys": [] }
		object_stats[obj].total_bytes += entry.total_bytes
		object_stats[obj].keys.append(key)
	
	var total_bytes : int = 0
	for obj in object_stats.keys():
		total_bytes += object_stats[obj].total_bytes
	
	if total_bytes == 0:
		_clear_all_segments()
		return
	
	for obj in object_stats.keys():
		var bytes = object_stats[obj].total_bytes
		object_stats[obj].percent = (bytes as float / total_bytes) * 100.0
	
	var major_objects : Array = []
	var other_bytes : int = 0
	var other_keys : Array = []
	
	for obj in object_stats.keys():
		var pct = object_stats[obj].percent
		if pct >= other_threshold:
			major_objects.append({
				"name": obj,
				"percent": pct,
				"bytes": object_stats[obj].total_bytes,
				"keys": object_stats[obj].keys
			})
		else:
			other_bytes += object_stats[obj].total_bytes
			other_keys.append_array(object_stats[obj].keys)
	
	var other_pct = (other_bytes as float / total_bytes) * 100.0 if total_bytes > 0 else 0.0
	if other_pct > 0.0:
		major_objects.append({
			"name": "Other",
			"percent": other_pct,
			"bytes": other_bytes,
			"keys": other_keys
		})
	
	major_objects.sort_custom(func(a, b): return a.percent > b.percent)
	
	data_cache.clear()
	for item in major_objects:
		data_cache[item.name] = item
	
	_schedule_rebuild()

func _schedule_rebuild() -> void:
	if rebuild_scheduled: return
	rebuild_scheduled = true
	call_deferred("_rebuild_bar_deferred")

func _rebuild_bar_deferred() -> void:
	if not rebuild_scheduled: return
	rebuild_scheduled = false
	
	var ordered_names : Array = data_cache.keys()
	ordered_names.sort_custom(func(a, b):
		return data_cache[a].percent > data_cache[b].percent
	)
	
	var total_percent : float = 0.0
	for item in data_cache.values():
		total_percent += item.percent
	total_percent = max(total_percent, 100.0)
	
	var color_idx = 0
	for obj_name in ordered_names:
		var item = data_cache[obj_name]
		var seg = _get_or_create_segment(obj_name)
		
		var col = other_color if obj_name == "Other" else color_palette[color_idx % color_palette.size()]
		seg.modulate = col
		color_idx += 1
		
		var ratio = item.percent / total_percent * 100.0
		seg.size_flags_stretch_ratio = ratio
		
		var tooltip = "%s\n%.2f%% (%s)" % [
			obj_name,
			item.percent,
			_format_bytes(item.bytes)
		]
		seg.tooltip_text = tooltip
		
		seg.set_meta("keys", item.keys)
		
		if seg.get_index() != get_child_count() - 1:
			move_child(seg, -1)
	
	_remove_unused_segments(ordered_names)

func _get_or_create_segment(obj_name : String) -> Control:
	if segment_cache.has(obj_name):
		return segment_cache[obj_name]
	
	var seg = bar_segment_template.duplicate()
	add_child(seg)
	seg.visible = true
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.mouse_filter = Control.MOUSE_FILTER_PASS
	
	seg.connect("mouse_entered", func():
		seg.modulate.a = 0.8
	)
	seg.connect("mouse_exited", func():
		seg.modulate.a = 1.0
	)
	
	segment_cache[obj_name] = seg
	return seg

func _remove_unused_segments(current_objects : Array) -> void:
	var to_remove = []
	for name in segment_cache.keys():
		if !current_objects.has(name):
			to_remove.append(name)
	
	for name in to_remove:
		segment_cache[name].queue_free()
		segment_cache.erase(name)

func _clear_all_segments() -> void:
	for seg in segment_cache.values():
		seg.queue_free()
	segment_cache.clear()

func _format_bytes(b : int) -> String:
	if b <= 0: return "0 B"
	var u = ["B","KB","MB","GB"]
	var i = 0
	var v = float(b)
	while v >= 1000.0 and i < 3:
		v /= 1000.0
		i += 1
	return "%.*f %s" % [1 if i > 0 else 0, v, u[i]]
