class_name Interaction
extends GrabbableNode2D

signal deleted
signal request_deletion
signal mouse_pressed()
signal finger_pressed()

@onready var Ball: AnimatedSprite2D = $Ball
@onready var Dot: AnimatedSprite2D = $Dot
@onready var InfoNumberLabel: Label = $InfoNumberLabel
@export var information_box_offset := Vector2(0, 0)

static var used_information_numbers: Array[int] = []

enum {HIGHLIGHT, NORMAL}
enum Side {Before = -1, After = +1}
const INTERACTION_SIZE_MINIMUM := 3
const INFORMATION_ID_MAXIMUM := 99
const MAXIMUM_DIMENSIONALITY : float = 4

var Diagram: MainDiagram
var Initial: StateLine
var Final: StateLine
var StateManager: Node

var InformationBox := preload("res://Scenes_and_scripts/UI/Info/interaction_information.tscn")
var information_id: int

var has_moved: bool = false
var decor: Decoration.Decor = Decoration.Decor.none: set = _set_decor
var id : int
var connected_lines: Array[ParticleLine] = []
var old_connected_lines: Array[ParticleLine] = []
var connected_particles: Array[ParticleData.Particle] : get = _get_connected_particles
var connected_base_particles: Array[ParticleData.Particle] : get = _get_connected_base_particles
var connected_colour_lines: Array[ParticleLine] : get = _get_connected_colour_lines
var connected_shade_lines: Array[ParticleLine] : get = _get_connected_shade_lines
var degree: int = 0 : get = _get_degree

var information_visible: bool = false
var information_box: InteractionInformation

var valid := true: set = _set_valid
var valid_colourless := true: set = _set_valid_colourless
var hovering := false:
	get:
		return grab_area_hovered
var update_queued := true

func _ready() -> void:
	super._ready()
	
	request_deletion.connect(Diagram.delete_interaction)

	Ball.frame = NORMAL
	
	update_valid_visual()
	
	queue_update()

func init(diagram: MainDiagram) -> void:
	Diagram = diagram
	Initial = diagram.StateLines[StateLine.State.Initial]
	Final = diagram.StateLines[StateLine.State.Final]
	StateManager = diagram.StateManager

func _grab_area_hovered_changed(new_value: bool) -> void:
	grab_area_hovered = new_value
	
	if grabbed:
		return
	
	EventBus.deletable_object_hover_changed.emit(self, grab_area_hovered)
	
	if new_value:
		Ball.frame = HIGHLIGHT
	else:
		Ball.frame = NORMAL

func _set_decor(new_decor: Decoration.Decor) -> void:
	decor = new_decor
	update_valid_visual()

func _set_hovering(new_value: bool) -> void:
	hovering = new_value

func _set_valid(new_valid: bool) -> void:
	valid = new_valid
	update_valid_visual()

func _set_valid_colourless(new_valid_colourless: bool) -> void:
	valid_colourless = new_valid_colourless
	update_valid_visual()

func connect_line(particle_line:ParticleLine) -> void:
	if particle_line in connected_lines:
		return
	
	connected_lines.push_back(particle_line)
	queue_update()

func disconnect_line(particle_line:ParticleLine) -> void:
	connected_lines.erase(particle_line)
	queue_update()

func update_valid_visual() -> void:
	var current_ball_frame: int = Ball.frame
	
	if valid and valid_colourless:
		Ball.animation = Decoration.get_decor_name(decor) + '_valid'
	else:
		Ball.animation = Decoration.get_decor_name(decor) + '_invalid'
	
	Ball.frame = current_ball_frame

func update_dot_visual() -> void:
	if !grabbed:
		if connected_lines.size() >= INTERACTION_SIZE_MINIMUM:
			Dot.visible = true
		else:
			Dot.visible = false
	
	if get_on_state_line() != StateLine.State.None:
		Dot.frame = 1
		Dot.visible = true
		return
	
	if degree == 2:
		Dot.frame = 2
	else:
		Dot.frame = 0

func get_on_state_line() -> StateLine.State:
	if position.x == Initial.position.x and position.x == Final.position.x:
		return StateLine.State.Both
		
	if position.x == Initial.position.x:
		return StateLine.State.Initial
		
	if position.x == Final.position.x:
		return StateLine.State.Final
		
	return StateLine.State.None

func queue_update() -> void:
	update_queued = true

func update() -> void:
	update_dot_visual()
	update_ball_hovering()
	if connected_lines.size() < 2 and information_visible:
		close_information_box()
	
	if information_visible:
		information_box.build_table()
	
	set_shader_parameters()
	
	valid = validate()
	
	if !valid:
		pass

func update_ball_hovering() -> void:
	self.hovering = self.hovering

func has_colour() -> bool:
	for particle_line:ParticleLine in connected_lines:
		if particle_line.has_colour:
			return true
	return false
	
func has_shade() -> bool:
	for particle_line:ParticleLine in connected_lines:
		if particle_line.has_shade:
			return true
	return false

func _get_connected_colour_lines() -> Array[ParticleLine]:
	var connected_coloured_lines: Array[ParticleLine] = []
	for particle_line:ParticleLine in connected_lines:
		if particle_line.has_colour:
			connected_coloured_lines.append(particle_line)
	return connected_coloured_lines

func _get_connected_shade_lines() -> Array[ParticleLine]:
	var connected_shaded_lines: Array[ParticleLine] = []
	for particle_line:ParticleLine in connected_lines:
		if particle_line.has_shade:
			connected_shaded_lines.append(particle_line)
	return connected_shaded_lines

func _get_connected_particles() -> Array[ParticleData.Particle]:
	connected_particles.clear()
	for particle_line:ParticleLine in connected_lines:
		connected_particles.append(particle_line.particle)
	connected_particles.sort()
	return connected_particles

func _get_connected_base_particles() -> Array[ParticleData.Particle]:
	connected_base_particles.clear()
	for particle_line:ParticleLine in connected_lines:
		connected_base_particles.append(particle_line.base_particle)
	connected_base_particles.sort()
	return connected_base_particles

func _get_degree() -> int:
	var connected_count: int = connected_lines.size()
	
	if connected_count < INTERACTION_SIZE_MINIMUM:
		return 0
	elif connected_count == INTERACTION_SIZE_MINIMUM:
		return 1
	
	return 2

func should_request_deletion() -> bool:
	if connected_lines.size() == 0:
		return true
	return false

func move(to_position: Vector2i) -> void:
	has_moved = true
	position = to_position

func has_particle_connected(particle: ParticleData.Particle) -> bool:
	return particle in connected_particles

func has_base_particle_connected(base_particle: ParticleData.Particle) -> bool:
	return base_particle in connected_base_particles

func get_line_particles(particle_lines: Array[ParticleLine]) -> Array[ParticleData.Particle]:
	var particles: Array[ParticleData.Particle] = []
	for particle_line:ParticleLine in particle_lines:
		particles.append(particle_line.particle)
	particles.sort()
	return particles

func validate(particle_lines := connected_lines) -> bool:
	var particles := get_line_particles(particle_lines)

	if particle_lines.size() < 2:
		return true
	
	if !is_dimensionality_valid(particles):
		return false

	if has_neutral_photon(particles):
		return false
	
	if has_colourless_gluon(particles):
		return false
	
	if has_massless_H(particles):
		return false

	if has_shadeless_Z(particles):
		return false
	elif !is_no_H_valid(particles):
		return false
	
	if get_invalid_quantum_numbers(particles, particle_lines).size() > 0:
		return false
	
	return true

func has_weak(particles := connected_particles) -> bool:
	return ParticleData.Particle.W in particles or ParticleData.Particle.anti_W in particles

func get_invalid_quantum_numbers(
	particles := connected_particles,
	particle_lines := connected_lines
) -> Array[ParticleData.QuantumNumber]:
	
	var is_weak: bool = has_weak(particles)
	#var has_W_0: bool = particle_lines.any(
		#func(particle_line: ParticleLine) -> bool:
			#return particle_line.line_vector.x == 0 and particle_line.base_particle == ParticleData.Particle.W
	#)
	var invalid_quantum_numbers: Array[ParticleData.QuantumNumber] = []
	var before_quantum_sum : Array[float] = get_side_quantum_sum(Side.Before, particle_lines)
	var after_quantum_sum : Array[float] = get_side_quantum_sum(Side.After, particle_lines)

	for quantum_number:ParticleData.QuantumNumber in ParticleData.QuantumNumber.values():
		var quantum_number_difference := before_quantum_sum[quantum_number] - after_quantum_sum[quantum_number]
		var quantum_numbers_equal := is_zero_approx(quantum_number_difference)
		
		if quantum_numbers_equal:
			continue

		#if has_W_0 and quantum_number == ParticleData.QuantumNumber.charge and abs(quantum_number_difference) == 1:
			#continue
		
		if is_weak and quantum_number in ParticleData.WEAK_QUANTUM_NUMBERS:
			continue
		
		invalid_quantum_numbers.append(quantum_number)
	
	return invalid_quantum_numbers

func get_unconnected_line_vector(particle_line: ParticleLine) -> Vector2:
	return particle_line.points[particle_line.get_unconnected_point(self)] - positioni()

func get_side_connected_lines(side: Interaction.Side, particle_lines := connected_lines) -> Array[ParticleLine]:
	var side_connected_lines : Array[ParticleLine] = []
	
	for particle_line:ParticleLine in particle_lines:
		var unconnected_point := particle_line.get_unconnected_point(self)
		var unconnected_vector : Vector2 = get_unconnected_line_vector(particle_line)
		if side * unconnected_vector.x > 0:
			side_connected_lines.append(particle_line)
		elif unconnected_vector.x == 0 and is_vertical_line_on_side(unconnected_point, side):
			side_connected_lines.append(particle_line)

	return side_connected_lines

func is_vertical_line_on_side(unconnected_point: ParticleLine.Point, side: Interaction.Side) -> bool:
	if side == Side.Before:
		return unconnected_point == ParticleLine.Point.Start
	
	return unconnected_point == ParticleLine.Point.End

func get_side_quantum_sum(side: Interaction.Side, particle_lines := connected_lines) -> Array[float]:
	var quantum_sum : Array[float] = []
	var side_connected_lines := get_side_connected_lines(side, particle_lines)
	
	for quantum_number:ParticleData.QuantumNumber in ParticleData.QuantumNumber.values():
		var sum: float = 0
		for particle_line:ParticleLine in side_connected_lines:
			#var line_is_W_0: bool = particle_line.line_vector.x == 0 and particle_line.base_particle == ParticleData.Particle.W
			#
			#if line_is_W_0 and quantum_number == ParticleData.QuantumNumber.charge:
				#continue
			#
			sum += ParticleData.quantum_number(particle_line.particle, quantum_number)

		quantum_sum.append(sum)

	return quantum_sum

func get_dimensionality(particles := connected_particles) -> float:
	var dimensionality: float = 0.0
	
	for particle in particles:
		dimensionality += ParticleData.dimensionality(particle)
	
	return dimensionality

func is_dimensionality_valid(particles := connected_particles) -> bool:
	return get_dimensionality(particles) <= MAXIMUM_DIMENSIONALITY

func has_neutral_photon(particles := connected_particles) -> bool:
	if ParticleData.Particle.photon not in particles:
		return false
	
	if particles.size() == 2 and particles.all(
		func(particle:ParticleData.Particle) -> bool:
			return particle == ParticleData.Particle.photon
	):
		return false
	
	var skipped_photon: bool = false
	for particle in particles:
		if !skipped_photon and particle == ParticleData.Particle.photon:
			skipped_photon = true
			continue
	
		if ParticleData.has_charge(particle):
			return false
	
	return true

func has_colourless_gluon(particles := connected_particles) -> bool:
	if ParticleData.Particle.gluon not in particles:
		return false

	return !particles.all(ParticleData.has_colour)

func has_shadeless_Z(particles := connected_particles) -> bool:
	if ParticleData.Particle.Z not in particles:
		return false
	
	if particles.size() == 2 and particles.all(
		func(particle:ParticleData.Particle) -> bool:
			return particle == ParticleData.Particle.Z
	):
		return false
	
	if ParticleData.Particle.H in particles:
		return false
	
	var skipped_Z: bool = false
	for particle in particles:
		if !skipped_Z and particle == ParticleData.Particle.Z:
			skipped_Z = true
			continue
	
		if ParticleData.has_shade(particle):
			return false
	
	return true

func has_massless_H(particles := connected_particles) -> bool:
	if ParticleData.Particle.H not in particles:
		return false
	
	return particles.any(
		func(particle: ParticleData.Particle) -> bool:
			return is_zero_approx(ParticleData.PARTICLE_MASSES[
				ParticleData.base(particle)
			])
	)

func is_no_H_valid(particles := connected_particles) -> bool:
	if ParticleData.Particle.H not in particles:
		return true

	var no_H_lines : Array[ParticleLine] = connected_lines.filter(
		func(particle_line: ParticleLine) -> bool:
			return particle_line.particle != ParticleData.Particle.H
	)
	
	if no_H_lines.size() > 2 or no_H_lines.size() == 1:
		return false		
	
	return validate(no_H_lines)

func positioni() -> Vector2i:
	return position

func is_hovered() -> bool:
	return hovering

func get_new_information_id() -> int:
	for i:int in range(1, INFORMATION_ID_MAXIMUM):
		if !i in used_information_numbers:
			return i
	return -1

func open_information_box() -> void:
	information_id = get_new_information_id()
	used_information_numbers.append(information_id)
	
	information_box = InformationBox.instantiate()
	information_box.ConnectedInteraction = self
	information_box.ID = information_id
	information_box.position = Diagram.position + position + information_box_offset
	EventBus.add_floating_menu.emit(information_box)
	
	InfoNumberLabel.text = str(information_id)
	InfoNumberLabel.show()
	information_visible = true

func close_information_box() -> void:
	used_information_numbers.erase(information_id)
	InfoNumberLabel.hide()
	information_box.queue_free()
	information_visible = false

func _on_mouse_area_button_pressed() -> void:
	if has_moved:
		return
	
	if (
		(StateManager.state == BaseState.State.Idle or
		(StateManager.state == BaseState.State.Drawing and
		!StateManager.states[BaseState.State.Drawing].drawing)) and
		connected_lines.size() >= 2
	):
		if information_visible:
			close_information_box()
			$ButtonSoundComponent.play_button_up()
		else:
			open_information_box()
			$ButtonSoundComponent.play_button_down()

func delete() -> void:
	deleted.emit(self)
	queue_free()

func deconstructor() -> void:
	if information_visible:
		close_information_box()
	Diagram.update_statelines()

func _on_tree_exiting() -> void:
	deconstructor()
	
func drop() -> void:
	super.drop()
	
	update_dot_visual()
	self.hovering = hovering
	Diagram.update_statelines()

func get_interaction_index() -> Array[int]:
	var sorted_connected_base_particles := self.connected_base_particles.duplicate(true)
	
	for i:int in sorted_connected_base_particles.size():
		var particle: ParticleData.Particle = sorted_connected_base_particles[i]
		if ParticleData.is_general(particle):
			sorted_connected_base_particles[i] = ParticleData.convert_particle(particle)
	
	sorted_connected_base_particles.sort()
	
	for i:int in range(ParticleData.INTERACTIONS.size()):
		for j:int in range(ParticleData.INTERACTIONS[i].size()):
			if sorted_connected_base_particles == ParticleData.INTERACTIONS[i][j]:
				return [i, j]
	
	return []

func get_interaction_strength() -> float:
	var interaction_index := get_interaction_index()
	if interaction_index == []:
		return -1
	return ParticleData.INTERACTION_STRENGTHS[interaction_index[0]][interaction_index[1]][0]

func calculate_interaction_strength_alpha(interaction_strength:float = get_interaction_strength()) -> float:
	var minimum_log_strength := log(ParticleData.MINIMUM_INTERACTION_STRENGTH)
	var maximum_log_strength := log(ParticleData.MAXIMUM_INTERACTION_STRENGTH)
	
	if interaction_strength == -1:
		return 1.0
	
	var proportional_strength : float = (
		(log(interaction_strength) - minimum_log_strength) /
		(maximum_log_strength - minimum_log_strength) *
		(1.0 - ParticleData.MINIMUM_INTERACTION_STRENGTH_ALPHA) + ParticleData.MINIMUM_INTERACTION_STRENGTH_ALPHA
	)
	
	return proportional_strength

func set_shader_parameters(alpha: float = 1.0) -> void:
	var interaction_strength_alpha := calculate_interaction_strength_alpha()
	
	alpha *= interaction_strength_alpha
	
	material.set_shader_parameter("interaction_strength_alpha", interaction_strength_alpha)
	
	set_connected_line_shader_parameters(interaction_strength_alpha)

func set_connected_line_shader_parameters(interaction_strength_alpha: float) -> void:
	for particle_line:ParticleLine in connected_lines:
		particle_line.set_point_interaction_strength_alpha(particle_line.get_point_at_position(position), interaction_strength_alpha)

func get_connected_vision_lines(vision: Globals.Vision) -> Array[ParticleLine]:
	match vision:
		Globals.Vision.Colour:
			return self.connected_colour_lines
		Globals.Vision.Shade:
			return self.connected_shade_lines
	
	return []

func get_vision_vectors(vision: Globals.Vision) -> PackedVector2Array:
	var vision_particle_line_vectors: PackedVector2Array = get_connected_vision_lines(vision).map(
		func(vision_line: ParticleLine) -> Vector2:
			return get_unconnected_line_vector(vision_line)
	)
	
	if vision_particle_line_vectors.size() == 1:
		if get_on_state_line() == StateLine.State.None:
			var orthogonal_vector: Vector2 = vision_particle_line_vectors[0].orthogonal().normalized()
			return [orthogonal_vector, -orthogonal_vector]
		
		return [Vector2.UP, Vector2.DOWN]
	
	elif vision_particle_line_vectors.size() == 2:
		var middle_vector: Vector2 = (vision_particle_line_vectors[0] + vision_particle_line_vectors[1]).normalized()
		return [middle_vector, -middle_vector]
	
	var vision_vectors: PackedVector2Array = []
	for i:int in vision_particle_line_vectors.size():
		vision_vectors.push_back(
			(vision_particle_line_vectors[i] + vision_particle_line_vectors[(i+1 % vision_particle_line_vectors.size())]).normalized()
		)
	
	return vision_vectors

func _on_mouse_area_button_button_down() -> void:
	has_moved = false
	
	mouse_pressed.emit(self)
	EventBus.grabbable_object_clicked.emit(self)
	EventBus.deletable_object_clicked.emit(self)

func _on_touch_screen_button_pressed() -> void:
	EventBus.message.emit("interaction input")
	finger_pressed.emit(self)
	EventBus.grabbable_object_clicked.emit(self)
	EventBus.deletable_object_clicked.emit(self)
