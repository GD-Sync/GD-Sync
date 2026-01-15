@tool
@icon("res://addons/GD-Sync/UI/Icons/SynchronizedAnimationTree.png")
extends AnimationTree
class_name SynchronizedAnimationTree

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

enum BROADCAST_MODE {
	## Broadcast when you are the host of this lobby.
	WHEN_HOST,
	## Broadcast when you are the not host of this lobby.
	WHEN_CLIENT,
	## Broadcast when you are the owner of this Node or any parent Node.
	WHEN_OWNER,
	## Broadcast on the last valid owner this Node had. If the last valid owner leaves or if no owner was ever assigned, it broadcasts on the host.
	WHEN_HOST_OR_LAST_VALID_OWNER,
	## Broadcast when you are the host of this lobby and this Node has no owner. 
	## If it does have an owner, only the owner broadcasts. 
	## [br]Useful for scenario's like picking up and holding objects, where you want the owner to broadcast 
	## when the item is picked up. When it is dropped and the owner is removed, the lobby 
	## host goes back to broadcasting it.
	WHEN_HOST_AND_NO_OWNER_OR_OWNER,
	## Always broadcast. Never recommended.
	ALWAYS,
	## Never broadcast.
	NEVER,
}

static var _VARIABLE_INPUTS : PackedStringArray = [
	"/add_amount",
	"/blend_amount",
	"/blend_position"
]

static var _INSTANT_INPUTS : PackedStringArray = [
	"/active",
	"/scale"
]

## Decides when to broadcast animation changes to other clients.
@export var broadcast: BROADCAST_MODE : set = _set_broadcast
## How many times per second the animation tree should check for changes.
@export var refresh_rate : int = 15

var _current_variable_inputs : Dictionary = {}
var _current_instant_inputs : Dictionary = {}
var _state_machines : Dictionary = {}
var _state_machine_inputs : Dictionary = {}

var _cooldown : float = 0.0
var _current_cooldown : float = 0.0
var _should_broadcast : bool = false
var last_owner : int = -1

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	
	_cooldown = 1.0/refresh_rate
	GDSync.connect_gdsync_owner_changed(self, _owner_changed)
	GDSync.host_changed.connect(_host_changed)
	GDSync.expose_func(_travel_remote)
	GDSync.expose_func(set)
	
	var property_list : Array = get_property_list()
	
	for property in property_list:
		var name : String = property["name"]
		if "parameters/" in name:
			
			for variable_input in _VARIABLE_INPUTS:
				if variable_input in name:
					_current_variable_inputs[name] = get(name)
					GDSync.expose_var(self, name)
					break
			
			for instant_input in _INSTANT_INPUTS:
				if instant_input in name:
					_current_instant_inputs[name] = get(name)
					GDSync.expose_var(self, name)
					break
			
			if "/playback" in name:
				var state_machine : AnimationNodeStateMachinePlayback = get(name)
				_state_machines[name] = state_machine
				_state_machine_inputs[state_machine] = state_machine.get_current_node()
	
	_update_sync_mode()
	
	if !_should_broadcast:
		_update_inputs(_current_variable_inputs, true)
		_update_inputs(_current_instant_inputs, true)
		_update_state_machines(true)

func _process(delta: float) -> void:
	if !_should_broadcast:
		return
	
	_update_inputs(_current_instant_inputs)
	
	_current_cooldown -= delta
	if _current_cooldown <= 0:
		_current_cooldown += _cooldown
		
		_update_inputs(_current_variable_inputs)
		_update_state_machines()

func _update_inputs(inputs : Dictionary, forced : bool = false) -> void:
	for input_name in inputs:
		var old_value = inputs[input_name]
		var new_value = get(input_name)
		
		if forced or old_value != new_value:
			inputs[input_name] = new_value
			
			if "/active" in input_name:
				var request : String = input_name.replace("/active", "/request")
				GDSync.call_func(set, [request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE if new_value else AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT])
			else:
				GDSync.sync_var(self, input_name)

func _update_state_machines(forced : bool = false) -> void:
	for state_machine_path in _state_machines:
		var state_machine : AnimationNodeStateMachinePlayback = _state_machines[state_machine_path]
		var old_node : String = _state_machine_inputs[state_machine]
		var new_node : String = state_machine.get_current_node()
		
		if forced or old_node != new_node:
			_state_machine_inputs[state_machine] = new_node
			GDSync.call_func(_travel_remote, [state_machine_path, new_node])

func _travel_remote(state_machine_path : String, node_name : String) -> void:
	var state_machine : AnimationNodeStateMachinePlayback = _state_machines[state_machine_path]
	state_machine.travel(node_name)

func _host_changed(is_host : bool, new_host_id : int) -> void:
	_update_sync_mode()

func _owner_changed(owner) -> void:
	if owner >= 0: last_owner = owner
	_update_sync_mode()

func _set_broadcast(mode : int) -> void:
	broadcast = mode
	_update_sync_mode()

func _update_sync_mode() -> void:
	if Engine.is_editor_hint() || GDSync == null: return
	var is_host : bool = GDSync.is_host()
	var is_owner : bool = GDSync.is_gdsync_owner(self)
	match (broadcast):
		BROADCAST_MODE.WHEN_HOST:
			_should_broadcast = is_host
		BROADCAST_MODE.WHEN_CLIENT:
			_should_broadcast = !is_host
		BROADCAST_MODE.WHEN_OWNER:
			_should_broadcast = is_owner
		BROADCAST_MODE.WHEN_HOST_OR_LAST_VALID_OWNER:
			var valid_owner : bool = GDSync.lobby_get_all_clients().has(last_owner)
			_should_broadcast = (is_host and !valid_owner) || (valid_owner and last_owner == GDSync.get_client_id())
		BROADCAST_MODE.WHEN_HOST_AND_NO_OWNER_OR_OWNER:
			_should_broadcast = (is_host and GDSync.get_gdsync_owner(self) < 0) || is_owner
		BROADCAST_MODE.ALWAYS:
			_should_broadcast = true
		BROADCAST_MODE.NEVER:
			_should_broadcast = false
