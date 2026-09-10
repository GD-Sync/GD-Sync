@tool
@icon("res://addons/GD-Sync/UI/Icons/InterestViewer.png")
extends Node
class_name InterestViewer

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

## Reports where one player is in the world so the host can run distance checks.
## [br][br]Add this to every player alongside an [InterestObject]. It only provides the
## player's viewing position. Range is controlled entirely by each [InterestObject]'s
## [member InterestObject.visibility_radius]. Enemies, projectiles, and other entities
## do not need an InterestViewer. They only need an [InterestObject].

## The Node whose position marks where this player is in the world.
## [br][br]Leave this empty to use this node's parent. It must be a [Node2D] or [Node3D].
## Only the position is read here, the node itself is never moved or synchronized.
@export var target : NodePath
## How many times per second this player's position is sent to the host.
## [br][br]The host uses this to decide which objects are in range. Higher values make
## objects appear and disappear more smoothly as the player moves, at a small bandwidth cost.
## This has nothing to do with how often your actual game state is synchronized.
@export_range(1.0, 30.0, 1.0, "or_greater") var update_rate : float = 5.0
## Which categories of objects this player is allowed to receive.
## [br][br]An [InterestObject] reaches this player only if they share at least one enabled layer.
## Use layers to group things like world objects, indoor areas, teams, or spectator-only content.
## Leave every layer enabled if you don't need this kind of separation.
@export_flags_3d_physics var interest_layers : int = 1

var GDSync
var _cooldown : float = 0.0
var _force_report : bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		update_configuration_warnings()
		return
	
	GDSync = get_node("/root/GDSync")
	add_to_group("_gdsync_interest")
	GDSync.host_changed.connect(_host_changed)
	GDSync.connect_gdsync_owner_changed(self, _owner_changed)
	_force_interest_report()

func _exit_tree() -> void:
	if Engine.is_editor_hint() or GDSync == null:
		return
	var owner_id : int = GDSync.get_gdsync_owner(self)
	if owner_id >= 0:
		GDSync._interest_manager.unregister_viewer(str(get_path()), owner_id)

func _process(delta : float) -> void:
	if !GDSync.is_active() or !_is_local_viewer():
		return
	
	_cooldown -= delta
	if !_force_report and _cooldown > 0.0:
		return
	
	_force_report = false
	_cooldown = 1.0 / maxf(update_rate, 1.0)
	var target_node := _get_target()
	if target_node == null:
		return
	
	var viewer_dimension := _get_dimension(target_node)
	if viewer_dimension == 0:
		return
	
	GDSync._interest_manager.report_viewer(
		str(get_path()),
		GDSync.get_client_id(),
		_get_position(target_node),
		viewer_dimension,
		interest_layers
	)

func _force_interest_report() -> void:
	_force_report = true
	_cooldown = 0.0

func _is_local_viewer() -> bool:
	var owner_id : int = GDSync.get_gdsync_owner(self)
	return owner_id >= 0 and owner_id == GDSync.get_client_id()

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
	_force_interest_report()

func _get_configuration_warnings() -> PackedStringArray:
	var target_node := _get_target()
	if target_node == null:
		return ["Target Node was not found."]
	if !(target_node is Node2D) and !(target_node is Node3D):
		return ["Target must be a Node2D or Node3D."]
	return []
