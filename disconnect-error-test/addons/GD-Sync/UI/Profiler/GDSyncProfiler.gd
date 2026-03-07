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

signal stats_updated(client_id : int, stats : Dictionary)
signal custom_data_updated(data : Dictionary)
signal message_details_updated(details : Dictionary)
signal client_joined(client_id : int)
signal client_left(client_id : int)
signal ping_measured(client_id : int, ping : float, perceived_ping : float)
signal start_monitoring_connections
signal stop_monitoring_connections
signal profiler_cleared()
signal profiler_started()
signal profiler_stopped()

@export var start_button : Button = null : set = _set_start_button
@export var stop_button : Button = null : set = _set_stop_button

var auto_start : bool = false

var valid_session : bool = false
var global_stats : Dictionary = {
	"up":0,"down":0,"pkts_up":0,"pkts_down":0,
	"up_sec":0.0,"down_sec":0.0,"pkts_up_sec":0.0,"pkts_down_sec":0.0,
	"avg_msg_up":0.0,"avg_msg_down":0.0,"avg_msg_up_sec":0.0,"avg_msg_down_sec":0.0,
	"last":0.0,"hist":[],
	"total_sec": 0.0
}
var client_stats : Dictionary = {}
var custom_data : Dictionary = {}
var message_details_up : Dictionary = {}
var message_details_down : Dictionary = {}
var last_details_emit : float = 0.0
const DETAILS_EMIT_INTERVAL : float = 5.0

func _ready() -> void:
	stop()
	clear()
	invalidate_session()
	_update_button_states()

func _on_auto_start_toggled(toggled_on: bool) -> void:
	auto_start = true

func _set_start_button(btn) -> void:
	start_button = btn
	_update_button_states()

func _set_stop_button(btn) -> void:
	stop_button = btn
	_update_button_states()

func _update_button_states() -> void:
	if start_button:
		start_button.disabled = is_processing() or !valid_session
	if stop_button:
		stop_button.disabled = !is_processing() or !valid_session

func start() -> void:
	if is_processing(): return
	set_process(true)
	profiler_started.emit()
	_update_button_states()

func stop() -> void:
	if not is_processing(): return
	set_process(false)
	profiler_stopped.emit()
	_update_button_states()

func clear() -> void:
	global_stats = {
		"up":0,"down":0,"pkts_up":0,"pkts_down":0,
		"up_sec":0.0,"down_sec":0.0,"pkts_up_sec":0.0,"pkts_down_sec":0.0,
		"avg_msg_up":0.0,"avg_msg_down":0.0,"avg_msg_up_sec":0.0,"avg_msg_down_sec":0.0,
		"last":0.0,"hist":[],
		"total_sec": 0.0
	}
	client_stats.clear()
	custom_data.clear()
	message_details_up.clear()
	message_details_down.clear()
	last_details_emit = 0.0
	profiler_cleared.emit()
	custom_data_updated.emit(custom_data)
	message_details_updated.emit({"up": {}, "down": {}})

func validate_session() -> void:
	valid_session = true
	_update_button_states()

func invalidate_session() -> void:
	valid_session = false
	_update_button_states()

func game_started() -> void:
	if auto_start:
		start()

func register_transfer_usage(client_id : int, origin : Dictionary, byte_count : int, upload : bool, details : String) -> void:
	if client_id <= 0: return
	var dir = "up" if upload else "down"
	var pkt_key = "pkts_" + dir
	global_stats[dir] += byte_count
	global_stats[pkt_key] += 1
	var c = client_stats.get(client_id, {
		"up":0,"down":0,"pkts_up":0,"pkts_down":0,
		"up_sec":0.0,"down_sec":0.0,"pkts_up_sec":0.0,"pkts_down_sec":0.0,
		"avg_msg_up":0.0,"avg_msg_down":0.0,"avg_msg_up_sec":0.0,"avg_msg_down_sec":0.0,
		"last":0.0,"hist":[],
		"total_sec": 0.0
	})
	c[dir] += byte_count
	c[pkt_key] += 1
	client_stats[client_id] = c
	
	var key = "%s-%s-%s" % [origin.get("type", ""), origin.get("object", ""), origin.get("target", "")]
	if key == "--":
		return
	
	var details_dict = message_details_up if upload else message_details_down
	var entry = details_dict.get(key, {
		"type": origin.get("type", ""),
		"object": origin.get("object", ""),
		"target": origin.get("target", ""),
		"count": 0,
		"total_bytes": 0,
		"avg_bytes": 0.0,
		"percent": 0.0,
		"last_details": []
	})
	entry.count += 1
	entry.total_bytes += byte_count
	entry.avg_bytes = entry.total_bytes / entry.count
	
	entry.last_details.append(details)
	if entry.last_details.size() > 3:
		entry.last_details.pop_front()
	
	details_dict[key] = entry

func register_custom_data(data : Dictionary) -> void:
	for key in data.keys():
		custom_data[key] = data[key]
	custom_data_updated.emit(custom_data)

func _process(_delta):
	var now = Time.get_ticks_msec() / 1000.0
	if now - global_stats.last >= 1.0:
		_update_rates(global_stats, now)
		_update_rates_all_clients(now)
		_emit_all()
		global_stats.last = now

	if now - last_details_emit >= DETAILS_EMIT_INTERVAL:
		_update_message_percentages()
		var combined = {
			"up": message_details_up.duplicate(),
			"down": message_details_down.duplicate()
		}
		message_details_updated.emit(combined)
		last_details_emit = now

func _update_message_percentages() -> void:
	_update_percentages_for(message_details_up)
	_update_percentages_for(message_details_down)

func _update_percentages_for(dict : Dictionary) -> void:
	var total_bytes : int = 0
	for key in dict.keys():
		total_bytes += dict[key].total_bytes
	if total_bytes == 0:
		for key in dict.keys():
			dict[key].percent = 0.0
	else:
		for key in dict.keys():
			var entry = dict[key]
			entry.percent = (entry.total_bytes as float / total_bytes) * 100.0
			dict[key] = entry

func _update_rates(stats : Dictionary, now : float) -> void:
	var h = stats.hist
	h.append({
		"t":now,
		"up":stats.up,"down":stats.down,
		"pkts_up":stats.pkts_up,"pkts_down":stats.pkts_down
	})
	while h.size() > 0 and now - h[0].t > 5.0:
		h.pop_front()
	if h.size() < 2:
		stats.up_sec = 0.0
		stats.down_sec = 0.0
		stats.pkts_up_sec = 0.0
		stats.pkts_down_sec = 0.0
		stats.avg_msg_up = 0.0
		stats.avg_msg_down = 0.0
		stats.avg_msg_up_sec = 0.0
		stats.avg_msg_down_sec = 0.0
		stats.total_sec = 0.0
		return
	var first = h[0]
	var last = h[-1]
	var dt = last.t - first.t
	if dt <= 0.0:
		stats.up_sec = 0.0
		stats.down_sec = 0.0
		stats.pkts_up_sec = 0.0
		stats.pkts_down_sec = 0.0
		stats.avg_msg_up_sec = 0.0
		stats.avg_msg_down_sec = 0.0
		stats.total_sec = 0.0
		return
	var delta_up = last.up - first.up
	var delta_down = last.down - first.down
	var delta_pkts_up = last.pkts_up - first.pkts_up
	var delta_pkts_down = last.pkts_down - first.pkts_down
	stats.up_sec = delta_up / dt
	stats.down_sec = delta_down / dt
	stats.pkts_up_sec = delta_pkts_up / dt
	stats.pkts_down_sec = delta_pkts_down / dt
	stats.avg_msg_up_sec = delta_up / delta_pkts_up if delta_pkts_up > 0 else 0.0
	stats.avg_msg_down_sec = delta_down / delta_pkts_down if delta_pkts_down > 0 else 0.0
	var total_pkts_up = stats.pkts_up
	var total_pkts_down = stats.pkts_down
	stats.avg_msg_up = stats.up / total_pkts_up if total_pkts_up > 0 else 0.0
	stats.avg_msg_down = stats.down / total_pkts_down if total_pkts_down > 0 else 0.0
	stats.total_sec = stats.up_sec + stats.down_sec

func _update_rates_all_clients(now : float) -> void:
	for cid in client_stats.keys():
		_update_rates(client_stats[cid], now)

func _emit_all() -> void:
	stats_updated.emit(-1, global_stats)
	for cid in client_stats.keys():
		stats_updated.emit(cid, client_stats[cid])
