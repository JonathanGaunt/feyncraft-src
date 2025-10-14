extends GrabbableControl
class_name InteractionInformation

signal closed_button_pressed

enum Tab {QuantumNumbers, Other}
enum OtherProperties {Degree, Dimensionality, ColourlessGluon, NeutralPhoton, MasslessH, ShadelessZ, NoHInvalid, Colour, InvalidInteraction}

@onready var data_containers : Array[GridContainer] = [
	$"PanelContainer/TabContainer/Quantum Numbers/Quantum Numbers",
	$PanelContainer/TabContainer/Other/Other
]
const NUMBER_OF_TITLE_NODES : int = 4

var ConnectedInteraction: Interaction
var ID: int
var invalid_icon := preload("res://Scenes_and_scripts/UI/Info/invalid.tscn")
var valid_icon := preload("res://Scenes_and_scripts/UI/Info/valid.tscn")

#1 charge, 2 lepton num., 3 e. num, 4 mu num., 5 tau num., 6 quark num., 7 up num., 8 down num., 9 charm num., 10 strange num., 11 top num., 12 bottom num., 13 colour
var property_names := [['charge', 'lepton num.', 'electron num.', 'muon num.', 'tau num.', 'quark num.', 'up num.', 'down num.', 'charm num.', 'strange num.', 'top num.', 'bottom num.', 'bright num.', 'dark num.'],
['degree', 'dimensionality', 'gluon from colourless?', 'photon from neutral?', "Higgs from massless?", "Z from shadeless?", "H-less is particle/0?", 'colour', 'interaction invalid']]

func _ready() -> void:
	super._ready()
	
	closed_button_pressed.connect(ConnectedInteraction.close_information_box)
	
	$PanelContainer/NumberContainer/Number.text = str(ID)
	
	build_table()
	
func build_table() -> void:
	clear_table()
	build_quantum_number_tab()
	build_other_tab()

func get_bool_str(b: bool) -> String:
	return "Yes" if b else "No"

func clear_table() -> void:
	for container in data_containers:
		for i:int in range(container.get_children().size()):
			if i < container.columns:
				continue
			container.get_child(i).queue_free()
	
func build_quantum_number_tab() -> void:
	var relevant_quantum_numbers : Array[ParticleData.QuantumNumber] = get_relevant_quantum_numbers()
	var invalid_quantum_numbers : Array[ParticleData.QuantumNumber] = ConnectedInteraction.get_invalid_quantum_numbers()
	var before_quantum_numbers : Array[float] = ConnectedInteraction.get_side_quantum_sum(Interaction.Side.Before)
	var after_quantum_numbers : Array[float] = ConnectedInteraction.get_side_quantum_sum(Interaction.Side.After)
	
	for quantum_number:ParticleData.QuantumNumber in relevant_quantum_numbers:
		add_label(data_containers[Tab.QuantumNumbers], property_names[Tab.QuantumNumbers][quantum_number])
		add_label(data_containers[Tab.QuantumNumbers], fraction_to_string(before_quantum_numbers[quantum_number]))
		add_label(data_containers[Tab.QuantumNumbers], fraction_to_string(after_quantum_numbers[quantum_number]))
		add_invalid(data_containers[Tab.QuantumNumbers], !quantum_number in invalid_quantum_numbers)

func fraction_to_string(fraction: float) -> String:
	if is_integer(fraction):
		return str(round(fraction))
	
	return str(int(round(fraction*3)))+'/3'

func build_other_tab() -> void:
	var particles := ConnectedInteraction.connected_particles
	
	add_label(data_containers[Tab.Other], property_names[Tab.Other][OtherProperties.Degree])
	add_label(data_containers[Tab.Other], "= "+ str(ConnectedInteraction.degree))
	add_label(data_containers[Tab.Other], '')
	
	add_label(data_containers[Tab.Other], property_names[Tab.Other][OtherProperties.Dimensionality])
	add_label(data_containers[Tab.Other], "= "+ str(ConnectedInteraction.get_dimensionality(particles)) +
		(" ( <= 4 ) " if ConnectedInteraction.is_dimensionality_valid(particles) else ' ( > 4 ) '))
	add_invalid(data_containers[Tab.Other], ConnectedInteraction.is_dimensionality_valid(particles))
	
	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.gluon):
		add_label(data_containers[Tab.Other], property_names[Tab.Other][OtherProperties.ColourlessGluon])
		var colourless_gluon: bool = ConnectedInteraction.has_colourless_gluon(particles) or !ConnectedInteraction.valid_colourless
		add_label(data_containers[Tab.Other], "  %s  "%[get_bool_str(colourless_gluon)])
		add_invalid(data_containers[Tab.Other], !colourless_gluon)
	
	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.photon):
		var neutral_photon: bool = ConnectedInteraction.has_neutral_photon(particles)
		add_label(data_containers[Tab.Other], property_names[Tab.Other][OtherProperties.NeutralPhoton])
		add_label(data_containers[Tab.Other], "  %s  "%[get_bool_str(neutral_photon)])
		add_invalid(data_containers[Tab.Other], !neutral_photon)
		
	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.H):
		var massless_H: bool = ConnectedInteraction.has_massless_H(particles)
		var is_no_H_valid: bool = ConnectedInteraction.is_no_H_valid(particles)
		
		add_label(data_containers[Tab.Other], property_names[Tab.Other][OtherProperties.MasslessH])
		add_label(data_containers[Tab.Other], "  %s  "%[get_bool_str(massless_H)])
		add_invalid(data_containers[Tab.Other], !massless_H)
		
		add_label(data_containers[Tab.Other], property_names[Tab.Other][OtherProperties.NoHInvalid])
		add_label(data_containers[Tab.Other], "  %s  "%[get_bool_str(is_no_H_valid)])
		add_invalid(data_containers[Tab.Other], is_no_H_valid)

	elif ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.Z):
		var neutral_Z: bool = ConnectedInteraction.has_shadeless_Z(particles)
		add_label(data_containers[Tab.Other], property_names[Tab.Other][OtherProperties.ShadelessZ])
		add_label(data_containers[Tab.Other], "  %s  "%[get_bool_str(neutral_Z)])
		add_invalid(data_containers[Tab.Other], !neutral_Z)

func add_label(container: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.use_parent_material = true
	
	
	if container.get_child_count()%container.columns != 0:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
	container.add_child(label)

func add_invalid(container: GridContainer, valid: bool) -> void:
	if valid:
		container.add_child(valid_icon.instantiate())
	else:
		container.add_child(invalid_icon.instantiate())

func get_relevant_quantum_numbers() -> Array[ParticleData.QuantumNumber]:
	var relevant_quantum_numbers: Array[ParticleData.QuantumNumber] = []
	
	relevant_quantum_numbers.append(ParticleData.QuantumNumber.charge)
	
	for base_particle in ConnectedInteraction.connected_base_particles:
		if base_particle in ParticleData.LEPTONS:
			relevant_quantum_numbers.append(ParticleData.QuantumNumber.lepton)
			break
	
	if (
		ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.electron) or
		ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.electron_neutrino)
	):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.electron)
		
	if (
		ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.muon) or
		ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.muon_neutrino)
	):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.muon)
		
	if (
		ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.tau) or
		ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.tau_neutrino)
	):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.tau)
	
	for base_particle in ConnectedInteraction.connected_base_particles:
		if base_particle in ParticleData.QUARKS:
			relevant_quantum_numbers.append(ParticleData.QuantumNumber.quark)
			break

	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.up):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.up)

	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.down):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.down)

	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.charm):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.charm)

	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.strange):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.strange)

	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.top):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.top)

	if ConnectedInteraction.has_base_particle_connected(ParticleData.Particle.bottom):
		relevant_quantum_numbers.append(ParticleData.QuantumNumber.bottom)
	
	return relevant_quantum_numbers

func is_integer(test_float: float) -> bool:
	return is_zero_approx(abs(test_float) - floor(abs(test_float)))

func _on_close_button_pressed() -> void:
	closed_button_pressed.emit()

func _on_tab_container_child_entered_tree(node: Control) -> void:
	node.material = load("res://Resources/Shaders/palette_swap_material.tres")
	node.mouse_filter = Control.MOUSE_FILTER_PASS
