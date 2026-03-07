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

const LOG_PATH : String = "user://GD-Sync/Logs"
var GDSync

var logging_enabled : bool = true
var session_id : String

var logs : PackedStringArray

var original_log_times : Dictionary = {}
var recent_log_times : Dictionary = {}
var recent_log_counts : Dictionary = {}

var log_timer : float = 0.0
var new_logs : bool = false

var use_profiler : bool = false
var monitor_connections : bool = false
var connection_timer : float = 0.0
var profiler_data : Dictionary = {}
var profiler_message_queue : Array = []
var debugger_singleton

func _ready() -> void:
	name = "Logger"
	GDSync = get_node("/root/GDSync")
	
	logging_enabled = OS.is_debug_build()
	set_process(logging_enabled)
	
	if OS.has_feature("editor"):
		debugger_singleton = Engine.get_singleton("EngineDebugger")
		debugger_singleton.register_message_capture("gdsyncprofiler", _capture)
		debugger_singleton.send_message("gdsyncprofiler:gamestart", [])
		
		GDSync.client_joined.connect(func(client_id : int):
			register_profiler_message("clientjoined", [client_id]))
		GDSync.client_left.connect(func(client_id : int):
			register_profiler_message("clientleft", [client_id]))
	
	if !logging_enabled: return
	var time : float = Time.get_unix_time_from_system()
	session_id = str(ceili(time)/86400)+str(ceili(time*1000.0)%86400000)
	
	if !DirAccess.dir_exists_absolute(LOG_PATH):
		DirAccess.make_dir_absolute(LOG_PATH)
	
	var files : PackedStringArray = DirAccess.get_files_at(LOG_PATH)
	if files.size() > 4:
		var file_times : Dictionary = {}
		for file in files:
			file_times[FileAccess.get_modified_time(LOG_PATH+"/"+file)] = file
		
		var keys : Array = file_times.keys()
		keys.sort()
		for i in range(files.size()-4):
			var log_time : int = keys[i]
			DirAccess.remove_absolute(LOG_PATH+"/"+file_times[log_time])

func _process(delta: float) -> void:
	log_timer -= delta
	_process_logs()
	_write_logs()
	_monitor_connections(delta)

func _monitor_connections(delta : float) -> void:
	if !monitor_connections:
		return
	
	connection_timer -= delta
	if connection_timer <= 0.0:
		connection_timer += 1.0
		
		for client_id in GDSync.lobby_get_all_clients():
			_monitor_connection(client_id)

func _monitor_connection(client_id : int) -> void:
	if GDSync.get_client_id() == client_id: return
	
	var ping : float = await GDSync.get_client_ping(client_id)
	var perceived_ping : float = await GDSync.get_client_percieved_ping(client_id)
	register_profiler_message("pingmeasured", [client_id, ping, perceived_ping])

func _process_logs() -> void:
	var current_time : float = Time.get_unix_time_from_system()
	for log in recent_log_times:
		var time : float = recent_log_times[log]
		var count : int = recent_log_counts[log]
		if current_time - time > 1.0 or count >= 100:
			
			var original_time : float = original_log_times[log]
			original_log_times.erase(log)
			recent_log_times.erase(log)
			recent_log_counts.erase(log)
			
			var print_time : String = str(snappedf(fmod(original_time, 1000.0), 0.01)).pad_decimals(2)
			
			new_logs = true
			if count == 1:
				logs.append("["+print_time+"]"+log+"\n")
			else:
				logs.append("["+print_time+"][x"+str(count)+"]"+log+"\n")

func _write_logs() -> void:
	if log_timer > 0.0: return
	log_timer = 1.0
	if !new_logs: return
	new_logs = false
	
	var log_path : String = LOG_PATH+"/GDLog"+session_id+".txt"
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
		if file == null:
			return
	
	file.seek_end()
	for log in logs:
		file.store_string(log)
	logs.clear()
	file.close()

func write_log(log : String, prefix : String = "") -> void:
	if !logging_enabled: return
	
	log = prefix+" "+log
	
	if !original_log_times.has(log): original_log_times[log] = Time.get_unix_time_from_system()
	recent_log_times[log] = Time.get_unix_time_from_system()
	recent_log_counts[log] = recent_log_counts.get(log, 0)+1

func write_error(error : String, prefix : String = "") -> void:
	write_log(error, prefix+"[ERROR]")

func _capture(message : String, data : Array) -> bool:
	if message == "start":
		use_profiler = true
		debugger_singleton.send_message("gdsyncprofiler:setdata", [profiler_data])
		
		for message_data in profiler_message_queue:
			debugger_singleton.send_message("gdsyncprofiler:"+message_data[0], message_data[1])
		profiler_message_queue.clear()
		return true
	if message == "stop":
		use_profiler = false
		return true
	if message == "start_monitoring_connections":
		monitor_connections = true
		return true
	if message == "stop_monitoring_connections":
		monitor_connections = false
		return true
	return false

func register_profiler_data(key : String, value) -> void:
	profiler_data[key] = value
	if !use_profiler: return
	debugger_singleton.send_message("gdsyncprofiler:setdata", [profiler_data])

func register_profiler_message(message : String, values : Array) -> void:
	if !use_profiler:
		profiler_message_queue.append([message, values])
		return
	debugger_singleton.send_message("gdsyncprofiler:"+message, values)

func register_transfer_usage(origin : Dictionary, byte_count : int, upload : bool, details : String) -> void:
	if !use_profiler: return
	debugger_singleton.send_message("gdsyncprofiler:registertransfer", [GDSync.get_client_id(), origin, byte_count, upload, details])
