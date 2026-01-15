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

@export var profiler : Node = null : set = _set_profiler
@export var client_id : int = -1
@export var series : Array[Dictionary] = [
	{"key": "up_sec", "color": Color("#4ade80"), "label": "Upload"},
	{"key": "down_sec", "color": Color("#60a5fa"), "label": "Download"}
]
@export var history_seconds : int = 60
@export var padding := Vector2(40, 30)
@export var grid_color := Color(0.3, 0.3, 0.3, 0.5)
@export var text_color := Color.WHITE
@export var bg_color := Color(0.1, 0.1, 0.1, 0.8)
@export var font_size := 12
@export_enum("Bytes", "Milliseconds") var display_mode : int = 0:
	set = _set_display_mode

var data_series : Array = []

func _ready():
	_setup_series()
	if profiler:
		_connect_signal()

func _set_display_mode(mode):
	display_mode = mode
	queue_redraw()

func _set_profiler(v):
	if profiler == v: return
	if profiler:
		_disconnect_signal()
	profiler = v
	if profiler:
		_connect_signal()

func _setup_series():
	data_series.clear()
	for s in series:
		var ds = {
			"values": [],
			"color": s.color,
			"label": s.label
		}
		ds.values.resize(history_seconds)
		ds.values.fill(0.0)
		data_series.append(ds)

func _connect_signal():
	if not profiler: return
	if profiler.has_signal("stats_updated") and not profiler.stats_updated.is_connected(_on_stats_updated):
		profiler.stats_updated.connect(_on_stats_updated)
	if profiler.has_signal("profiler_cleared") and not profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.connect(_on_clear)

func _disconnect_signal():
	if not profiler: return
	if profiler.has_signal("stats_updated") and profiler.stats_updated.is_connected(_on_stats_updated):
		profiler.stats_updated.disconnect(_on_stats_updated)
	if profiler.has_signal("profiler_cleared") and profiler.profiler_cleared.is_connected(_on_clear):
		profiler.profiler_cleared.disconnect(_on_clear)

func _on_stats_updated(cid : int, stats : Dictionary):
	if client_id != -1 and cid != client_id: return
	if client_id == -1 and cid != -1: return
	for i in data_series.size():
		var key = series[i].key
		var val = stats.get(key, 0.0)
		var ds = data_series[i]
		ds.values.pop_back()
		ds.values.push_front(val)
	queue_redraw()

func _on_clear():
	_setup_series()
	queue_redraw()

func _nice_number(value : float, round_up : bool) -> float:
	var exponent = floor(log(value) / log(10.0))
	var fraction = value / pow(10.0, exponent)
	var nice_fraction = 10.0 if round_up else 1.0
	if fraction <= 1.0: nice_fraction = 1.0
	elif fraction <= 2.0: nice_fraction = 2.0
	elif fraction <= 5.0: nice_fraction = 5.0
	else: nice_fraction = 10.0
	return nice_fraction * pow(10.0, exponent)

func _draw():
	var rect = get_rect()
	draw_rect(rect, bg_color)

	if data_series.is_empty(): return

	var graph_rect = rect.grow_individual(-padding.x, -padding.y, -padding.x, -padding.y)
	var w = graph_rect.size.x
	var h = graph_rect.size.y
	var x0 = graph_rect.position.x
	var y0 = graph_rect.position.y

	var all_vals : Array = []
	for ds in data_series:
		for v in ds.values:
			if v > 0: all_vals.append(v)
	var raw_max = all_vals.max() if not all_vals.is_empty() else 1000.0
	var max_val = _nice_number(raw_max * 1.05, true)
	max_val = max(max_val, 1.0)

	var grid_levels = 5
	for i in range(grid_levels + 1):
		var y = y0 + h * i / float(grid_levels)
		draw_line(Vector2(x0, y), Vector2(x0 + w, y), grid_color, 1.0)
		var label_val = max_val * (1.0 - i / float(grid_levels))
		var label = _format_value(label_val, 1)
		draw_string(ThemeDB.fallback_font, Vector2(x0 - 5, y + 5), label, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, text_color)

	for idx in data_series.size():
		var ds = data_series[idx]
		var points : Array = []
		for i in history_seconds:
			var v = ds.values[i]
			var x = x0 + w * (1.0 - i / float(history_seconds - 1))
			var y = y0 + h * (1.0 - v / max_val)
			points.append(Vector2(x, y))
		if points.size() > 1:
			draw_polyline(points, ds.color, 2.0)

	var total_width := 0.0
	var label_widths : Array = []
	for ds in data_series:
		var size = ThemeDB.fallback_font.get_string_size(ds.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		label_widths.append(size.x)
		total_width += size.x
	total_width += (data_series.size() - 1) * 10
	var start_x = x0 + (w - total_width) / 2.0
	var legend_y = y0 + h + 14
	var current_x = start_x
	for i in data_series.size():
		var ds = data_series[i]
		draw_string(ThemeDB.fallback_font, Vector2(current_x, legend_y), ds.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ds.color)
		current_x += label_widths[i] + 10

func _format_value(value : float, d := 1) -> String:
	match display_mode:
		0:
			return _format_bytes(value, d) + "/s"
		1:
			return "%.*f ms" % [d, value]
		_:
			return "%.*f" % [d, value]

func _format_bytes(b : float, d := 1) -> String:
	if b <= 0: return "0 B"
	var u = ["B","KB","MB","GB"]
	var i = 0
	var v = abs(b)
	while v >= 1000.0 and i < 3:
		v /= 1000.0
		i += 1
	return "%.*f %s" % [d, v, u[i]]
