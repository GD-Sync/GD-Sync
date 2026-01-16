@tool
@icon("res://addons/GD-Sync/UI/Icons/SynchronizedRigidBody3D.png")
extends RigidBody2D
class_name SynchronizedRigidBody2D

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

## How many times per second the body should be synchronized.
@export var refresh_rate : int = 30

func apply_central_impulse_synced(impulse : Vector2 = Vector2.ZERO) -> void:
	super.apply_central_impulse(impulse)
	await get_tree().physics_frame
	if !GDSync.is_gdsync_owner(self):
		GDSync.set_gdsync_owner(self, GDSync.get_client_id())

func apply_central_force_synced(force : Vector2) -> void:
	super.apply_central_force(force)
	await get_tree().physics_frame
	if !GDSync.is_gdsync_owner(self):
		GDSync.set_gdsync_owner(self, GDSync.get_client_id())

func apply_impulse_synced(impulse: Vector2, position: Vector2 = Vector2(0, 0)) -> void:
	super.apply_impulse(impulse, position)
	await get_tree().physics_frame
	if !GDSync.is_gdsync_owner(self):
		GDSync.set_gdsync_owner(self, GDSync.get_client_id())

func apply_force_synced(force: Vector2, position: Vector2 = Vector2(0, 0)) -> void:
	super.apply_force(force, position)
	await get_tree().physics_frame
	if !GDSync.is_gdsync_owner(self):
		GDSync.set_gdsync_owner(self, GDSync.get_client_id())

func apply_torque_synced(torque: float) -> void:
	super.apply_torque(torque)
	await get_tree().physics_frame
	if !GDSync.is_gdsync_owner(self):
		GDSync.set_gdsync_owner(self, GDSync.get_client_id())

func apply_torque_impulse_synced(impulse: float) -> void:
	super.apply_torque_impulse(impulse)
	await get_tree().physics_frame
	if !GDSync.is_gdsync_owner(self):
		GDSync.set_gdsync_owner(self, GDSync.get_client_id())





#Private functions ----------------------------------------------------------------------

var GDSync

var _cooldown : float = 0.0
var _current_cooldown : float = 0.0
var _current_fixed_cooldown : float = 0.0
var _should_broadcast : bool = false
var _last_owner : int = -1

var _pending_sync : bool = true
var _force_sync : bool = false
var _pending_correction : bool = false

var _remote_position : Vector2
var _remote_rotation : float
var _remote_linear_velocity : Vector2
var _remote_angular_velocity : float

var _disable_correction_counter : int = 0

var _last_sync_position : Vector2 = Vector2.ZERO
var _last_sync_rotation : float = 0.0
var _last_sync_linear_velocity : Vector2 = Vector2.ZERO
var _last_sync_angular_velocity : float = 0.0

const _FIXED_COOLDOWN : float = 10.0
const _SYNC_LINEAR_VELOCITY_THRESHOLD : float = 0.1
const _SYNC_ANGULAR_VELOCITY_THRESHOLD : float = 0.05
const _SYNC_ROTATION_THRESHOLD : float = 0.01
const _SYNC_POSITION_THRESHOLD : float = 0.01
const _CORRECTION_ROTATION_THRESHOLD : float = 0.03
const _CORRECTION_LINEAR_VELOCITY_THRESHOLD : float = 0.1
const _CORRECTION_ANGULAR_VELOCITY_THRESHOLD : float = 0.05
const _CORRECTION_POSITION_THRESHOLD : float = 0.01

func _ready() -> void:
	if !Engine.is_editor_hint():
		GDSync = get_node("/root/GDSync")
		
		_cooldown = 1.0/refresh_rate
		_last_owner = GDSync.get_gdsync_owner(self)
		can_sleep = false
		
		GDSync.expose_func(_sync_received)
		
		GDSync.host_changed.connect(_host_changed)
		GDSync.client_joined.connect(_client_joined)
		GDSync.connect_gdsync_owner_changed(self, _owner_changed)
		
		_update_sync_mode()
		_current_fixed_cooldown = 2.0

func _physics_process(delta: float) -> void:
	if _should_broadcast:
		if _may_synchronize(delta):
			var current_rot : float = global_transform.get_rotation()
			var rot_diff : float = current_rot - _last_sync_rotation
			if (
				_force_sync or
				abs((global_transform.origin - _last_sync_position).length_squared()) > _SYNC_POSITION_THRESHOLD or
				abs((linear_velocity - _last_sync_linear_velocity).length_squared()) > _SYNC_LINEAR_VELOCITY_THRESHOLD or
				abs(angular_velocity - _last_sync_angular_velocity) > _SYNC_ANGULAR_VELOCITY_THRESHOLD or
				abs(rot_diff) > _SYNC_ROTATION_THRESHOLD
				):
				_last_sync_linear_velocity = linear_velocity
				_last_sync_angular_velocity = angular_velocity
				_last_sync_position = global_transform.origin
				_last_sync_rotation = current_rot
				_pending_sync = true
				_force_sync = false
	else:
		_remote_position += _remote_linear_velocity * delta
		_remote_rotation += _remote_angular_velocity * delta

func _may_synchronize(delta : float) -> bool:
	_current_cooldown -= delta
	if _current_cooldown <= 0:
		_current_cooldown += _cooldown
		return true
	
	_current_fixed_cooldown -= delta
	if _current_fixed_cooldown <= 0.0:
		_current_fixed_cooldown += _FIXED_COOLDOWN
		_force_sync = true
		return true
	return false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _should_broadcast:
		if _pending_correction:
			_pending_correction = false
			state.linear_velocity = _remote_linear_velocity
			state.angular_velocity = _remote_angular_velocity
			state.transform = Transform2D(_remote_rotation, _remote_position)
		
		if _pending_sync:
			_pending_sync = false
			GDSync.call_func(_sync_received, 
				[GDSync.get_multiplayer_time(),
				state.linear_velocity,
				state.angular_velocity,
				state.transform.origin,
				state.transform.get_rotation()]
			)
			_sync_received(GDSync.get_multiplayer_time(),
				state.linear_velocity,
				state.angular_velocity,
				state.transform.origin,
				state.transform.get_rotation())
	else:
		var rot_diff : float = state.transform.get_rotation() - _remote_rotation
		if (
			_disable_correction_counter == 0 and (
			abs((state.linear_velocity - _remote_linear_velocity).length_squared()) > _CORRECTION_LINEAR_VELOCITY_THRESHOLD or
			abs(state.angular_velocity - _remote_angular_velocity) > _CORRECTION_ANGULAR_VELOCITY_THRESHOLD or
			abs((state.transform.origin - _remote_position).length_squared()) > _CORRECTION_POSITION_THRESHOLD or
			abs(rot_diff) > _CORRECTION_ROTATION_THRESHOLD
			)):
			state.linear_velocity = _remote_linear_velocity
			state.angular_velocity = _remote_angular_velocity
			state.transform = Transform2D(
					lerp_angle(state.transform.get_rotation(), _remote_rotation, 0.3),
					lerp(state.transform.origin, _remote_position, 0.3))

func _sync_received(time : float, lv : Vector2, av : float, pos : Vector2, rotation : float) -> void:
	var delta : float = min(GDSync.get_multiplayer_time() - time, 0.3)
	_remote_linear_velocity = lv
	_remote_angular_velocity = av
	_remote_position = pos + _remote_linear_velocity * delta
	_remote_rotation = rotation + _remote_angular_velocity * delta
	_last_sync_linear_velocity = _remote_linear_velocity
	_last_sync_angular_velocity = _remote_angular_velocity
	_last_sync_position = pos
	_last_sync_rotation = rotation
	sleeping = false

func _owner_changed(owner) -> void:
	if owner >= 0: _last_owner = owner
	_update_sync_mode()

func _client_joined(client_id : int) -> void:
	if _should_broadcast:
		_pending_sync = true

func _host_changed(is_host : bool, new_host_id : int) -> void:
	_update_sync_mode()

func _update_sync_mode() -> void:
	if Engine.is_editor_hint() || GDSync == null: return
	var is_host : bool = GDSync.is_host()
	var is_owner : bool = GDSync.is_gdsync_owner(self)
	var valid_owner : bool = GDSync.lobby_get_all_clients().has(_last_owner)
	_should_broadcast = (is_host and !valid_owner) || (valid_owner and _last_owner == GDSync.get_client_id())

func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	
	warnings.append("The SynchronizedRigidBody2D Node is experimental. Please report any issues on GitHub.")
	
	return warnings
