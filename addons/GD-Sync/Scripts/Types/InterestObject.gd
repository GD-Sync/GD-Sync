@tool
@icon("res://addons/GD-Sync/UI/Icons/InterestObject.png")
extends Node
class_name InterestObject

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

## Makes a synchronized entity send its state only to nearby players instead of
## to everyone. This is the main tool for scaling large worlds without wasting bandwidth.
## [br][br]Add one InterestObject to every entity you want filtered. That includes players, enemies,
## projectiles, vehicles, and so on. Players also need an [InterestViewer] so the host
## knows where they are for distance checks. Spawning is never affected.
## [NodeInstantiator] always reaches everyone.

signal client_entered(client_id : int)
signal client_exited(client_id : int)

## Turns range-based filtering on or off for this entity.
## [br][br]When off, "relevant" calls behave like normal GD-Sync calls and reach every player.
## Turning this off never affects spawning.
@export var enabled : bool = true :
	set(value):
		enabled = value
		_force_interest_report()
## The Node whose position is used as the center of this object.
## [br][br]Leave this empty to use this node's parent. It must be a [Node2D] or [Node3D].
## Every synchronizer inside this entity shares this one InterestObject.
@export var target : NodePath :
	set(value):
		target = value
		_force_interest_report()
## How far away a player can be and still receive this object's state, in world units (pixels in 2D, meters in 3D).
## [br][br]The host compares this radius against each player's [InterestViewer] position.
## Use a larger value for big or important objects, and a smaller one for minor props.
@export_range(0.0, 1000000.0, 0.1, "or_greater", "suffix:m") var visibility_radius : float = 100.0 :
	set(value):
		visibility_radius = value
		_force_interest_report()
## Extra distance a player can drift past the radius before this object stops sending to them.
## [br][br]This stops the object from rapidly starting and stopping updates when a player lingers
## right at the edge of [member visibility_radius]. Players still have to come within the normal
## radius to start receiving; they only stop once they move beyond the radius plus this margin.
@export_range(0.0, 1000000.0, 0.1, "or_greater", "suffix:m") var exit_margin : float = 10.0 :
	set(value):
		exit_margin = value
		_force_interest_report()
## Which categories this object belongs to.
## [br][br]A player receives this object only if their [member InterestViewer.interest_layers]
## shares at least one enabled layer. Use layers to separate things like world objects,
## indoor areas, teams, or spectator-only content.
@export_flags_3d_physics var interest_layers : int = 1 :
	set(value):
		interest_layers = value
		_force_interest_report()
## How many times per second this object rechecks its position to update who is in range.
## [br][br]Higher values keep the list of nearby players more up to date as the object moves,
## at a small bandwidth cost. This is ignored when [member is_static] is enabled.
@export_range(1.0, 30.0, 1.0, "or_greater") var update_rate : float = 5.0
## Keeps the host receiving this object's state even when the host is out of range.
## [br][br]Enable this when the host runs authoritative logic such as physics, validation, or
## anti-cheat and needs every object's state at all times. Disable it when the host is just
## another player that doesn't need distant objects. Position reports still reach the host either way.
@export var host_receives_state : bool = true :
	set(value):
		host_receives_state = value
		_force_interest_report()
## Marks this object as never moving, so it stops re-reporting its position after the first setup.
## [br][br]Ideal for buildings, pickups, and other fixed props; players moving in and out of range
## are still handled correctly. Leave this off for anything that can move, such as players,
## enemies, vehicles, or projectiles.
@export var is_static : bool = false :
	set(value):
		is_static = value
		_force_interest_report()
## Hides this entity's parent on your client when you are out of range.
## [br][br]Works when the parent is a [Node2D], [Node3D], or other [CanvasItem].
## Does nothing on nodes that cannot be hidden. Your own owned entities are never hidden.
@export var hide_parent_out_of_range : bool = false :
	set(value):
		hide_parent_out_of_range = value
		notify_property_list_changed()
		_update_parent_visibility()
## How long to wait before showing the parent again after you come back in range.
## [br][br]Only used when [member hide_parent_out_of_range] is enabled. This gives synchronized
## state time to catch up so the object does not flash at its old position for a frame.
var show_parent_delay : float = 0.1 :
	set(value):
		show_parent_delay = value

var GDSync
var _recipients : Array[int] = []
var _cooldown : float = 0.0
var _force_report : bool = true
var _last_position : Vector3 = Vector3.INF
var _last_authority : int = -1
var _last_settings_hash : int = 0
var _hid_parent : bool = false
var _show_parent_token : int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		update_configuration_warnings()
		return
	
	GDSync = get_node("/root/GDSync")
	add_to_group("_gdsync_interest")
	GDSync.host_changed.connect(_host_changed)
	GDSync.connect_gdsync_owner_changed(self, _owner_changed)
	GDSync._interest_manager.apply_cached_recipients(self)
	_force_interest_report()
	_update_parent_visibility()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_cancel_scheduled_show()
	_show_parent_now()
	if GDSync == null or _last_authority < 0:
		return
	GDSync._interest_manager.unregister_object(str(get_path()), _last_authority)


func _process(delta : float) -> void:
	if !GDSync.is_active():
		return
	if is_static and !_force_report:
		return
	
	var authority_id := _get_authority()
	if !enabled:
		if _last_authority == GDSync.get_client_id():
			GDSync._interest_manager.unregister_object(str(get_path()), _last_authority)
		_last_authority = -1
		_recipients.clear()
		_update_parent_visibility()
		return
	if authority_id != GDSync.get_client_id():
		return
	
	_cooldown -= delta
	if !_force_report and _cooldown > 0.0:
		return
	_cooldown = 1.0 / maxf(update_rate, 1.0)
	
	var target_node := _get_target()
	if target_node == null:
		return
	var object_dimension := _get_dimension(target_node)
	if object_dimension == 0:
		return
	var current_position := _get_position(target_node)
	var settings_hash := hash([
		object_dimension,
		visibility_radius,
		exit_margin,
		interest_layers,
		host_receives_state,
	])
	if (
		!_force_report
		and current_position.is_equal_approx(_last_position)
		and authority_id == _last_authority
		and settings_hash == _last_settings_hash
	):
		return
	
	_force_report = false
	_last_position = current_position
	_last_authority = authority_id
	_last_settings_hash = settings_hash
	GDSync._interest_manager.report_object(
		str(get_path()),
		authority_id,
		current_position,
		object_dimension,
		visibility_radius,
		exit_margin,
		interest_layers,
		host_receives_state
	)


func _is_gdsync_interest_object_enabled() -> bool:
	return enabled and GDSync != null and GDSync.is_active()


func _get_gdsync_interest_object_recipients() -> Array[int]:
	return _recipients


func _set_gdsync_interest_object_recipients(recipients : Array) -> void:
	var updated : Array[int] = []
	for client_id in recipients:
		updated.append(int(client_id))
	
	for client_id in updated:
		if !_recipients.has(client_id):
			client_entered.emit(client_id)
			if client_id == GDSync.get_client_id():
				_notify_synchronized_nodes("_interest_object_local_entered", client_id)
			elif _last_authority == GDSync.get_client_id():
				_notify_synchronized_nodes("_interest_object_client_entered", client_id)
	for client_id in _recipients:
		if !updated.has(client_id):
			client_exited.emit(client_id)
			if client_id != GDSync.get_client_id() and _last_authority == GDSync.get_client_id():
				_notify_synchronized_nodes("_interest_object_client_exited", client_id)
	_recipients = updated
	_update_parent_visibility()


func _update_parent_visibility() -> void:
	if Engine.is_editor_hint() or GDSync == null or !GDSync.is_active():
		return
	
	if !hide_parent_out_of_range or !enabled:
		_restore_parent_visibility()
		return
	
	var parent_node := get_parent()
	if parent_node == null or !_can_hide_node(parent_node):
		return
	
	if _get_authority() == GDSync.get_client_id():
		_restore_parent_visibility()
		return
	
	var in_range := _recipients.has(GDSync.get_client_id())
	if in_range:
		if _hid_parent:
			_schedule_show_parent()
	else:
		_cancel_scheduled_show()
		_hide_parent_now()


func _hide_parent_now() -> void:
	var parent_node := get_parent()
	if parent_node == null or !_can_hide_node(parent_node):
		return
	if !_hid_parent:
		_set_node_visible(parent_node, false)
		_hid_parent = true


func _schedule_show_parent() -> void:
	_show_parent_token += 1
	var token := _show_parent_token
	var delay := maxf(show_parent_delay, 0.0)
	if delay <= 0.0:
		_show_parent_now()
		return
	_await_show_parent(token, delay)


func _await_show_parent(token : int, delay : float) -> void:
	await get_tree().create_timer(delay).timeout
	if token != _show_parent_token:
		return
	if GDSync == null or !GDSync.is_active() or !hide_parent_out_of_range or !enabled:
		return
	if _get_authority() == GDSync.get_client_id():
		return
	if !_recipients.has(GDSync.get_client_id()):
		return
	_show_parent_now()


func _cancel_scheduled_show() -> void:
	_show_parent_token += 1


func _show_parent_now() -> void:
	if !_hid_parent:
		return
	var parent_node := get_parent()
	if parent_node != null and _can_hide_node(parent_node):
		_set_node_visible(parent_node, true)
	_hid_parent = false


func _restore_parent_visibility() -> void:
	_cancel_scheduled_show()
	_show_parent_now()


func _can_hide_node(node : Node) -> bool:
	return node is CanvasItem or node is Node3D


func _set_node_visible(node : Node, visible : bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = visible
	elif node is Node3D:
		(node as Node3D).visible = visible


func _force_interest_report() -> void:
	_force_report = true
	_cooldown = 0.0


func _notify_synchronized_nodes(method : StringName, client_id : int) -> void:
	var branch := get_parent()
	var candidates : Array[Node] = [branch]
	candidates.append_array(branch.find_children("*", "", true, false))
	for candidate in candidates:
		if (
			candidate.has_method(method)
			and GDSync._interest_manager.get_interest_object(candidate) == self
		):
			candidate.call(method, client_id)


func _get_authority() -> int:
	var owner_id : int = GDSync.get_gdsync_owner(self)
	if owner_id >= 0 and GDSync.lobby_get_all_clients().has(owner_id):
		return owner_id
	return GDSync.get_host()


func _get_target() -> Node:
	if target.is_empty():
		return get_parent()
	return get_node_or_null(target)


func _get_dimension(target_node : Node) -> int:
	if target_node is Node2D:
		return 2
	if target_node is Node3D:
		return 3
	return 0


func _get_position(target_node : Node) -> Vector3:
	if target_node is Node2D:
		var position_2d : Vector2 = target_node.global_position
		return Vector3(position_2d.x, position_2d.y, 0.0)
	if target_node is Node3D:
		return target_node.global_position
	return Vector3.ZERO


func _owner_changed(_owner_id : int) -> void:
	_force_interest_report()


func _host_changed(_is_host : bool, _host_id : int) -> void:
	_recipients.clear()
	_force_interest_report()
	_update_parent_visibility()


func _get_property_list() -> Array[Dictionary]:
	var properties : Array[Dictionary] = []
	if !hide_parent_out_of_range:
		return properties
	
	properties.append({
		"name": "show_parent_delay",
		"type": TYPE_FLOAT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,2,0.01,or_greater,suffix:s",
	})
	return properties


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	var target_node := _get_target()
	if target_node == null:
		warnings.append("Target Node was not found.")
	elif !(target_node is Node2D) and !(target_node is Node3D):
		warnings.append("Target must be a Node2D or Node3D.")
	
	if get_parent() != null:
		var sibling_count := 0
		for sibling in get_parent().get_children():
			if sibling is InterestObject:
				sibling_count += 1
		if sibling_count > 1:
			warnings.append("An entity may have only one sibling InterestObject.")
		if hide_parent_out_of_range and !_can_hide_node(get_parent()):
			warnings.append("hide_parent_out_of_range is enabled but the parent cannot be hidden (must be Node2D, Node3D, or CanvasItem).")
	return warnings
