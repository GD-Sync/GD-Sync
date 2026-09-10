extends Node

# Copyright (c) 2023-present GD-Sync.
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

const DEFAULT_CELL_SIZE : float = 128.0

var GDSync

var _viewers : Dictionary = {}
var _objects : Dictionary = {}
var _object_grid : Dictionary = {}
var _viewer_memberships : Dictionary = {}
var _recipient_cache : Dictionary = {}
var _ambiguous_object_branches : Dictionary = {}

func _ready() -> void:
	name = "InterestManager"
	GDSync.expose_func(_receive_viewer_update)
	GDSync.expose_func(_remove_viewer)
	GDSync.expose_func(_receive_object_update)
	GDSync.expose_func(_remove_object)
	GDSync.expose_func(_set_object_recipients_remote)
	GDSync.expose_func(_apply_object_recipient_delta_remote)
	GDSync.client_joined.connect(_client_joined)
	GDSync.client_left.connect(_client_left)
	GDSync.host_changed.connect(_host_changed)

func clear() -> void:
	_viewers.clear()
	_objects.clear()
	_object_grid.clear()
	_viewer_memberships.clear()
	_recipient_cache.clear()
	_ambiguous_object_branches.clear()

func call_function(callable : Callable, parameters : Array, reliable : bool) -> void:
	var object : Object = callable.get_object()
	var interest_object : Node = _find_interest_object(object) if object is Node else null
	if interest_object == null:
		GDSync._request_processor.create_function_call_request(callable, parameters, -1, reliable)
		return
	
	for client_id in interest_object._get_gdsync_interest_object_recipients():
		if client_id == GDSync.get_client_id():
			continue
		GDSync._request_processor.create_function_call_request(callable, parameters, client_id, reliable)

func sync_variable(object : Object, variable_name : String, reliable : bool) -> void:
	var interest_object : Node = _find_interest_object(object) if object is Node else null
	if interest_object == null:
		GDSync._request_processor.create_set_var_request(object, variable_name, -1, reliable)
		return
	
	for client_id in interest_object._get_gdsync_interest_object_recipients():
		if client_id == GDSync.get_client_id():
			continue
		GDSync._request_processor.create_set_var_request(object, variable_name, client_id, reliable)

func get_relevant_clients(object : Object, include_self : bool = false) -> Array:
	var clients : Array
	var interest_object : Node = _find_interest_object(object) if object is Node else null
	if interest_object == null:
		clients = GDSync.lobby_get_all_clients().duplicate()
	else:
		clients = interest_object._get_gdsync_interest_object_recipients().duplicate()
	if !include_self:
		clients.erase(GDSync.get_client_id())
	return clients

func has_interest_object(context : Node) -> bool:
	return _find_interest_object(context) != null

func get_interest_object(context : Node) -> Node:
	return _find_interest_object(context)

func apply_cached_recipients(interest_object : Node) -> void:
	var object_path := str(interest_object.get_path())
	if _recipient_cache.has(object_path):
		interest_object._set_gdsync_interest_object_recipients(_recipient_cache[object_path])

func report_viewer(
		viewer_path : String,
		client_id : int,
		position : Vector3,
		dimension : int,
		layers : int
	) -> void:
	if GDSync.is_host():
		_receive_viewer_update(viewer_path, client_id, position, dimension, layers)
	else:
		GDSync.call_func_on_unreliable(
			GDSync.get_host(),
			_receive_viewer_update,
			viewer_path,
			client_id,
			position,
			dimension,
			layers
		)

func unregister_viewer(viewer_path : String, client_id : int) -> void:
	if !GDSync.is_active():
		return
	if GDSync.is_host():
		_remove_viewer(viewer_path, client_id)
	else:
		GDSync.call_func_on(GDSync.get_host(), _remove_viewer, viewer_path, client_id)

func report_object(
		object_path : String,
		authority_id : int,
		position : Vector3,
		dimension : int,
		visibility_radius : float,
		exit_margin : float,
		layers : int,
		host_receives_state : bool
	) -> void:
	if GDSync.is_host():
		_receive_object_update(
			object_path,
			authority_id,
			position,
			dimension,
			visibility_radius,
			exit_margin,
			layers,
			host_receives_state
		)
	else:
		GDSync.call_func_on(
			GDSync.get_host(),
			_receive_object_update,
			object_path,
			authority_id,
			position,
			dimension,
			visibility_radius,
			exit_margin,
			layers,
			host_receives_state
		)

func unregister_object(object_path : String, authority_id : int) -> void:
	if !GDSync.is_active():
		return
	if GDSync.is_host():
		_remove_object(object_path, authority_id)
	else:
		GDSync.call_func_on(GDSync.get_host(), _remove_object, object_path, authority_id)

func _receive_viewer_update(
		viewer_path : String,
		client_id : int,
		position : Vector3,
		dimension : int,
		layers : int
	) -> void:
	if !GDSync.is_host():
		return
	
	var viewer_key := _viewer_key(viewer_path, client_id)
	_viewers[viewer_key] = {
		"client_id": client_id,
		"position": position,
		"dimension": dimension,
		"layers": layers,
	}
	_update_viewer_memberships(viewer_key)

func _remove_viewer(viewer_path : String, client_id : int) -> void:
	if !GDSync.is_host():
		return
	
	var viewer_key := _viewer_key(viewer_path, client_id)
	var memberships : Dictionary = _viewer_memberships.get(viewer_key, {})
	_viewers.erase(viewer_key)
	_viewer_memberships.erase(viewer_key)
	for object_path in memberships:
		_refresh_object_recipients(object_path)

func _receive_object_update(
		object_path : String,
		authority_id : int,
		position : Vector3,
		dimension : int,
		visibility_radius : float,
		exit_margin : float,
		layers : int,
		host_receives_state : bool
	) -> void:
	if !GDSync.is_host():
		return
	
	if _objects.has(object_path):
		_remove_object_from_grid(object_path)
	
	var previous_recipients : Array = _objects.get(object_path, {}).get("recipients", [])
	_objects[object_path] = {
		"authority_id": authority_id,
		"position": position,
		"dimension": dimension,
		"visibility_radius": maxf(visibility_radius, 0.0),
		"exit_margin": maxf(exit_margin, 0.0),
		"layers": layers,
		"host_receives_state": host_receives_state,
		"recipients": previous_recipients,
		"cells": [],
	}
	_add_object_to_grid(object_path)
	
	for viewer_key in _viewers:
		_update_membership(viewer_key, object_path, false)
	_refresh_object_recipients(object_path)

func _remove_object(object_path : String, authority_id : int) -> void:
	if !GDSync.is_host() or !_objects.has(object_path):
		return
	if _objects[object_path]["authority_id"] != authority_id:
		return
	
	var previous : Array = _objects[object_path]["recipients"]
	if !previous.is_empty():
		_apply_object_recipient_delta_remote(object_path, [], previous)
		for client_id in GDSync.lobby_get_all_clients():
			if client_id != GDSync.get_client_id():
				GDSync.call_func_on(
					client_id,
					_apply_object_recipient_delta_remote,
					object_path,
					[],
					previous
				)
	_remove_object_from_grid(object_path)
	_objects.erase(object_path)
	for memberships in _viewer_memberships.values():
		memberships.erase(object_path)

func _update_viewer_memberships(viewer_key : String) -> void:
	var viewer : Dictionary = _viewers[viewer_key]
	var candidates : Dictionary = _viewer_memberships.get(viewer_key, {}).duplicate()
	var cell_key := _cell_key(viewer["position"], viewer["dimension"])
	for object_path in _object_grid.get(cell_key, {}):
		candidates[object_path] = true
	
	for object_path in candidates:
		_update_membership(viewer_key, object_path)

func _update_membership(viewer_key : String, object_path : String, publish : bool = true) -> void:
	if !_viewers.has(viewer_key):
		return
	
	var memberships : Dictionary = _viewer_memberships.get_or_add(viewer_key, {})
	var was_relevant : bool = memberships.has(object_path)
	if !_objects.has(object_path):
		memberships.erase(object_path)
		return
	
	var viewer : Dictionary = _viewers[viewer_key]
	var interest_object : Dictionary = _objects[object_path]
	var relevant := false
	if (
		viewer["dimension"] == interest_object["dimension"]
		and (viewer["layers"] & interest_object["layers"]) != 0
	):
		var distance_squared := _distance_squared(
			viewer["position"],
			interest_object["position"],
			interest_object["dimension"]
		)
		var threshold : float = interest_object["visibility_radius"]
		if was_relevant:
			threshold += interest_object["exit_margin"]
		relevant = distance_squared <= threshold * threshold
	
	if relevant == was_relevant:
		return
	if relevant:
		memberships[object_path] = true
	else:
		memberships.erase(object_path)
	if publish:
		_refresh_object_recipients(object_path)

func _refresh_object_recipients(object_path : String) -> void:
	if !_objects.has(object_path):
		return
	
	var recipients : Dictionary = {}
	for viewer_key in _viewer_memberships:
		if _viewer_memberships[viewer_key].has(object_path) and _viewers.has(viewer_key):
			recipients[_viewers[viewer_key]["client_id"]] = true
	
	var interest_object : Dictionary = _objects[object_path]
	if interest_object["host_receives_state"] and GDSync.get_host() >= 0:
		recipients[GDSync.get_host()] = true
	
	var recipient_list : Array[int] = []
	for client_id in recipients:
		recipient_list.append(client_id)
	recipient_list.sort()
	
	if interest_object["recipients"] == recipient_list:
		return
	var previous : Array = interest_object["recipients"]
	var entered : Array = []
	var exited : Array = []
	for client_id in recipient_list:
		if !previous.has(client_id):
			entered.append(client_id)
	for client_id in previous:
		if !recipient_list.has(client_id):
			exited.append(client_id)
	interest_object["recipients"] = recipient_list
	
	_apply_object_recipient_delta_remote(object_path, entered, exited)
	for client_id in GDSync.lobby_get_all_clients():
		if client_id != GDSync.get_client_id():
			GDSync.call_func_on(
				client_id,
				_apply_object_recipient_delta_remote,
				object_path,
				entered,
				exited
			)

func _set_object_recipients_remote(object_path : String, recipients : Array) -> void:
	var updated : Array[int] = []
	for client_id in recipients:
		updated.append(int(client_id))
	_recipient_cache[object_path] = updated
	var interest_object := get_node_or_null(object_path)
	if (
		interest_object != null
		and interest_object.has_method("_set_gdsync_interest_object_recipients")
	):
		interest_object._set_gdsync_interest_object_recipients(updated)

func _apply_object_recipient_delta_remote(object_path : String, entered : Array, exited : Array) -> void:
	var updated : Array = _recipient_cache.get(object_path, []).duplicate()
	for client_id in exited:
		updated.erase(int(client_id))
	for client_id in entered:
		if !updated.has(int(client_id)):
			updated.append(int(client_id))
	_recipient_cache[object_path] = updated
	var interest_object := get_node_or_null(object_path)
	if (
		interest_object != null
		and interest_object.has_method("_set_gdsync_interest_object_recipients")
	):
		interest_object._set_gdsync_interest_object_recipients(updated)

func _add_object_to_grid(object_path : String) -> void:
	var interest_object : Dictionary = _objects[object_path]
	var radius : float = interest_object["visibility_radius"] + interest_object["exit_margin"]
	var min_cell := _cell_coordinates(interest_object["position"] - Vector3.ONE * radius)
	var max_cell := _cell_coordinates(interest_object["position"] + Vector3.ONE * radius)
	if interest_object["dimension"] == 2:
		min_cell.z = 0
		max_cell.z = 0
	
	var cells : Array = []
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				var key := "%s:%s:%s:%s" % [interest_object["dimension"], x, y, z]
				var bucket : Dictionary = _object_grid.get_or_add(key, {})
				bucket[object_path] = true
				cells.append(key)
	interest_object["cells"] = cells

func _remove_object_from_grid(object_path : String) -> void:
	for key in _objects[object_path].get("cells", []):
		if !_object_grid.has(key):
			continue
		_object_grid[key].erase(object_path)
		if _object_grid[key].is_empty():
			_object_grid.erase(key)

func _find_interest_object(context : Node) -> Node:
	var current := context
	while current != null:
		if current.has_method("_get_gdsync_interest_object_recipients"):
			return current if current._is_gdsync_interest_object_enabled() else null
		var sibling_objects : Array[Node] = []
		for child in current.get_children():
			if child.has_method("_get_gdsync_interest_object_recipients"):
				sibling_objects.append(child)
		if !sibling_objects.is_empty():
			if sibling_objects.size() > 1:
				var branch_id := current.get_instance_id()
				if !_ambiguous_object_branches.has(branch_id):
					_ambiguous_object_branches[branch_id] = true
					push_error(
						(
							"GD-Sync found multiple sibling InterestObjects under %s. "
							+ "The first sibling is used; an entity should have exactly one."
						) % current.get_path()
					)
			var interest_object := sibling_objects[0]
			return interest_object if interest_object._is_gdsync_interest_object_enabled() else null
		current = current.get_parent()
	return null

func _viewer_key(viewer_path : String, client_id : int) -> String:
	return "%s:%s" % [client_id, viewer_path]

func _cell_coordinates(position : Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / DEFAULT_CELL_SIZE),
		floori(position.y / DEFAULT_CELL_SIZE),
		floori(position.z / DEFAULT_CELL_SIZE)
	)

func _cell_key(position : Vector3, dimension : int) -> String:
	var cell := _cell_coordinates(position)
	if dimension == 2:
		cell.z = 0
	return "%s:%s:%s:%s" % [dimension, cell.x, cell.y, cell.z]

func _distance_squared(a : Vector3, b : Vector3, dimension : int) -> float:
	if dimension == 2:
		return Vector2(a.x, a.y).distance_squared_to(Vector2(b.x, b.y))
	return a.distance_squared_to(b)

func _client_left(client_id : int) -> void:
	if !GDSync.is_host():
		return
	for viewer_key in _viewers.keys():
		if _viewers[viewer_key]["client_id"] == client_id:
			var viewer_path : String = viewer_key.trim_prefix("%s:" % client_id)
			_remove_viewer(viewer_path, client_id)

func _client_joined(client_id : int) -> void:
	if !GDSync.is_host() or client_id == GDSync.get_client_id():
		return
	await get_tree().create_timer(0.5).timeout
	for object_path in _objects:
		GDSync.call_func_on(
			client_id,
			_set_object_recipients_remote,
			object_path,
			_objects[object_path]["recipients"]
		)

func _host_changed(is_host : bool, _new_host_id : int) -> void:
	clear()
	if is_host:
		get_tree().call_group("_gdsync_interest", "_force_interest_report")
