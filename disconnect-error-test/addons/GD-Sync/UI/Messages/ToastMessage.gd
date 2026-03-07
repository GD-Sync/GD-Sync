@tool
extends Control
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

var slide_tween : Tween = null
var main_tween : Tween = null
var is_hovered : bool = false
var can_pause : bool = false

func set_message(message : String, destroy : bool = true, duration : float = 5.0) -> void:
	var scale : float = size.y/1080.0
	$Anchor.scale = Vector2.ONE*scale
	
	var label : Control = $Anchor/Label
	label.text = message
	label.visible = true
	
	var original_position : Vector2 = label.position
	var offscreen_position : Vector2 = original_position + Vector2(1000, 0)
	label.position = offscreen_position
	
	main_tween = create_tween()
	main_tween.set_ease(Tween.EASE_OUT)
	main_tween.set_trans(Tween.TRANS_CUBIC)
	main_tween.tween_property(label, "position", original_position, 0.5)
	main_tween.tween_callback(func():
		can_pause = true
		if is_hovered: main_tween.pause())
	
	if destroy:
		main_tween.tween_interval(duration)
		main_tween.tween_callback(func(): can_pause = false)
		
		main_tween.set_ease(Tween.EASE_IN)
		main_tween.tween_property(label, "position", offscreen_position, 0.5)
		
		await main_tween.finished
		queue_free()

func update_position(target_height : float) -> void:
	var target_y : float = -target_height
	
	if slide_tween:
		slide_tween.kill()
	
	slide_tween = create_tween()
	slide_tween.set_ease(Tween.EASE_OUT)
	slide_tween.set_trans(Tween.TRANS_CUBIC)
	slide_tween.tween_property(self, "position:y", target_y, 0.3)

func get_height() -> float:
	var scale : float = size.y/1080.0
	return ($Anchor/Label.size.y + 20)*scale

func _on_label_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

func _on_label_mouse_entered() -> void:
	is_hovered = true
	if main_tween and main_tween.is_running() and can_pause:
		main_tween.pause()

func _on_label_mouse_exited() -> void:
	is_hovered = false
	if main_tween and main_tween.is_valid() and can_pause:
		main_tween.play()
