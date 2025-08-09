extends Node

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

func _ready() -> void:
	name = "Logger"
	GDSync = get_node("/root/GDSync")
	
	logging_enabled = OS.is_debug_build()
	set_process(logging_enabled)
	
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
