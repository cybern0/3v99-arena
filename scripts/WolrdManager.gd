extends Node

var characters := Node;
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var chars = get_tree().get_nodes_in_group("Characters")
	characters = [c as CharacterBody3D for c in chars]


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	for c in characters:
		c.velocity.y -= 9.8 * delta
		c.move_and_slide()
