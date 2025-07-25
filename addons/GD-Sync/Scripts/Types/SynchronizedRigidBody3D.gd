@tool
@icon("res://addons/GD-Sync/UI/Icons/SynchronizedRigidBody3D.png")
extends RigidBody3D
class_name SynchronizedRigidBody3D

#Copyright (c) 2025 GD-Sync.
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

## Decides when to broadcast the properties to other clients.
@export var broadcast: BROADCAST_MODE : set = _set_broadcast
## How many times per second the properties should be synchronized.
@export var refresh_rate : int = 30

func apply_central_impulse(impulse : Vector3) -> void:
	super.apply_central_impulse(impulse)
	await get_tree().physics_frame
	_push_correction()

func apply_central_force(force : Vector3) -> void:
	super.apply_central_force(force)
	await get_tree().physics_frame
	_push_correction()

func apply_impulse(impulse: Vector3, position: Vector3 = Vector3(0, 0, 0)) -> void:
	super.apply_impulse(impulse, position)
	await get_tree().physics_frame
	_push_correction()

func apply_force(force: Vector3, position: Vector3 = Vector3(0, 0, 0)) -> void:
	super.apply_force(force, position)
	await get_tree().physics_frame
	_push_correction()

func apply_torque(torque: Vector3) -> void:
	super.apply_torque(torque)
	await get_tree().physics_frame
	_push_correction()

func apply_torque_impulse(impulse: Vector3) -> void:
	super.apply_torque_impulse(impulse)
	await get_tree().physics_frame
	_push_correction()





#Private functions ----------------------------------------------------------------------

enum BROADCAST_MODE {
	## Broadcast when you are the host of this lobby.
	WHEN_HOST,
	## Broadcast on the last valid owner this Node had. If the last valid owner leaves or if no owner was ever assigned, it broadcasts on the host.
	WHEN_HOST_OR_LAST_VALID_OWNER,
	## Broadcast when you are the host of this lobby and this Node has no owner. If it does have an owner, only the owner broadcasts.
	## [br]Useful for scenario's like picking up and holding objects, where you want the owner to broadcast 
	## when the item is picked up. When it is dropped and the owner is removed, the lobby 
	## host goes back to broadcasting it.
	WHEN_HOST_AND_NO_OWNER_OR_OWNER,
	## Never broadcast.
	NEVER,
}

var GDSync

var _cooldown : float = 0.0
var _current_cooldown : float = 0.0
var _should_broadcast : bool = false
var _last_owner : int = -1

var _pending_sync : bool = true
var _pending_correction : bool = false

var _remote_position : Vector3
var _remote_euler : Vector3
var _remote_linear_velocity : Vector3
var _remote_angular_velocity : Vector3

var _disable_correction_counter : int = 0

func _ready() -> void:
	if !Engine.is_editor_hint():
		GDSync = get_node("/root/GDSync")
		
		_cooldown = 1.0/refresh_rate
		_last_owner = GDSync.get_gdsync_owner(self)
		
		GDSync.expose_func(_sync_received)
		GDSync.expose_func(_client_correct)
		
		GDSync.host_changed.connect(_host_changed)
		GDSync.connect_gdsync_owner_changed(self, _owner_changed)
		
		_update_sync_mode()

func _physics_process(delta: float) -> void:
	if _should_broadcast:
		if _may_synchronize(delta):
			_pending_sync = true
	
	_remote_position += _remote_linear_velocity * delta
	_remote_euler += _remote_angular_velocity*delta

func _may_synchronize(delta : float) -> bool:
	_current_cooldown -= delta
	if _current_cooldown <= 0:
		_current_cooldown += _cooldown
		return true
	return false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _should_broadcast:
		if _pending_correction:
			_pending_correction = false
			state.linear_velocity = _remote_linear_velocity
			state.angular_velocity = _remote_angular_velocity
			state.transform.origin = _remote_position
			state.transform.basis = Basis(Quaternion.from_euler(_remote_euler))
		
		if _pending_sync:
			_pending_sync = false
			GDSync.call_func(_sync_received, 
				[GDSync.get_multiplayer_time(),
				state.linear_velocity,
				state.angular_velocity,
				state.transform.origin,
				state.transform.basis.get_euler()]
			)
			_sync_received(GDSync.get_multiplayer_time(),
				state.linear_velocity,
				state.angular_velocity,
				state.transform.origin,
				state.transform.basis.get_euler())
	else:
		if (
			_disable_correction_counter == 0 and (
			abs((state.linear_velocity-_remote_linear_velocity).length_squared()) > 0.5 or
			abs((state.angular_velocity-_remote_angular_velocity).length_squared()) > 0.3 or
			abs((state.transform.origin-_remote_position).length_squared()) > 0.01
			)):
			#print("Correct ", name)
			#print(abs((state.linear_velocity-_remote_linear_velocity).length_squared()))
			#print(abs((state.angular_velocity-_remote_angular_velocity).length_squared()))
			#print(abs((state.transform.origin-_remote_position).length_squared()))
			#print(state.linear_velocity, " - ", _remote_linear_velocity)
			state.linear_velocity = _remote_linear_velocity
			state.angular_velocity = _remote_angular_velocity
			state.transform.origin = lerp(state.transform.origin, _remote_position, 0.1)
			state.transform.basis = state.transform.basis.slerp(Basis(Quaternion.from_euler(_remote_euler)), 0.1)
			
		#_check_velocity.call_deferred(state.linear_velocity)

func _push_correction() -> void:
	if _should_broadcast:
		return
	
	_disable_correction()
	GDSync.call_func(_client_correct, [
		GDSync.get_multiplayer_time(),
		linear_velocity,
		angular_velocity,
		position,
		rotation
		])

func _disable_correction() -> void:
	_disable_correction_counter += 1
	await get_tree().create_timer(0.2).timeout
	_disable_correction_counter -= 1

func _client_correct(time : float, lv : Vector3, av : Vector3, pos : Vector3, euler : Vector3) -> void:
	if _should_broadcast:
		var delta : float = min(GDSync.get_multiplayer_time()-time, 0.3)
		_remote_linear_velocity = lv
		_remote_angular_velocity = av
		_remote_position = pos + _remote_linear_velocity*delta
		_remote_euler = euler + _remote_angular_velocity*delta
		_pending_correction = true
		sleeping = false

func _sync_received(time : float, lv : Vector3, av : Vector3, pos : Vector3, euler : Vector3) -> void:
	var delta : float = min(GDSync.get_multiplayer_time()-time, 0.0)
	_remote_linear_velocity = lv
	_remote_angular_velocity = av
	_remote_position = pos + _remote_linear_velocity*delta
	_remote_euler = euler + _remote_angular_velocity*delta
	sleeping = false

func _set_broadcast(mode : int) -> void:
	broadcast = mode
	_update_sync_mode()

func _owner_changed(owner) -> void:
	if owner >= 0: _last_owner = owner
	_update_sync_mode()

func _host_changed(is_host : bool, new_host_id : int) -> void:
	_update_sync_mode()

func _update_sync_mode() -> void:
	if Engine.is_editor_hint() || GDSync == null: return
	var is_host : bool = GDSync.is_host()
	var is_owner : bool = GDSync.is_gdsync_owner(self)
	match (broadcast):
		BROADCAST_MODE.WHEN_HOST:
			_should_broadcast = is_host
		BROADCAST_MODE.WHEN_HOST_OR_LAST_VALID_OWNER:
			var valid_owner : bool = GDSync.lobby_get_all_clients().has(_last_owner)
			_should_broadcast = (is_host and !valid_owner) || (valid_owner and _last_owner == GDSync.get_client_id())
		BROADCAST_MODE.WHEN_HOST_AND_NO_OWNER_OR_OWNER:
			_should_broadcast = (is_host and GDSync.get_gdsync_owner(self) < 0) || is_owner
		BROADCAST_MODE.NEVER:
			_should_broadcast = false

func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	
	warnings.append("The SynchronizedRigidBody3D Node is experimental. Please report any issues on GitHub.")
	
	return warnings
