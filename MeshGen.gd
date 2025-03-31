@tool
extends Node3D


@export var update = false
@export_range (0,10) var frequency = 0.001
@export_range (0,10) var amplitude = 0.5
@export_range(0,10) var amplifier = 1.0
@export_range(0,10) var scale_noise = 1.0
#@export_range(0,10) var lacunarity = 1.0
@export var octaves = 2
@export var chunk_size = 16
@export var render_distance = 3
var chunks = {}
var noise = FastNoiseLite.new()
var thread
var semaphore
var chunk_queue = []
var mut
var prev_player_chunk_x = -1
var prev_player_chunk_z = -1
var player_x
var player_z
var player_chunk_x
var player_chunk_z
var exit_thread = false

var rng = RandomNumberGenerator.new()

# Called when the node enters the scene tree for the first time.
func _ready():
	noise.seed = 10
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	#noise.fractal_lacunarity = lacunarity
	#noise.fractal_octaves = octaves
	#noise.frequency = frequency
	#noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	mut = Mutex.new()
	semaphore = Semaphore.new()
	thread = Thread.new()
	thread.start(chunk_generation_thread)
	
	
#Gets local chunk coordinate (Chunks make up their own grid, one chunk in one unit)
func get_chunk_coord(player_coord):
	return floor(player_coord/chunk_size)

#Thread for generating chunk mesh
func chunk_generation_thread():
	while true:
		semaphore.wait()
		
		mut.lock()
		var key_add = chunk_queue.pop_front() 
		var should_exit = exit_thread
		mut.unlock()

		if should_exit:
			break

		if(key_add):
			var chunk_coord = key_add.split(",")
			var x = int(chunk_coord[0])
			var z = int(chunk_coord[1])
			var chunk_mesh = gen_chunk(x, z)
			var chunk = MeshInstance3D.new()
			chunk.material_override = preload("res://terrain.material")
			call_deferred("done_gen", chunk, key_add, chunk_mesh)


#Send mesh info back to main thread
func done_gen(chunk, key_add, chunk_mesh):
	chunk.mesh = chunk_mesh
	chunk.create_trimesh_collision()
	add_child(chunk)
	chunks[key_add] = chunk
	remove_chunks()


func remove_chunks():
# Iterate through the loaded chunks and check if they are out of range
	for key in chunks.keys():
		var chunk_coord = key.split(",")
		var x = int(chunk_coord[0])
		var z = int(chunk_coord[1])

	# Check if the chunk is outside the render distance
		if abs(x - player_chunk_x) > render_distance or abs(z - player_chunk_z) > render_distance:
			remove_child(chunks[key])
			chunks.erase(key)



func update_chunks():
	

	#Get player x and z in the world
	player_x = self.get_parent().get_node("Player").position.x
	player_z = self.get_parent().get_node("Player").position.z

	player_chunk_x = get_chunk_coord(player_x)
	player_chunk_z = get_chunk_coord(player_z)

	# Iterate through the loaded chunks and check if they are out of range

	
	if player_chunk_x != prev_player_chunk_x or player_chunk_z != prev_player_chunk_z:
		# Update previous player chunk coordinates
		prev_player_chunk_x = player_chunk_x
		prev_player_chunk_z = player_chunk_z


	#Loop over chunk while also checking outside of chunk
		for x in range(player_chunk_x - render_distance, player_chunk_x + render_distance):
			for z in range(player_chunk_z - render_distance, player_chunk_z + render_distance):
				var key = str(x) + "," + str(z)	
				if not chunks.has(key) and not chunk_queue.has(key):
					mut.lock()
					chunk_queue.append(key)
					mut.unlock()
					semaphore.post()


func gen_noise(global_x, global_z):

	var y = 0.0
	var tempFreq = frequency
	var tempAmplitude = amplitude

	for o in range(octaves):
		y += noise.get_noise_2d((global_x * tempFreq)/scale_noise, (global_z * tempFreq)/scale_noise) * tempAmplitude
		tempAmplitude/=2
		tempFreq*=2	


	if(y >= 0.0):
		y = pow(y, amplifier)	

	
	return y


func gen_chunk(chunk_x, chunk_z):
	
	#Declare new ArrayMesh and verticies and triangles(indicies)
	var a_mesh = ArrayMesh.new()
	var verticies = PackedVector3Array()
	var indicies = PackedInt32Array()

	#6 because we need 6 indicies for each square
	indicies.resize(chunk_size * chunk_size * 6)

	
	#Get Verticies and indicies
	for x in range(chunk_size + 1):
		for z in range(chunk_size + 1):
			
		#	var y = 0.0

			var global_x = x + chunk_x * chunk_size
			var global_z = z + chunk_z * chunk_size

			var altitude = gen_noise(global_x, global_z)
		#	var spline_points = PackedVector2Array([Vector2(-1.0, 0.0), Vector2(0.3, 20.0), Vector2(0.5, 70.0), Vector2(1.0, 70.0)])

		#	for i in range(len(spline_points) - 1):
		#		if(spline_points[i].x <= altitude and altitude <= spline_points[i+1].x):

		#			var t = (altitude - spline_points[i].x) / (spline_points[i + 1].x - spline_points[i].x)
		#			y = lerp(spline_points[i], spline_points[i + 1], t)



			#print(y.y)

			#Set the verticies			
			var vert = Vector3(global_x, altitude, global_z)
			verticies.append(vert)
			

	#Calculate indicies. vert and x used to offset
	var vert = 0
	var index = 0
	for x in range(chunk_size):
		for z in range(chunk_size):
			
			#First triangle
			indicies[index + 0] = vert + x + 0;
			indicies[index + 1] = vert + chunk_size + 1 + x
			indicies[index + 2] = vert + 1 + x

			#Second triangle
			indicies[index + 3] = vert + 1 + x
			indicies[index + 4] = vert + chunk_size + 1 + x
			indicies[index + 5] = vert + chunk_size + 2 + x

			vert += 1
			index += 6


	
	#Use surface tool to generate normals easily
	var surftool = SurfaceTool.new()
	surftool.begin(Mesh.PRIMITIVE_TRIANGLES)

	#This makes the normals flat to give the low poly look
	surftool.set_smooth_group(-1)
	
	for i in range(verticies.size()):
		surftool.add_vertex(verticies[i])
	for i in indicies:
		surftool.add_index(i)

	
	surftool.generate_normals()
	a_mesh = surftool.commit()

	return a_mesh


func _exit_tree():

	mut.lock()
	exit_thread = true # Protect with Mutex.
	mut.unlock()
	# Unblock by posting.
	semaphore.post()
	# Wait until it exits.
	thread.wait_to_finish()


#Change this to update player position with signal instead of every frame
func _process(_delta):
	update_chunks()	
