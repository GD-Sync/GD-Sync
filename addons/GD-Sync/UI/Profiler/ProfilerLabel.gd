@tool
extends RichTextLabel

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

@export var profiler : Node = null : set = _set_profiler
@export var client_id : int = -1
@export var stat_key : String = "up_sec"
@export var is_bytes : bool = true
@export var decimal_places : int = 1
@export var suffix : String = "/s"
@export var color_hex : String = "#ffffff"
@export var label_text : String = "Upload" : set = _set_label_text
@export var show_label_text : bool = true
@export_group("Custom Data")
@export var use_custom_data : bool = false
@export var show_missing : bool = true
@export var missing_text : String = "N/A"

func _ready():
	bbcode_enabled = true
	_update_display()
	if profiler:
		_connect_signal()

func _set_profiler(v):
	if profiler == v: return
	if profiler:
		_disconnect_signal()
	profiler = v
	if profiler:
		_connect_signal()
	_update_display()

func _set_label_text(v):
	label_text = v
	_update_display()

func _connect_signal():
	if not profiler: return
	if profiler.has_signal("stats_updated") and not profiler.stats_updated.is_connected(_on_stats_updated):
		profiler.stats_updated.connect(_on_stats_updated)
	if profiler.has_signal("custom_data_updated") and not profiler.custom_data_updated.is_connected(_on_custom_data):
		profiler.custom_data_updated.connect(_on_custom_data)
	if profiler.has_signal("profiler_cleared") and not profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.connect(_on_clear)

func _disconnect_signal():
	if not profiler: return
	if profiler.has_signal("stats_updated") and profiler.stats_updated.is_connected(_on_stats_updated):
		profiler.stats_updated.disconnect(_on_stats_updated)
	if profiler.has_signal("custom_data_updated") and profiler.custom_data_updated.is_connected(_on_custom_data):
		profiler.custom_data_updated.disconnect(_on_custom_data)
	if profiler.has_signal("profiler_cleared") and profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.disconnect(_on_clear)

func _on_stats_updated(cid : int, stats : Dictionary):
	if use_custom_data: return
	if client_id != -1 and cid != client_id: return
	if client_id == -1 and cid != -1: return
	var val = stats.get(stat_key, 0.0)
	var value_str = _format_value(val)
	_set_text(value_str)

func _on_custom_data(data : Dictionary):
	if not use_custom_data: return
	_update_from_custom_data(data)

func _on_clear():
	if use_custom_data:
		_update_from_custom_data({})
	else:
		_update_display()

func _update_from_custom_data(data : Dictionary):
	var val = data.get(stat_key, null)
	if val == null:
		if show_missing:
			_set_text(missing_text)
		else:
			text = ""
	else:
		var formatted = _format_custom_value(val)
		_set_text(formatted)

func _update_display():
	if use_custom_data:
		_update_from_custom_data({})
	else:
		_set_text("...")

func _set_text(value_str : String):
	var prefix = label_text + ": " if show_label_text else ""
	text = "[color=%s]%s%s[/color]" % [color_hex, prefix, value_str]

func _format_value(b) -> String:
	if is_nan(b) or is_inf(b):
		return "0 B" + suffix
	if not is_bytes:
		return _format_number(int(b)) + suffix
	if b == 0:
		return "0 B" + suffix
	var u = ["B","KB","MB","GB"]
	var i = 0
	var v = abs(b)
	while v >= 1000.0 and i < 3:
		v /= 1000.0
		i += 1
	var formatted = "%.*f" % [decimal_places, v]
	var parts = formatted.split(".")
	var int_part = _format_number(int(parts[0]))
	var frac_part = ("." + parts[1]) if parts.size() > 1 else ""
	return ("-" if b < 0 else "") + int_part + frac_part + " " + u[i] + suffix

func _format_custom_value(val) -> String:
	match typeof(val):
		TYPE_FLOAT, TYPE_INT:
			if abs(val) >= 1000.0 and is_bytes:
				return _format_bytes(float(val), decimal_places)
			else:
				return "%.*f" % [decimal_places, val] if typeof(val) == TYPE_FLOAT else str(val)
		TYPE_BOOL:
			return "True" if val else "False"
		TYPE_STRING:
			return val
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, \
		TYPE_PACKED_COLOR_ARRAY:
			return _pretty_print_array(val)
		TYPE_DICTIONARY:
			return _pretty_print_dict(val)
		TYPE_COLOR:
			return _format_color(val)
		_:
			return str(val)

func _pretty_print_array(arr, indent_level := 0) -> String:
	if arr.is_empty():
		return "[]"
	var indent := "  "
	var result := "[\n"
	for i in arr.size():
		var item = arr[i]
		var formatted = _pretty_print_value(item, indent_level + 1)
		result += indent.repeat(indent_level + 1) + formatted
		if i < arr.size() - 1:
			result += ","
		result += "\n"
	result += indent.repeat(indent_level) + "]"
	return result

func _pretty_print_dict(dict : Dictionary, indent_level := 0) -> String:
	if dict.is_empty():
		return "{}"
	var indent := "  "
	var result := "{\n"
	var keys = dict.keys()
	keys.sort()
	for i in keys.size():
		var key = keys[i]
		var value = dict[key]
		var key_type = typeof(key)
		var key_str = _escape_string(str(key))
		var key_color = _get_type_color(key_type)
		var formatted = _pretty_print_value(value, indent_level + 1)
		result += indent.repeat(indent_level + 1) + "[color=%s]%s[/color]: %s" % [key_color, key_str, formatted]
		if i < keys.size() - 1:
			result += ","
		result += "\n"
	result += indent.repeat(indent_level) + "}"
	return result

func _pretty_print_value(val, indent_level := 0) -> String:
	match typeof(val):
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, \
		TYPE_PACKED_COLOR_ARRAY:
			return _pretty_print_array(val, indent_level)
		TYPE_DICTIONARY:
			return _pretty_print_dict(val, indent_level)
		TYPE_COLOR:
			return _format_color(val)
		TYPE_STRING:
			if val.is_valid_int() or val.is_valid_float():
				return "[color=#f5c2e7]%s[/color]" % _escape_string(val)
			else:
				return "[color=#a6e3a1]%s[/color]" % _escape_string(val)
		TYPE_INT, TYPE_FLOAT:
			return "[color=#89b4fa]%s[/color]" % _format_custom_value(val)
		TYPE_BOOL:
			return "[color=#f38ba8]Yes[/color]" if val else "[color=#f38ba8]No[/color]"
		_:
			return "[color=#cdd6f4]%s[/color]" % str(val)

func _format_color(col : Color) -> String:
	var hex = col.to_html(false)
	return "[color=#%s]██[/color] %s" % [hex, col]

func _escape_string(s : String) -> String:
	return "\"" + s.replace("\"", "\\\"") + "\""

func _get_type_color(t : int) -> String:
	match t:
		TYPE_STRING: return "#f5c2e7"
		TYPE_INT, TYPE_FLOAT: return "#89b4fa"
		TYPE_BOOL: return "#f38ba8"
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, \
		TYPE_PACKED_COLOR_ARRAY: return "#cba6f7"
		TYPE_DICTIONARY: return "#f9e2af"
		TYPE_COLOR: return "#94e2d5"
		_: return "#cdd6f4"

func _format_bytes(b : float, d := 1) -> String:
	if b <= 0: return "0 B"
	var u = ["B","KB","MB","GB"]
	var i = 0
	var v = abs(b)
	while v >= 1000.0 and i < 3:
		v /= 1000.0
		i += 1
	return "%.*f %s" % [d, v, u[i]]

func _format_number(n : float) -> String:
	var s = str(int(abs(n)))
	var result = ""
	for i in range(s.length() - 1, -1, -1):
		if (s.length() - 1 - i) % 3 == 0 and i < s.length() - 1:
			result = "." + result
		result = s[i] + result
	return ("-" if n < 0 else "") + result
