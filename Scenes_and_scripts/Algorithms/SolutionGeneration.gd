extends Node

const INTERACTION_SIZE : int = 3

enum Find {All, LowestOrder, One}

var start_time : float
var print_times := false

var find_one: bool = false
var found_one: bool = false
var found_matrix: ConnectionMatrix = null
var g_degree: int
var g_particle_interactions: Dictionary = {}
var g_allow_tadpoles: bool
var g_self_energies: bool

var find: Find = Find.All

func generate_diagrams(
	initial_state: Array,
	final_state: Array,
	min_degree: int,
	max_degree: int,
	useable_particles: PackedInt32Array,
	p_find: Find = Find.All,
	allow_tadpoles: bool = false,
	self_energies: bool = false
) -> Array[ConnectionMatrix]:
	
	find = p_find
	find_one = find == Find.One
	found_one = false
	
	g_allow_tadpoles = allow_tadpoles
	g_self_energies = self_energies
	
	start_time = Time.get_ticks_usec()
	var print_results : bool = false
	
	if print_results:
		print(initial_state)
		print(final_state)
	
	if !are_quantum_numbers_valid(initial_state, final_state):
		print('Initial state quantum numbers do not match final state')
		return [null]
	
	g_particle_interactions = get_useable_particle_interactions(useable_particles)
	
	for state_interaction:Array in (initial_state + final_state):
		if state_interaction.any(
			func(particle: ParticleData.Particle) -> bool:
				return ParticleData.base(particle) not in g_particle_interactions.keys()
		):
			return [null]
	
	var base_interaction_matrix := create_base_interaction_matrix(initial_state, final_state)
	var degrees_to_check := get_degrees_to_check(
		min_degree, max_degree, base_interaction_matrix
	)
	
	var generated_connection_matrices : Array[ConnectionMatrix] = []
	var base_matrix := convert_interaction_matrix_to_in_out(base_interaction_matrix)
	
	for degree:int in degrees_to_check:
		if find == Find.LowestOrder and !generated_connection_matrices.is_empty():
			break
		
		g_degree = degree
		
		var hadron_connected_matrices := connect_hadrons(base_matrix)
		
		if find_one:
			if found_one:
				return [found_matrix]
			continue
		
		var state_fermion_connected_matrices : Array[InteractionMatrix] = []
		for matrix:InteractionMatrix in hadron_connected_matrices:
			state_fermion_connected_matrices.append_array(
				connect_state_fermions(matrix)
			)
		hadron_connected_matrices.clear()

		var connected_matrices: Array[InteractionMatrix] = []
		
		for matrix:InteractionMatrix in state_fermion_connected_matrices:
			if (
				is_matrix_colourless(matrix)
				or is_disconnected(matrix)
				or has_state_fermion(matrix)
			):
				continue
			elif is_complete(matrix):
				connected_matrices.push_back(matrix)
				continue
			
			connected_matrices.append_array(connect_matrix(matrix))

		generated_connection_matrices.append_array(
			get_connection_matrices(connected_matrices).filter(
				func(matrix:ConnectionMatrix) -> bool:
					return !is_matrix_colourless(matrix)
					)
		)
		
		if find == Find.LowestOrder and !generated_connection_matrices.is_empty():
			return generated_connection_matrices
	
	if generated_connection_matrices.is_empty():
		return [null]
		
	return generated_connection_matrices

func has_state_fermion(matrix: InteractionMatrix) -> bool:
	return matrix.unconnected_matrix.any(
		func(interaction:Array) -> bool:
			return interaction.any(
				func(particle:ParticleData.Particle) -> bool:
					return ParticleData.is_fermion(particle) && !ParticleData.is_general(particle)
			)
	)
		

func shuffle_particle_interactions() -> void:
	for particle:ParticleData.Particle in g_particle_interactions.keys():
		g_particle_interactions[particle].shuffle()

func get_hadron_ids(matrix: InteractionMatrix) -> PackedInt32Array:
	return ArrayFuncs.packed_int_filter(
		matrix.get_state_ids(StateLine.State.Initial),
		matrix.is_hadron
	)

func connect_hadrons(
	base_matrix: InteractionMatrix,
	hadron_ids: PackedInt32Array = get_hadron_ids(base_matrix)
) -> Array[InteractionMatrix]:
	var to_ids := ArrayFuncs.packed_int_filter(
		base_matrix.get_state_ids(StateLine.State.Final),
		base_matrix.is_hadron
	)
	
	if hadron_ids.is_empty():
		if find_one:
			connect_state_fermions(base_matrix)
			return []
		else:
			return [base_matrix]
	
	var connected_matrices: Array[InteractionMatrix] = [base_matrix]
	for id:int in hadron_ids:
		var hadron_connected_matrices : Array[InteractionMatrix] = []
		
		for matrix:InteractionMatrix in connected_matrices:
			var hadron: PackedInt32Array = matrix.unconnected_matrix[id]
			hadron.sort()
			
			var unconnected_particles: PackedInt32Array = []
			for to_id: int in to_ids:
				var particles := PackedInt32Array(matrix.unconnected_matrix[to_id])
				unconnected_particles.append_array(particles)
			
			var further_matrices: Array[InteractionMatrix] = []
			
			var can_leave_all := is_connection_number_possible(
				matrix.get_unconnected_particle_count(), g_degree
			)
			
			if can_leave_all:
				further_matrices.push_back(matrix)
			
			if hadron.size() == 2:
				further_matrices.append_array(
					connect_3interaction(
						hadron,
						matrix,
						unconnected_particles,
						g_degree,
						ParticleData.Particle.none,
						id,
						id,
						0,
						to_ids,
						false
					)
				)
			else:
				further_matrices.append_array(
					connect_4interaction(
						hadron,
						matrix,
						unconnected_particles,
						g_degree,
						ParticleData.Particle.none,
						id,
						id,
						0,
						to_ids,
						false
					)
				)
			
			further_matrices = further_matrices.filter(
				func(matrix:InteractionMatrix) -> bool:
					return !is_disconnected_id(matrix, id)
			)
			
			if find_one:
				for further_matrix:InteractionMatrix in further_matrices:
					connect_hadrons(further_matrix, hadron_ids.slice(1))
					if found_one:
						return []
				continue

			hadron_connected_matrices.append_array(further_matrices)
		
		if find_one:
			return []
			
		connected_matrices.assign(hadron_connected_matrices)

	return connected_matrices

func is_disconnected_id(matrix: InteractionMatrix, id: int) -> bool:
	var reachable_ids: PackedInt32Array = matrix.reach_ids(id, [], true)
	
	if reachable_ids.size() == matrix.matrix_size:
		return false
	
	return ArrayFuncs.packed_int_all(
		reachable_ids, 
		func(jd: int) -> bool:
			return matrix.unconnected_matrix[jd].is_empty()
	)

func is_entry_fermion(particle: ParticleData.Particle) -> bool:
	return (
		particle > 0
		and ParticleData.is_fermion(particle)
		and !ParticleData.is_general(particle)
	)

func is_matrix_colourless(matrix: ConnectionMatrix) -> bool:
	var has_gluon: bool = !matrix.find_first_id(
		func(id: int) -> bool:
			return ParticleData.Particle.gluon in matrix.get_connected_particles(id)
	) == matrix.matrix_size
	
	if !has_gluon:
		return false
	
	var drawing_matrix: DrawingMatrix = DrawingMatrix.new(matrix)
	var path_data: Vision.PathData = Vision.generate_colour_paths(drawing_matrix)
	
	return Vision.find_colourless_interactions(
		path_data,
		drawing_matrix,
		true
	).size() > 0

func connect_state_fermions(base_matrix: InteractionMatrix) -> Array[InteractionMatrix]:
	var fermion_entry_states : Array = base_matrix.unconnected_matrix.map(
		func(state: Array) -> Array:
			return state.filter(is_entry_fermion)
	)
	var fermion_entry_ids : PackedInt32Array = ArrayFuncs.find_all_var(
		fermion_entry_states, func(state: Array) -> bool: return !state.is_empty()
	)
	
	if fermion_entry_ids.is_empty():
		if has_state_fermion(base_matrix):
			return []
		
		if find_one:
			connect_matrix(base_matrix)
		else:
			return [base_matrix]
	
	if found_one:
		return []
	
	var connected_interaction_matrices: Array[InteractionMatrix] = [base_matrix]

	for id:int in fermion_entry_ids:
		for fermion:ParticleData.Particle in fermion_entry_states[id]:
			var fermion_connected_matrices: Array[InteractionMatrix] = []
			
			for interaction_matrix:InteractionMatrix in connected_interaction_matrices:
				if fermion not in interaction_matrix.unconnected_matrix[id]:
					fermion_connected_matrices.push_back(interaction_matrix)
					continue
				
				fermion_connected_matrices.append_array(
					connect_fermion_from_id(
						fermion,
						id,
						-1,
						interaction_matrix
					)
				)
			
			fermion_connected_matrices = fermion_connected_matrices.filter(
				func(matrix: InteractionMatrix) -> bool:
					return !is_disconnected_id(matrix, id)
			)
			connected_interaction_matrices.assign(fermion_connected_matrices)

	return connected_interaction_matrices

func connect_matrix(base_matrix: InteractionMatrix) -> Array[InteractionMatrix]:
	var connected_matrices: Array[InteractionMatrix] = []
	var to_connect_matrices: Array[InteractionMatrix] = [base_matrix]
	
	var entry_ids: PackedInt32Array = base_matrix.find_all_unconnected(
		func(particle: ParticleData.Particle) -> bool:
			return particle >= 0
	)
	
	#if base_matrix.get_unconnected_particle_count() == 2
	
	if entry_ids.is_empty():
		if find_one:
			if is_disconnected(base_matrix) or is_matrix_colourless(base_matrix):
				return []
			elif is_complete(base_matrix):
				found_one = true
				found_matrix = base_matrix.get_connection_matrix()
				return []
		else:
			return [base_matrix]
	
	if found_one:
		return []

		
	for from_id:int in entry_ids:
		var further_matrices: Array[InteractionMatrix] = []
		for matrix:InteractionMatrix in to_connect_matrices:
			
			if (
				matrix.unconnected_matrix[from_id].is_empty()
				or get_next_particle(matrix.unconnected_matrix[from_id]) == ParticleData.Particle.none
			):
				further_matrices.push_back(matrix)
				continue

			further_matrices.append_array(
				connect_matrix_from_id(matrix, from_id)
			)
		
		to_connect_matrices.clear()
		for matrix:InteractionMatrix in further_matrices:
			if is_disconnected_id(matrix, from_id):
				continue
			elif is_complete(matrix):
				connected_matrices.push_back(matrix)
			else:
				to_connect_matrices.push_back(matrix)
		
		if to_connect_matrices.is_empty():
			break
				
	return connected_matrices

func convert_interaction_matrix_to_in_out(interaction_matrix: InteractionMatrix) -> InteractionMatrix:
	var converted_matrix: InteractionMatrix = interaction_matrix.duplicate(true)
	
	for id:int in converted_matrix.matrix_size:
		converted_matrix.unconnected_matrix[id] = converted_matrix.unconnected_matrix[id].map(
			func(particle:ParticleData.Particle) -> ParticleData.Particle:
				if particle in ParticleData.UNSHADED_PARTICLES:
					return particle
				
				return StateLine.state_factor[interaction_matrix.get_state_from_id(id)] * particle
		)
	
	return converted_matrix

func connect_particle_from_id(
	particle: ParticleData.Particle,
	from_id: int,
	base_matrix: InteractionMatrix
) -> Array[InteractionMatrix]:
	if found_one:
		return []
	
	var particle_interactions: Array = g_particle_interactions[particle]
	
	if find_one:
		particle_interactions = g_particle_interactions[particle].duplicate(true)
		particle_interactions.shuffle()

	var unconnected_particles: PackedInt32Array = base_matrix.get_unconnected_particles()
	unconnected_particles.remove_at(unconnected_particles.find(particle))
	
	var connected_matrices : Array[InteractionMatrix] = []

	for interaction:PackedInt32Array in particle_interactions:
		var interaction_connected_matrices := get_interaction_connected_matrices(
			interaction,
			base_matrix,
			particle,
			from_id,
			unconnected_particles,
		)
		
		if interaction_connected_matrices.is_empty():
			continue
		
		if find_one:
			interaction_connected_matrices.shuffle()
		
		var further_connected_matrices : Array[InteractionMatrix] = []
		for matrix:InteractionMatrix in interaction_connected_matrices:
			further_connected_matrices.append_array(
				connect_matrix_from_id(matrix, base_matrix.matrix_size, from_id, interaction)
			)
		
		if further_connected_matrices.is_empty():
			continue
		
		if interaction.size() == 2 and interaction[0] == interaction[1]:
			further_connected_matrices.sort_custom(sort_interaction_matrices)
			connected_matrices.append_array(
				get_3_distinguishable_matrices(
					further_connected_matrices,
					base_matrix.matrix_size,
					from_id,
				)
				)
		elif interaction.size() == 3:
			further_connected_matrices.sort_custom(sort_interaction_matrices)
			connected_matrices.append_array(
				get_4_distinguishable_matrices(
					interaction,
					further_connected_matrices,
					base_matrix.matrix_size,
					from_id
				)
			)
		else:
			connected_matrices.append_array(further_connected_matrices)
	
	return connected_matrices

static func sort_interaction_matrices(
	matrixA: InteractionMatrix,
	matrixB: InteractionMatrix
) -> bool:
	return matrixA.particle_count < matrixB.particle_count

func is_distinguishable(
	matrix:InteractionMatrix,
	matrices:Array[InteractionMatrix],
	from_id:int,
	to_remove_ids:PackedInt32Array,
	to_remove_index:int
) -> bool:
	if matrix.particle_count != matrices[0].particle_count:
		return true
	
	if !matrix.unconnected_matrix[from_id].is_empty():
		return true

	var to_ids := matrix.get_connected_ids(from_id, true)
	
	for id:int in to_remove_ids:
		to_ids.remove_at(to_ids.find(id))
		
	to_ids.sort()
	
	if to_remove_index != -1 and to_ids.size() == 3:
		to_ids.remove_at(to_remove_index)
	
	if to_ids.size() != 2 or ArrayFuncs.packed_int_any(
		to_ids,
		func(id:int) -> bool:
			return (
				matrix.get_state_from_id(id) != StateLine.State.None
				or !matrix.unconnected_matrix[id].is_empty()
			)
	):
		return true
	
	var swapped_matrix := matrix.duplicate(true)
	swapped_matrix.swap_ids(to_ids[0], to_ids[1])
	
	return !matrices.any(
		func(matrixB: InteractionMatrix) -> bool:
			return swapped_matrix.is_duplicate_interaction_matrix(matrixB)
	)

func get_3_distinguishable_matrices(
	matrices: Array[InteractionMatrix],
	from_id: int,
	to_remove_id: int,
	to_remove_particle := ParticleData.Particle.none,
	to_remove_index: int = -1
) -> Array[InteractionMatrix]:
	if matrices.size() <= 1:
		return matrices
	
	var distinguished_matrices: Array[InteractionMatrix] = []
	
	for i:int in range(matrices.size() - 1):
		var matrix := matrices[i]
		var to_remove_ids: PackedInt32Array = [to_remove_id]
		if to_remove_particle != ParticleData.Particle.none:
			if ParticleData.is_anti(to_remove_particle):
				to_remove_ids.push_back(
					matrix.get_connected_ids(
						from_id,
						false,
						ParticleData.base(to_remove_particle),
						true
					)[0]
				)
			else:
				to_remove_ids.push_back(
					matrix.get_connected_ids(from_id, true, to_remove_particle)[0]
				)
		
		if is_distinguishable(
			matrix,
			matrices.slice(i+1),
			from_id,
			to_remove_ids,
			to_remove_index
		):
			distinguished_matrices.push_back(matrix)
	
	distinguished_matrices.push_back(matrices[-1])

	return distinguished_matrices

func get_4_distinguishable_matrices(
	interaction: PackedInt32Array,
	matrices: Array[InteractionMatrix],
	from_id: int,
	prev_id: int
) -> Array[InteractionMatrix]:
	if matrices.size() == 1:
		return matrices
	
	var particleA: ParticleData.Particle = interaction[0]
	var particleB: ParticleData.Particle = interaction[1]
	var particleC: ParticleData.Particle = interaction[2]
	
	if particleA == particleB and particleA == particleC:
		var distinguished_matrices : Array[InteractionMatrix]
		for i:int in range(3):
			if i == 0:
				distinguished_matrices = get_3_distinguishable_matrices(
					matrices,
					from_id,
					prev_id,
					ParticleData.Particle.none,
					i
				)
				continue
			
			distinguished_matrices = get_3_distinguishable_matrices(
				distinguished_matrices,
				from_id,
				prev_id,
				ParticleData.Particle.none,
				i
			)
		return distinguished_matrices

	elif particleA == particleB:
		return get_3_distinguishable_matrices(
			matrices,
			from_id,
			prev_id,
			particleC
		)
	elif particleB == particleC:
		return get_3_distinguishable_matrices(
			matrices,
			from_id,
			prev_id,
			particleA
		)
	elif particleA == particleC:
		return get_3_distinguishable_matrices(
			matrices,
			from_id,
			prev_id,
			particleB
		)
	else:
		return matrices

func get_interaction_connected_matrices(
	interaction:PackedInt32Array,
	base_matrix:InteractionMatrix,
	from_particle:ParticleData.Particle,
	from_id:int,
	unconnected_particles:PackedInt32Array,
) -> Array[InteractionMatrix]:
	var interaction_degree: int = 1 if interaction.size() == 2 else 2
	var interaction_count: int = g_degree - base_matrix.degree
	
	if interaction_degree > interaction_count:
		return []
	
	var interaction_connected_matrices: Array[InteractionMatrix] = []
	
	var can_leave_all := is_connection_number_possible(
		unconnected_particles.size() + interaction.size(), interaction_count - interaction_degree
	)

	if can_leave_all:
		interaction_connected_matrices.push_back(
			add_interaction(interaction, base_matrix, from_particle, from_id, interaction_degree)
		)
	
	var new_id: int = base_matrix.matrix_size
	
	if interaction_degree == 1:
		interaction_connected_matrices.append_array(
			connect_3interaction(
				interaction,
				base_matrix,
				unconnected_particles,
				interaction_count - interaction_degree,
				from_particle,
				from_id,
				new_id,
				interaction_degree,
				range(base_matrix.matrix_size),
				g_allow_tadpoles
			)
		)
	else:
		interaction_connected_matrices.append_array(
			connect_4interaction(
				interaction,
				base_matrix,
				unconnected_particles,
				interaction_count - interaction_degree,
				from_particle,
				from_id,
				new_id,
				interaction_degree,
				range(base_matrix.matrix_size),
				true
			)
		)
		
	return interaction_connected_matrices

func is_disconnected(matrix: InteractionMatrix) -> bool:
	if is_complete(matrix):
		return !matrix.is_fully_connected(true)
	
	return (
		matrix.degree > 0
		and matrix.get_unconnected_state_particle_count(StateLine.State.None) == 0
		and matrix.get_unconnected_state_particle_count(StateLine.State.Both) != 0
	)

func is_complete(matrix: InteractionMatrix) -> bool:
	return matrix.get_unconnected_particle_count() == 0

func is_tadpole_id(id:int, matrix: InteractionMatrix, interaction:PackedInt32Array) -> bool:
	if matrix.degree == 0:
		return false
	
	if interaction.size() == 3:
		return false
	
	return ArrayFuncs.packed_int_all(
		range(matrix.matrix_size),
		func(jd: int) -> bool:
			return (
				jd == id
				or matrix.unconnected_matrix[jd].is_empty()
			)
			)

func is_self_energy(to_id: int, from_id: int, matrix: InteractionMatrix) -> bool:
	if to_id == -1 or from_id == -1:
		return false
	
	if (
		matrix.get_state_from_id(to_id) != StateLine.State.None
		or matrix.get_state_from_id(from_id) != StateLine.State.None
	):
		return false
	
	var is_four_interaction := (
		matrix.get_interaction_size(from_id) == 4
		or matrix.get_interaction_size(to_id) == 4
	)
	var is_double_connection := matrix.get_connection_size(from_id, to_id, true) > 1
	
	var reach_behind_ids := matrix.reach_ids(
		from_id,
		[],
		true,
		[to_id],
		!(is_four_interaction and is_double_connection)
)
	if reach_behind_ids.size() == matrix.matrix_size:
		return false
	
	var behind_state_id_count := 0
	var behind_is_disconnected := false
	for id:int in reach_behind_ids:
		if !behind_is_disconnected and !matrix.unconnected_matrix[id].is_empty():
			behind_is_disconnected = true
		
		if matrix.get_state_from_id(id) != StateLine.State.None:
			behind_state_id_count += 1
	
	if !behind_is_disconnected and (
		behind_state_id_count == 1
		or behind_state_id_count == matrix.get_state_count(StateLine.State.Both) - 1
	):
		return true
	
	var reach_ahead_ids := matrix.reach_ids(
		to_id,
		[],
		true,
		[from_id],
		!(is_four_interaction and is_double_connection)
)
	if reach_ahead_ids.size() == matrix.matrix_size:
		return false
	
	var ahead_state_id_count := 0
	var ahead_is_disconnected := false
	for id:int in reach_ahead_ids:
		if !ahead_is_disconnected and !matrix.unconnected_matrix[id].is_empty():
			ahead_is_disconnected = true
		
		if matrix.get_state_from_id(id) != StateLine.State.None:
			ahead_state_id_count += 1
	
	if !ahead_is_disconnected and (
		ahead_state_id_count == 1
		or ahead_state_id_count == matrix.get_state_count(StateLine.State.Both) - 1
	):
		return true
	
	if ahead_state_id_count == 0:
		return ArrayFuncs.packed_int_any(
			matrix.get_connected_ids(from_id, true),
			func(id: int) -> bool:
				if id == to_id:
					return false
				
				return is_self_energy(id, from_id, matrix)
		)
	
	elif behind_state_id_count == 0:
		return ArrayFuncs.packed_int_any(
			matrix.get_connected_ids(to_id, true),
			func(id: int) -> bool:
				if id == from_id:
					return false
				
				return is_self_energy(id, to_id, matrix)
		)
	
	return false

func has_self_energy(matrix: InteractionMatrix, to_id: int, from_id: int) -> bool:
	var unconnected_ids := matrix.get_unconnected_ids()
	if (
		unconnected_ids.size() == 2
		and ArrayFuncs.packed_int_all(
			unconnected_ids,
			func(id: int) -> bool:
				return matrix.get_interaction_size(id) != 4
				)
		 and ArrayFuncs.packed_int_any(
			unconnected_ids,
			func(id: int) -> bool:
				return matrix.get_state_from_id(id) != StateLine.State.None
				)
	):
		return true
	
	return is_self_energy(to_id, from_id, matrix)

func connect_matrix_from_id(
	base_matrix: InteractionMatrix,
	from_id: int,
	prev_id: int = -1,
	interaction: PackedInt32Array = []
) -> Array[InteractionMatrix]:
	if found_one:
		return []
	
	if is_disconnected(base_matrix):
		return []
	
	if !g_self_energies and has_self_energy(base_matrix, from_id, prev_id):
		return []
	
	if is_complete(base_matrix):
		if find_one:
			var connection_matrix := base_matrix.get_connection_matrix()
			if !is_matrix_colourless(connection_matrix):
				found_one = true
				found_matrix = connection_matrix
				return []
		
		return [base_matrix]

	if base_matrix.unconnected_matrix[from_id].is_empty():
		return [base_matrix]
	
	if !g_allow_tadpoles and is_tadpole_id(from_id, base_matrix, interaction):
		return []

	var connected_matrices: Array[InteractionMatrix] = []
	var to_connect_matrices: Array[InteractionMatrix] = [base_matrix]
	for i:int in base_matrix.unconnected_matrix[from_id].size():
		var further_matrices: Array[InteractionMatrix] = []
		
		for matrix:InteractionMatrix in to_connect_matrices:
			if found_one:
				return []
			
			var next_particle := get_next_particle(matrix.unconnected_matrix[from_id])
			
			if next_particle == ParticleData.Particle.none:
				if find_one:
					connect_matrix(matrix)
				else:
					connected_matrices.push_back(matrix)

				continue
			
			further_matrices.append_array(
				connect_particle_from_id(next_particle, from_id, matrix	)
			)
		
		to_connect_matrices.clear()
		for matrix:InteractionMatrix in further_matrices:
			if matrix.unconnected_matrix[from_id].is_empty():
				connected_matrices.push_back(matrix)
			else:
				to_connect_matrices.push_back(matrix)
		
		if to_connect_matrices.is_empty():
			break
		
	return connected_matrices

func add_interaction(
	interaction: PackedInt32Array,
	base_matrix: InteractionMatrix,
	particle: ParticleData.Particle,
	from_id: int,
	degree: int
) -> InteractionMatrix:
	var particle_connected_matrix := base_matrix.duplicate(true)
	
	if particle == ParticleData.Particle.none:
		return particle_connected_matrix
	
	particle_connected_matrix.add_unconnected_interaction(
		interaction,
		StateLine.State.None,
		base_matrix.matrix_size,
		degree
	)
	particle_connected_matrix.connect_interactions_no_remove(
		from_id, base_matrix.matrix_size, particle, true, false
	)
	return particle_connected_matrix

func is_connection_possible(
	unconnected_particles: PackedInt32Array,
	connection_particles: PackedInt32Array,
	interaction_size: int,
	interaction_count: int
) -> bool:
	return (
		is_connection_number_possible(
			unconnected_particles.size() + interaction_size - 2*connection_particles.size(),
			interaction_count
		) and has_connection_particles(
			unconnected_particles, connection_particles
		)
	)

func is_self_connection_possible(
	particleA: ParticleData.Particle,
	particleB: ParticleData.Particle,
	unconnected_particle_count: int,
	interaction_count
) -> bool:
	return (
		is_connection_particle(particleA, particleB)
		and is_connection_number_possible(
			unconnected_particle_count - 2,
			interaction_count
		)
	)

func connect_3interaction(
	interaction:PackedInt32Array,
	base_matrix:InteractionMatrix,
	unconnected_particles:PackedInt32Array,
	interaction_count:int,
	particle:ParticleData.Particle,
	from_id:int,
	new_id:int,
	degree:int,
	to_ids:PackedInt32Array = range(base_matrix.matrix_size),
	allow_self_connect: bool = true
) -> Array[InteractionMatrix]:
	var unconnected_particle_count: int = unconnected_particles.size()
	var interaction_size: int = interaction.size()
	
	var particleA: ParticleData.Particle = interaction[0] as ParticleData.Particle
	var particleB: ParticleData.Particle = interaction[1] as ParticleData.Particle
	var is_same_particle: bool = particleA == particleB
	
	var can_connect_A := is_connection_possible(
		unconnected_particles, [particleA], interaction_size, interaction_count
	)
	
	var can_connect_B := (
		!is_same_particle
		and is_connection_possible(
			unconnected_particles, [particleB], interaction_size, interaction_count
		)
	)
	
	var can_connect_both := is_connection_possible(
		unconnected_particles, interaction, interaction_size, interaction_count
	)
	
	var can_self_connect := (
		allow_self_connect
		and is_connection_particle(particleA, particleB)
		and is_connection_number_possible(unconnected_particles.size(), interaction_count)
	)

	if !(
		can_connect_A
		or can_connect_B
		or can_connect_both
		or can_self_connect
	):
		return []
	
	var particle_connected_matrix : InteractionMatrix = add_interaction(interaction, base_matrix, particle, from_id, degree)
	var connected_matrices: Array[InteractionMatrix] = []
	if can_connect_A:
		connected_matrices.append_array(
			connect_particle_to_ids(particleA, new_id, particle_connected_matrix, to_ids)
		)
		
	if can_connect_B:
		connected_matrices.append_array(
			connect_particle_to_ids(particleB, new_id, particle_connected_matrix, to_ids)
		)
	
	if can_connect_both:
		connected_matrices.append_array(
			connect_2_particles_to_ids(particleA, particleB, new_id, particle_connected_matrix, to_ids)
		)
	
	if can_self_connect:
		connected_matrices.push_back(
			self_connect(particleA, particleB, new_id, particle_connected_matrix)
		)
	
	return connected_matrices

func connect_4interaction(
	interaction:PackedInt32Array,
	base_matrix:InteractionMatrix,
	unconnected_particles:PackedInt32Array,
	interaction_count:int,
	particle:ParticleData.Particle,
	from_id:int,
	new_id:int,
	degree:int,
	to_ids:PackedInt32Array = range(base_matrix.matrix_size),
	allow_self_connect: bool = true
) -> Array[InteractionMatrix]:
	var unconnected_particle_count: int = unconnected_particles.size()
	var interaction_size: int = interaction.size()
	
	if len(interaction) < 3:
		return []
	
	var particleA: ParticleData.Particle = interaction[0] as ParticleData.Particle
	var particleB: ParticleData.Particle = interaction[1] as ParticleData.Particle
	var particleC: ParticleData.Particle = interaction[2] as ParticleData.Particle
	
	var is_AB_same_particle := particleA == particleB
	var is_BC_same_particle := particleB == particleC
	var is_AC_same_particle := particleA == particleC
	var is_same_particle := (is_AB_same_particle and is_AC_same_particle)
	
	var is_AB_connection_particle := is_AB_same_particle or is_connection_particle(particleA, particleB)
	var is_BC_connection_particle := is_BC_same_particle or is_connection_particle(particleB, particleC)
	var is_AC_connection_particle := is_AC_same_particle or is_connection_particle(particleA, particleC)
	
	var can_connect_A := is_connection_possible(
		unconnected_particles, [particleA], interaction_size, interaction_count
	)

	var can_connect_B := (
		!is_AB_same_particle
		and is_connection_possible(
			unconnected_particles, [particleB], interaction_size, interaction_count
		)
	)
	
	var can_connect_C := (
		!is_AC_same_particle
		and !is_BC_same_particle
		and is_connection_possible(
			unconnected_particles, [particleC], interaction_size, interaction_count
		)
	)
	
	var can_connect_AB := is_connection_possible(
		unconnected_particles, [particleA, particleB], interaction_size, interaction_count
	)
	
	var can_connect_BC := (
		!is_same_particle
		and is_connection_possible(
			unconnected_particles, [particleB, particleC], interaction_size, interaction_count
		)
	)
	
	var can_connect_AC := (
		!is_same_particle
		and !(can_connect_AB and is_BC_same_particle)
		and !(can_connect_BC and is_AB_same_particle)
		and is_connection_possible(
			unconnected_particles, [particleA, particleC], interaction_size, interaction_count
		)
	)
	
	var can_connect_ABC := (
		is_connection_possible(
			unconnected_particles, interaction, interaction_size, interaction_count
		)
	)
	
	var can_self_connect_AB := (
		allow_self_connect
		and is_AB_connection_particle
		and is_connection_number_possible(unconnected_particle_count + 1, interaction_count)
	)
	
	var can_self_connect_BC := (
		allow_self_connect
		and !is_same_particle
		and is_BC_connection_particle
		and is_connection_number_possible(unconnected_particle_count + 1, interaction_count)
	)
	
	var can_self_connect_AC := (
		allow_self_connect
		and !is_same_particle
		and is_AC_connection_particle
		and is_connection_number_possible(unconnected_particle_count + 1, interaction_count)
	)
	
	var can_self_connect_ABC := (
		allow_self_connect
		and (is_AB_connection_particle or is_AB_connection_particle or is_AC_connection_particle)
		and is_connection_number_possible(unconnected_particle_count - 1, interaction_count)
	)
	
	if !(
		can_connect_A
		or can_connect_B
		or can_connect_C
		or can_connect_AB
		or can_connect_BC
		or can_connect_AC
		or can_connect_ABC
		or can_self_connect_AB
		or can_self_connect_BC
		or can_self_connect_AC
		or can_self_connect_ABC
	):
		return []
	
	
	var particle_connected_matrix := add_interaction(interaction, base_matrix, particle, from_id, degree)
	
	var connected_matrices: Array[InteractionMatrix] = []
	if can_connect_A:
		connected_matrices.append_array(
			connect_particle_to_ids(particleA, new_id, particle_connected_matrix, to_ids)
		)
	if can_connect_B:
		connected_matrices.append_array(
			connect_particle_to_ids(particleB, new_id, particle_connected_matrix, to_ids)
		)
	if can_connect_C:
		connected_matrices.append_array(
			connect_particle_to_ids(particleC, new_id, particle_connected_matrix, to_ids)
		)

	if can_connect_AB:
		connected_matrices.append_array(
			connect_2_particles_to_ids(particleA, particleB, new_id, particle_connected_matrix, to_ids)
		)
	if can_connect_BC:
		connected_matrices.append_array(
			connect_2_particles_to_ids(particleB, particleC, new_id, particle_connected_matrix, to_ids)
		)
	if can_connect_AC:
		connected_matrices.append_array(
			connect_2_particles_to_ids(particleA, particleC, new_id, particle_connected_matrix, to_ids)
		)
	
	if can_connect_ABC :
		connected_matrices.append_array(
			connect_3_particles_to_ids(particleA, particleB, particleC, new_id, particle_connected_matrix, to_ids)
		)
	
	if can_self_connect_AB:
		connected_matrices.push_back(
			self_connect(particleA, particleB, new_id, particle_connected_matrix)
		)
	if can_self_connect_BC:
		connected_matrices.push_back(
			self_connect(particleB, particleC, new_id, particle_connected_matrix)
		)
	if can_self_connect_AC:
		connected_matrices.push_back(
			self_connect(particleA, particleC, new_id, particle_connected_matrix)
		)
	
	if can_self_connect_ABC:
		connected_matrices.append_array(
			self_connect_ABC(
				particleA,
				particleB,
				particleC,
				is_AB_connection_particle,
				is_BC_connection_particle,
				is_AC_connection_particle,
				new_id,
				particle_connected_matrix
			)
		)
	
	return connected_matrices

func get_next_particle(interaction: PackedInt32Array) -> ParticleData.Particle:
	for particle: ParticleData.Particle in interaction:
		if particle < 0:
			continue
		if ParticleData.is_fermion(particle):
			return particle
	
	for particle: ParticleData.Particle in interaction:
		if particle < 0:
			continue
		if ParticleData.is_particle(particle, ParticleData.Particle.W):
			return particle
	
	for particle: ParticleData.Particle in interaction:
		if !ParticleData.has_shade(particle):
			return particle
	
	return ParticleData.Particle.none

func connect_fermion_from_id(
	fermion: ParticleData.Particle,
	from_id: int,
	prev_id: int,
	base_matrix: InteractionMatrix
) -> Array[InteractionMatrix]:
	
	if found_one:
		return []
	
	var particle_interactions: Array = g_particle_interactions[fermion]
	
	if find_one:
		particle_interactions = g_particle_interactions[fermion].duplicate(true)
		particle_interactions.shuffle()

	if is_disconnected(base_matrix):
		return []

	var unconnected_particles: PackedInt32Array = base_matrix.get_unconnected_particles()
	
	unconnected_particles.remove_at(unconnected_particles.find(fermion))
	
	var connected_matrices: Array[InteractionMatrix] = []
	for interaction:PackedInt32Array in particle_interactions:
		var interaction_connected_matrices := get_interaction_connected_matrices(
			interaction,
			base_matrix,
			fermion,
			from_id,
			unconnected_particles
		)
		
		if find_one:
			interaction_connected_matrices.shuffle()
		
		var new_id: int = base_matrix.matrix_size
		for matrix:InteractionMatrix in interaction_connected_matrices:
			if found_one:
				return []

			if !g_self_energies and has_self_energy(matrix, new_id, from_id):
				continue
			
			var next_particle: ParticleData.Particle = get_next_particle(
				matrix.unconnected_matrix[new_id]
			)

			if (
				next_particle == ParticleData.Particle.none
				or !ParticleData.is_fermion(next_particle)
			):
				if find_one:
					connect_state_fermions(matrix)
				else:
					connected_matrices.push_back(matrix)
				continue
			
			connected_matrices.append_array(
				connect_fermion_from_id(
					next_particle,
					new_id,
					from_id,
					matrix
				)
			)
	
	return connected_matrices

func convert_general_path_from_id(
	from_id: int,
	general_particle: ParticleData.Particle,
	fermion: ParticleData.Particle,
	matrix: InteractionMatrix,
	reverse: bool
) -> void:
	
	var connected_ids := matrix.get_connected_ids(
		from_id,
		false,
		general_particle,
		reverse
	)
	
	if connected_ids.is_empty():
		return
	
	var next_id: int = connected_ids[0]
	
	matrix.disconnect_interactions_no_add(
		from_id, next_id, general_particle, false, false, reverse
	)
	matrix.connect_interactions_no_remove(
		from_id, next_id, fermion, false, false, reverse
	)
	
	convert_general_path_from_id(
		next_id,
		general_particle,
		fermion,
		matrix,
		reverse
	)

func connect_particle_to_ids(
	particle: ParticleData.Particle,
	from_id: int,
	base_matrix: InteractionMatrix,
	to_ids: PackedInt32Array = range(base_matrix.matrix_size),
	start_particle_index: int = 0
) -> Array[InteractionMatrix]:
	var connected_matrices: Array[InteractionMatrix] = []
	
	for to_id:int in to_ids:
		if to_id == from_id:
			continue

		var connected_particles: PackedInt32Array = []
		
		for to_particle_index:int in range(
			start_particle_index, base_matrix.unconnected_matrix[to_id].size()
		):
			var to_particle: ParticleData.Particle = (
				base_matrix.unconnected_matrix[to_id][to_particle_index]
			)
			
			if to_particle in connected_particles:
				continue
				
			if !is_connection_particle(particle, to_particle):
				continue
			
			var connected_matrix := connect_particle_to_id(
				particle, to_particle, from_id, to_id, base_matrix
			)
			connected_matrices.push_back(connected_matrix)
			connected_particles.push_back(to_particle)
		
		if to_id == to_ids[0]:
			start_particle_index = 0
	
	return connected_matrices

func connect_particle_to_id(
	from_particle: ParticleData.Particle,
	to_particle: ParticleData.Particle,
	from_id: int,
	to_id: int,
	base_matrix: InteractionMatrix
) -> InteractionMatrix:


	var connected_matrix: InteractionMatrix = base_matrix.duplicate(true)
	connected_matrix.connect_asymmetric_interactions(
		from_id,
		to_id,
		from_particle,
		to_particle,
		ParticleData.base(to_particle),
		from_particle < 0
	)
	
	if ParticleData.general_can_convert(from_particle, to_particle):
		convert_general_path_from_id(
			from_id,
			from_particle,
			to_particle,
			connected_matrix,
			from_particle > 0
		)
	
	return connected_matrix

func connect_2_particles_to_ids(
	particleA: ParticleData.Particle,
	particleB: ParticleData.Particle,
	from_id: int,
	base_matrix: InteractionMatrix,
	to_ids: PackedInt32Array = range(base_matrix.matrix_size),
	start_particle_index: int = 0
) -> Array[InteractionMatrix]:
	
	var connected_matrices: Array[InteractionMatrix] = []
	
	if particleA != particleB:
		for particle_A_connected_matrix:InteractionMatrix in connect_particle_to_ids(
				particleA, from_id, base_matrix, to_ids
		):
			connected_matrices.append_array(
				connect_particle_to_ids(
					particleB, from_id, particle_A_connected_matrix, to_ids
				)
			)
		
		return connected_matrices
	
	var particle: ParticleData.Particle = particleA
	
	for to_idA:int in to_ids:
		if to_idA == from_id:
			continue

		var connected_particlesA: PackedInt32Array = []
		for to_particle_indexA:int in range(
			start_particle_index, base_matrix.unconnected_matrix[to_idA].size()
		):
			var to_particleA: ParticleData.Particle = (
				base_matrix.unconnected_matrix[to_idA][to_particle_indexA]
			)

			if to_particleA in connected_particlesA:
				continue
			
			if !is_connection_particle(particle, to_particleA):
				continue
			
			var particleA_connected_matrix := connect_particle_to_id(
				particle, to_particleA, from_id, to_idA, base_matrix
			)
			
			connected_particlesA.push_back(to_particleA)
			
			connected_matrices.append_array(
				connect_particle_to_ids(
					particle,
					from_id,
					particleA_connected_matrix,
					to_ids.slice(to_ids.find(to_idA)),
					to_particle_indexA
				)
			)
		
		if to_idA == to_ids[0]:
			start_particle_index = 0
	
	return connected_matrices

func connect_3_particles_to_ids(
	particleA: ParticleData.Particle,
	particleB: ParticleData.Particle,
	particleC: ParticleData.Particle,
	from_id: int,
	base_matrix: InteractionMatrix,
	to_ids: PackedInt32Array = range(base_matrix.matrix_size)
) -> Array[InteractionMatrix]:
	
	var connected_matrices: Array[InteractionMatrix] = []
	
	if !(particleA == particleB or particleB == particleC):
		for particleA_connected_matrix:InteractionMatrix in connect_particle_to_ids(
				particleA, from_id, base_matrix, to_ids
		):
			for particle_AB_connected_matrix:InteractionMatrix in connect_particle_to_ids(
				particleB, from_id, particleA_connected_matrix, to_ids
			):
				connected_matrices.append_array(
					connect_particle_to_ids(
						particleC,
						from_id,
						particle_AB_connected_matrix,
						to_ids
					)
				)
		
		return connected_matrices
	
	elif (particleA != particleB):
		for particleA_connected_matrix in connect_particle_to_ids(
			particleA, from_id, base_matrix
		):
			connected_matrices.append_array(
				connect_2_particles_to_ids(
					particleB,
					particleC,
					from_id,
					particleA_connected_matrix,
					to_ids
				)
			)
		
		return connected_matrices
	
	elif (particleB != particleC):
		for particleC_connected_matrix in connect_particle_to_ids(
			particleC, from_id, base_matrix, to_ids
		):
			connected_matrices.append_array(
				connect_2_particles_to_ids(
					particleA,
					particleB,
					from_id,
					particleC_connected_matrix,
					to_ids
				)
			)
		
		return connected_matrices
	
	
	var particle: ParticleData.Particle = particleA
	for to_idA:int in to_ids:
		if to_idA == from_id:
			continue

		var connected_particlesA: PackedInt32Array = []
		for to_particle_indexA:int in base_matrix.unconnected_matrix[to_idA].size():
			var to_particleA: ParticleData.Particle = (
				base_matrix.unconnected_matrix[to_idA][to_particle_indexA]
			)

			if to_particleA in connected_particlesA:
				continue
			
			if !is_connection_particle(particle, to_particleA):
				continue
			
			var particleA_connected_matrix := connect_particle_to_id(
				particle, to_particleA, from_id, to_idA, base_matrix
			)
			
			connected_particlesA.push_back(to_particleA)

			connected_matrices.append_array(
				connect_2_particles_to_ids(
					particleB,
					particleC,
					from_id,
					particleA_connected_matrix,
					to_ids.slice(to_ids.find(to_idA)),
					to_particle_indexA
				)
			)
	
	return connected_matrices

func self_connect(
	particleA:ParticleData.Particle,
	particleB:ParticleData.Particle,
	id:int,
	base_matrix:InteractionMatrix
) -> InteractionMatrix:
	return connect_particle_to_id(particleA, particleB, id, id, base_matrix)

func self_connect_ABC(
	particleA:ParticleData.Particle,
	particleB:ParticleData.Particle,
	particleC:ParticleData.Particle,
	is_AB_connection_particle:bool,
	is_BC_connection_particle:bool,
	is_AC_connection_particle:bool,
	id:int,
	base_matrix:InteractionMatrix,
	to_ids: PackedInt32Array = range(base_matrix.matrix_size)
) -> Array[InteractionMatrix]:

	var connected_matrices: Array[InteractionMatrix] = []
	
	if is_AB_connection_particle:
		for matrix:InteractionMatrix in connect_particle_to_ids(
			particleC, id, base_matrix, to_ids
		):
			connected_matrices.push_back(
				self_connect(particleB, particleC, id, matrix)
			)
	elif is_AC_connection_particle:
		for matrix:InteractionMatrix in connect_particle_to_ids(
			particleB, id, base_matrix, to_ids
		):
			connected_matrices.push_back(
				self_connect(particleA, particleC, id, matrix)
			)
	elif is_BC_connection_particle:
		for matrix:InteractionMatrix in connect_particle_to_ids(
			particleA, id, base_matrix, to_ids
		):
			connected_matrices.push_back(
				self_connect(particleB, particleC, id, matrix)
			)
	
	return connected_matrices

func has_connection_particle(
	to_particles: PackedInt32Array,
	from_particle: ParticleData.Particle
) -> bool:
	return ArrayFuncs.packed_int_any(
		to_particles,
		func(particle: ParticleData.Particle) -> bool:
			return is_connection_particle(from_particle, particle)
	)

func has_connection_particles(
	to_particles: PackedInt32Array,
	from_particles: PackedInt32Array
) -> bool:
	var has_particles: Array[bool]
	has_particles.resize(from_particles.size())
	has_particles.fill(false)
	
	for to_particle: ParticleData.Particle in to_particles:
		for i:int in from_particles.size():
			if !has_particles[i] and is_connection_particle(from_particles[i], to_particle):
				has_particles[i] = true
				break
		
		if has_particles.all(func(b:bool)->bool:return  b):
			return true
	
	return false

func is_connection_particle(
	from_particle: ParticleData.Particle,
	to_particle: ParticleData.Particle
) -> bool:
	if !ParticleData.has_shade(from_particle):
		return from_particle == to_particle
	
	if from_particle == -to_particle:
		return true
	
	return ParticleData.general_can_convert(from_particle, to_particle)

func interaction_in_particles(interaction: Array, particles: Array, interactions: Array = []) -> bool:
	if interaction in interactions:
		return false
	
	return interaction.all(
		func(particle: ParticleData.Particle) -> bool:
			return ParticleData.base(particle) in particles
	)

func get_useable_particle_interactions(useable_particles: Array) -> Dictionary:
	var useable_particle_interactions: Dictionary = {}
	
	for particle:ParticleData.Particle in useable_particles:
		if ParticleData.is_anti(particle) or particle in useable_particle_interactions.keys():
			continue
		
		useable_particle_interactions[particle] = ParticleData.PARTICLE_INTERACTIONS[particle].filter(
			interaction_in_particles.bind(useable_particles)
		)
	
	for general_particle in ParticleData.GENERAL_PARTICLES:
		if general_particle in useable_particles:
			continue
		
		for particle: ParticleData.Particle in useable_particle_interactions.keys():
			if particle not in ParticleData.general_particle_interaction_replacements[general_particle].keys():
				continue
			
			useable_particle_interactions[particle].append_array(
				ParticleData.general_particle_interaction_replacements[general_particle][particle].filter(
					interaction_in_particles.bind(
						useable_particles,
						useable_particle_interactions[particle]
					)
				)
			)
	
	if !(
		ParticleData.Particle.bright_quark in useable_particles
		or ParticleData.Particle.dark_quark in useable_particles
	) and ParticleData.Particle.W in useable_particles:
		useable_particle_interactions[ParticleData.Particle.W].append_array(
			ParticleData.general_quark_W_replacements.filter(
				interaction_in_particles.bind(useable_particles)
			)
		)
	
	
	return useable_particle_interactions

func create_base_interaction_matrix(initial_state: Array, final_state: Array) -> InteractionMatrix:
	var base_interaction_matrix := InteractionMatrix.new()
	for state_interaction:Array in initial_state:
		base_interaction_matrix.add_unconnected_interaction(state_interaction, StateLine.State.Initial)
	for state_interaction:Array in final_state:
		base_interaction_matrix.add_unconnected_interaction(state_interaction, StateLine.State.Final)
	return base_interaction_matrix

func get_hadron_particles(state_interactions: Array) -> Array:
	var hadron_particles : Array = []
	
	for state_interaction:Array in state_interactions:
		var is_hadron: bool = state_interaction.size() > 1
		if !is_hadron:
			continue
		hadron_particles += state_interaction
	
	return hadron_particles

func get_degrees_to_check(
	min_degree: int,
	max_degree: int,
	interaction_matrix: InteractionMatrix
) -> Array:
	var degrees_to_check: Array = []
	var initial_hadron_particles := get_hadron_particles(interaction_matrix.get_unconnected_state(StateLine.State.Initial))
	var final_hadron_particles := get_hadron_particles(interaction_matrix.get_unconnected_state(StateLine.State.Final))
	var number_of_state_particles := interaction_matrix.get_unconnected_state_particle_count(StateLine.State.Both)

	var number_of_unconnectable_particles: int = (
		number_of_state_particles - initial_hadron_particles.size() - final_hadron_particles.size() +
		get_non_shared_elements(initial_hadron_particles, final_hadron_particles).size()
	)

	min_degree = max(ceil(number_of_unconnectable_particles/3.0), min_degree)
	
	for degree in range(min_degree, max_degree+1):
		if (number_of_state_particles - degree) % 2 == 0:
			degrees_to_check.append(degree)

	return degrees_to_check

func get_print_time() -> String:
	return "time: " + str(Time.get_ticks_usec() - start_time) + " usec"

func get_connection_matrices(interaction_matrices: Array[InteractionMatrix]) -> Array[ConnectionMatrix]:
	var connection_matrices: Array[ConnectionMatrix] = []
	
	for interaction_matrix:InteractionMatrix in interaction_matrices:
		connection_matrices.push_back(interaction_matrix.get_connection_matrix())
	
	return connection_matrices

func get_non_shared_elements(array1: Array, array2: Array) -> Array:
	
	var non_shared : Array = []
	var array1_copy : Array = array1.duplicate()
	var array2_copy : Array = array2.duplicate()
	
	for element:Variant in array1:
		if element not in array2_copy:
			non_shared.append(element)
		else:
			array1_copy.erase(element)
			array2_copy.erase(element)
	
	for element:Variant in array2_copy:
		if element not in array1_copy:
			non_shared.append(element)
		else:
			array1_copy.erase(element)
	
	return non_shared

func print_time(count: int = -1) -> void:
	if !print_times:
		return
	
	if count == -1:
		print("Time: " + str(Time.get_ticks_usec() - start_time))
	else:
		print(count, "Time: ", get_print_time())

func is_out_particle(particle: ParticleData.Particle, state: StateLine.State) -> bool:
	return StateLine.state_factor[state] == sign(particle)

func is_connection_number_possible(unconnected_particle_count : int, interaction_count : int) -> bool:
	if unconnected_particle_count == 0:
		return interaction_count == 0
	
	if interaction_count == 1:
		return (
			unconnected_particle_count == INTERACTION_SIZE
			or unconnected_particle_count == 1
		)

	return unconnected_particle_count <= interaction_count * INTERACTION_SIZE

func are_quantum_numbers_valid(initial_state : Array, final_state : Array) -> bool:
	for quantum_number:ParticleData.QuantumNumber in ParticleData.QuantumNumber.values():
		if !is_equal_approx(
			calculate_quantum_sum(quantum_number, initial_state),
			calculate_quantum_sum(quantum_number, final_state)
		):
			if (
				quantum_number == ParticleData.QuantumNumber.charge or
				quantum_number == ParticleData.QuantumNumber.lepton or 
				quantum_number == ParticleData.QuantumNumber.quark
			):
				return false
	
	return true

func calculate_quantum_sum(quantum_number: ParticleData.QuantumNumber, state_interactions: Array) -> float:
	var quantum_sum: float = 0
	for state_interaction:Array in state_interactions:
		for particle:ParticleData.Particle in state_interaction:
			quantum_sum += ParticleData.quantum_number(particle, quantum_number)
	return quantum_sum
