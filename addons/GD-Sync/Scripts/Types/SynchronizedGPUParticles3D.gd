@icon("res://addons/GD-Sync/UI/Icons/SynchronizedGPUParticles.png")
extends GPUParticles3D
class_name SynchronizedGPUParticles3D

#Copyright (c) 2023-present GD-Sync.
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

## Restarts this particle system on all relevant clients with a shared random seed.
## Useful for one-shot effects such as explosions, impacts, and bursts.
func restart_synced() -> void:
	var particle_seed : int = _generate_seed()
	_sync_particle_properties()
	GDSync.call_func_all_relevant(_restart_remote, particle_seed)

## Starts emitting on all relevant clients with a shared random seed so the
## particle look matches across clients.
func emit_synced() -> void:
	var particle_seed : int = _generate_seed()
	_sync_particle_properties()
	GDSync.call_func_all_relevant(_emit_remote, particle_seed)

## Stops emitting on all relevant clients.
func stop_synced() -> void:
	GDSync.call_func_all_relevant(_stop_remote)




#Private functions ----------------------------------------------------------------------

const _SYNCED_PROPERTIES : PackedStringArray = [
	"amount",
	"lifetime",
	"one_shot",
	"preprocess",
	"speed_scale",
	"explosiveness",
	"randomness",
	"fixed_fps",
	"fract_delta",
	"interpolate",
	"local_coords",
]

var GDSync
var _last_seed : int = 0

func _ready() -> void:
	use_fixed_seed = true
	GDSync = get_node("/root/GDSync")
	
	for property_name in _SYNCED_PROPERTIES:
		GDSync.expose_var(self, property_name)
	
	GDSync.expose_func(_restart_remote)
	GDSync.expose_func(_emit_remote)
	GDSync.expose_func(_stop_remote)

func _generate_seed() -> int:
	_last_seed = randi()
	return _last_seed

func _apply_seed(particle_seed : int) -> void:
	use_fixed_seed = true
	seed = particle_seed
	_last_seed = particle_seed

func _sync_particle_properties() -> void:
	for property_name in _SYNCED_PROPERTIES:
		GDSync.sync_var_relevant(self, property_name)

func _restart_remote(particle_seed : int) -> void:
	_apply_seed(particle_seed)
	restart(true)

func _emit_remote(particle_seed : int) -> void:
	_apply_seed(particle_seed)
	emitting = true
	restart(true)

func _stop_remote() -> void:
	emitting = false

func _interest_object_client_entered(client_id : int) -> void:
	if !emitting:
		return
	for property_name in _SYNCED_PROPERTIES:
		GDSync.sync_var_on(client_id, self, property_name)
	GDSync.call_func_on(client_id, _restart_remote, _last_seed)
