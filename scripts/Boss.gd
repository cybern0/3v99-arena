extends CharacterBody3D

var ray_cast: RayCast3D = null

func _ready() -> void:
	ray_cast = find_child("RayCast3D", true, false)
	# ray_cast. body entered if existe, connect to a func that take if is attacking and body is in group player then body.get_parent as the player.has method  take_damage
