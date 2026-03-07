@tool
extends Node

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
signal profiler_cleared

@export var profiler : Node = null : set = _set_profiler
@export var button_template : Control = null
@export var latency_graph_template : Control = null
@export var jitter_graph_template : Control = null

var client_data : Dictionary = {}
var client_buttons : Dictionary = {}
var client_latency_graphs : Dictionary = {}
var client_jitter_graphs : Dictionary = {}
var own_id : int = -1
var monitoring : bool = false

func _ready():
	button_template.visible = false
	
	if profiler:
		_connect_signal()

func _set_profiler(v):
	if profiler == v: return
	if profiler:
		_disconnect_signal()
	profiler = v
	if profiler:
		_connect_signal()

func _connect_signal():
	if not profiler: return
	if profiler.has_signal("profiler_started") and not profiler.profiler_started.is_connected(_on_profiler_started):
		profiler.profiler_started.connect(_on_profiler_started)
	if profiler.has_signal("profiler_stopped") and not profiler.profiler_stopped.is_connected(_on_profiler_stopped):
		profiler.profiler_stopped.connect(_on_profiler_stopped)
	if profiler.has_signal("client_joined") and not profiler.client_joined.is_connected(_on_client_joined):
		profiler.client_joined.connect(_on_client_joined)
	if profiler.has_signal("client_left") and not profiler.client_left.is_connected(_on_client_left):
		profiler.client_left.connect(_on_client_left)
	if profiler.has_signal("ping_measured") and not profiler.ping_measured.is_connected(_on_ping_measured):
		profiler.ping_measured.connect(_on_ping_measured)
	if profiler.has_signal("profiler_cleared") and not profiler.profiler_cleared.is_connected(_on_profiler_cleared):
		profiler.profiler_cleared.connect(_on_profiler_cleared)
	if profiler.has_signal("custom_data_updated") and not profiler.custom_data_updated.is_connected(_on_custom_data):
		profiler.custom_data_updated.connect(_on_custom_data)

func _disconnect_signal():
	if not profiler: return
	if profiler.has_signal("profiler_started") and profiler.profiler_started.is_connected(_on_profiler_started):
		profiler.profiler_started.disconnect(_on_profiler_started)
	if profiler.has_signal("profiler_stopped") and profiler.profiler_stopped.is_connected(_on_profiler_stopped):
		profiler.profiler_stopped.disconnect(_on_profiler_stopped)
	if profiler.has_signal("client_joined") and profiler.client_joined.is_connected(_on_client_joined):
		profiler.client_joined.disconnect(_on_client_joined)
	if profiler.has_signal("client_left") and profiler.client_left.is_connected(_on_client_left):
		profiler.client_left.disconnect(_on_client_left)
	if profiler.has_signal("ping_measured") and profiler.ping_measured.is_connected(_on_ping_measured):
		profiler.ping_measured.disconnect(_on_ping_measured)
	if profiler.has_signal("profiler_cleared") and profiler.profiler_cleared.is_connected(_on_profiler_cleared):
		profiler.profiler_cleared.disconnect(_on_profiler_cleared)
	if profiler.has_signal("custom_data_updated") and profiler.custom_data_updated.is_connected(_on_custom_data):
		profiler.custom_data_updated.disconnect(_on_custom_data)

func _on_custom_data(data : Dictionary) -> void:
	if !data.has("client_id"): return
	own_id = data["client_id"]

func _on_monitor_button_toggled(toggled_on: bool) -> void:
	monitoring = toggled_on
	
	if monitoring:
		profiler.start_monitoring_connections.emit()
	else:
		profiler.stop_monitoring_connections.emit()

func _on_profiler_started() -> void:
	if monitoring:
		profiler.start_monitoring_connections.emit()

func _on_profiler_stopped() -> void:
	profiler.stop_monitoring_connections.emit()

func _on_profiler_cleared() -> void:
	client_data.clear()
	
	for button in client_buttons.values():
		button.queue_free()
	
	for graph in client_latency_graphs.values():
		graph.queue_free()
	
	for graph in client_jitter_graphs.values():
		graph.queue_free()
	
	client_buttons.clear()
	client_latency_graphs.clear()
	client_jitter_graphs.clear()
	
	latency_graph_template.visible = true
	jitter_graph_template.visible = true
	
	profiler_cleared.emit()

func _on_client_joined(client_id : int) -> void:
	if client_id == own_id: return
	
	client_data[client_id] = {"latency" : 0.0, "jitter" : 0.0}
	
	var button : Button = button_template.duplicate()
	button_template.get_parent().add_child(button)
	
	button.text = "Client %s" % [client_id]
	button.pressed.connect(_show_client_graph.bind(client_id))
	button.visible = true
	client_buttons[client_id] = button
	
	var latency_graph : Control = latency_graph_template.duplicate()
	latency_graph_template.get_parent().add_child(latency_graph)
	
	latency_graph.visible = true
	latency_graph.client_id = client_id
	latency_graph.data_series[0]["label"] = "Latency to client "+str(client_id)
	latency_graph.data_series[1]["label"] = "Perceived latency to client "+str(client_id)
	client_latency_graphs[client_id] = latency_graph
	
	var jitter_graph : Control = jitter_graph_template.duplicate()
	jitter_graph_template.get_parent().add_child(jitter_graph)
	
	jitter_graph.visible = true
	jitter_graph.client_id = client_id
	jitter_graph.data_series[0]["label"] = "Jitter to client "+str(client_id)
	client_jitter_graphs[client_id] = jitter_graph
	
	if client_data.size() == 1:
		_show_client_graph(client_id)

func _show_client_graph(client_id : int) -> void:
	latency_graph_template.visible = false
	jitter_graph_template.visible = false
	
	for graph in client_latency_graphs.values():
		graph.visible = false
	for graph in client_jitter_graphs.values():
		graph.visible = false
	
	client_latency_graphs[client_id].visible = true
	client_jitter_graphs[client_id].visible = true

func _on_client_left(client_id : int) -> void:
	if client_data.has(client_id):
		client_data.erase(client_id)
	
	if client_buttons.has(client_id):
		client_buttons[client_id].queue_free()
		client_buttons.erase(client_id)
	
	if client_latency_graphs.has(client_id):
		client_latency_graphs[client_id].queue_free()
		client_latency_graphs.erase(client_id)
	
	if client_jitter_graphs.has(client_id):
		client_jitter_graphs[client_id].queue_free()
		client_jitter_graphs.erase(client_id)

func _on_ping_measured(client_id : int, ping : float, perceived_ping : float) -> void:
	if !client_latency_graphs.has(client_id): return
	ping *= 1000.0
	perceived_ping *= 1000.0
	
	ping = max(0, ping)
	perceived_ping = max(0, perceived_ping)
	
	var data : Dictionary = client_data[client_id]
	var last_latency : float = data["latency"]
	var jitter : float = abs(last_latency-ping) if last_latency > 0 else 0.0
	data["latency"] = ping
	data["perceived_latency"] = perceived_ping
	data["jitter"] = jitter
	
	stats_updated.emit(client_id, data)
