@icon("res://addons/GD-Sync/UI/Icons/SynchronizedAudioStreamPlayer.png")
extends AudioStreamPlayer
class_name SynchronizedAudioStreamPlayer

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

func play_synced(from_position : float = 0.0) -> void:
	GDSync.sync_var(self, "volume_db")
	GDSync.sync_var(self, "pitch_scale")
	GDSync.call_func_all(_play_remote, [from_position])

func stop_synced() -> void:
	GDSync.call_func_all(_stop_remote)

#Private functions ----------------------------------------------------------------------

var GDSync

func _ready() -> void:
	GDSync = get_node("/root/GDSync")
	
	GDSync.expose_var(self, "volume_db")
	GDSync.expose_var(self, "pitch_scale")
	
	GDSync.expose_func(_play_remote)
	GDSync.expose_func(_stop_remote)

func _play_remote(from_position : float) -> void:
	play(from_position)

func _stop_remote() -> void:
	stop()
