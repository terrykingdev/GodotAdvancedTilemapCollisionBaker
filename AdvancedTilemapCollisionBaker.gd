@tool
extends StaticBody2D

## This script is used to help fix the issues caused by physics glitches you get on
## tiled maps when object can become stuck. It converts tiles into larger areas of
## CollisionShape2D or CollisionPolygon2D.
## By default it uses a Hybrid method which is to first convert areas into rectangular
## CollisionShape2D and then convert the remaining tiles to CollisionPolygon2D.
## Thanks to https://github.com/popcar2/GodotTilemapBaker for the initial idea which only handles
## rectangles. There did seem to be an issue with it working on some test maps I did but I'm using
## a different method.

## Your TileMap Node
@export var tilemap_nodepath: NodePath

## The tilemap layer to bake collisions on.
## You can bake for multiple layers by disabling delete_children_on_run and running multiple times.
@export var target_tiles_layer: int = 0

## The physics layer of the target layer to use
@export var physics_layer: int = 0

## Whether or not you want the children of this node to be deleted on run or not.
## Be careful with this!
@export var delete_children_on_run: bool = true

## A fake button to run the code. Bakes collisions and adds colliders as children to this node!
@export var run_script: bool = false : set = runCode

enum CollisionTypes {RECTANGLES,POLYGONS,HYBRID}
## Divide into rectangular strips or polygons. Hybrid is best of both.
@export var collision_type: CollisionTypes = CollisionTypes.HYBRID

enum ConvertRange {WHOLE_MAP,VIEWPOINT_ONLY}
## Convert the whole tilemap or only what's visible in the current viewport
@export var convert_range: ConvertRange = ConvertRange.WHOLE_MAP

enum RectangleDirection {HORIZONTAL,VERTICAL}
## For rectangular regions horizontal will prefer wider selections ideal for platformers
## Vertical will prefer longer vertical strips.
@export var rectangle_direction: RectangleDirection = RectangleDirection.HORIZONTAL

## Clear the current collisions
@export var clear: bool = false : set = clearAll

## Create a random colour for rectangles to easily distinguish them
@export var random_debug_collision_colours: bool = false

var tile_size
var tilemap_locations
var tile_map: TileMap

func _ready():
	runCode() # just for testing
	pass

func runCode(_fake_bool = null):
	if tilemap_nodepath.is_empty():
		print("Please set a Tilemap Nodepath")
		return
	if not get_node(tilemap_nodepath) is TileMap:
		print("Tilemap Nodepath is not a TileMap!")
		return
	
	tile_map = get_node(tilemap_nodepath)
	
	if delete_children_on_run:
		delete_children()
	
	tile_size = tile_map.tile_set.tile_size
	print("tile_size",tile_size)
	
	var viewport_origin=-get_viewport_transform().origin/get_viewport_transform().get_scale()
	var viewport_size = Vector2(get_viewport().size)/get_viewport_transform().get_scale()
	var visible_viewport={
		x1= viewport_origin.x,
		y1= viewport_origin.y,
		x2= viewport_origin.x+viewport_size.x,
		y2= viewport_origin.y+viewport_size.y
	}
	
	var polys_left=[]
	# Get all the tilemap cells
	tilemap_locations = tile_map.get_used_cells(target_tiles_layer)
	# Go backwards so we can easily delete items in the loop
	for tm in range(tilemap_locations.size()-1,-1,-1):
		var coords=tilemap_locations[tm]
		coords.x*=tile_size.x
		coords.y*=tile_size.y
		var skip=false
		if convert_range==ConvertRange.VIEWPOINT_ONLY:
			# Filter out those outside of the viewport
			if coords.x+tile_size.x<visible_viewport.x1 or coords.x>visible_viewport.x2 or coords.y+tile_size.y<visible_viewport.y1 or coords.y>visible_viewport.y2:
				tilemap_locations.remove_at(tm)
				skip=true
		if not skip:
			# Filter out those without any collision polys
			var tiledata=tile_map.get_cell_tile_data(target_tiles_layer, tilemap_locations[tm])
			var poly_count=tiledata.get_collision_polygons_count(physics_layer)
			if poly_count==0:
				tilemap_locations.remove_at(tm)
			else:
				if collision_type==CollisionTypes.RECTANGLES or collision_type==CollisionTypes.HYBRID:
					var collision_polygon_points=tiledata.get_collision_polygon_points(physics_layer,0)
					var is_full_block=true
					# Solid block must have 4 points
					if collision_polygon_points.size()==4:
						# Assume if all points are on the tile boundary that's it's all four corners
						for i in range(4):
							if abs(collision_polygon_points[i].x)!=tile_size.x/2 or abs(collision_polygon_points[i].y)!=tile_size.y/2:
								is_full_block=false
								break
					else:
						is_full_block=false
					if not is_full_block:
						polys_left.append(tilemap_locations[tm])
						tilemap_locations.remove_at(tm)
			
	if tilemap_locations.size() == 0:
		print("Empty tilemap, ensure your physics layer has your polys defined")
		return
		
	if collision_type==CollisionTypes.RECTANGLES:
		divideIntoRectangles()
	elif collision_type==CollisionTypes.POLYGONS:
		divideIntoPolygons()
	elif collision_type==CollisionTypes.HYBRID:
		divideIntoRectangles()
		# Now process all the cells that weren't rectangles
		tilemap_locations=polys_left
		divideIntoPolygons()
		
func sortVectorsByXY(a, b):
	if a.y < b.y:
		return true
	if a.y == b.y:
		if a.x < b.x:
			return true
	return false

func sortVectorsByYX(a, b):
	if a.x < b.x:
		return true
	if a.x == b.x:
		if a.y < b.y:
			return true
	return false
		
func divideIntoRectangles():
	if rectangle_direction==RectangleDirection.HORIZONTAL:
		tilemap_locations.sort_custom(sortVectorsByXY)
		divideIntoRectanglesHorizontal()
	else:
		tilemap_locations.sort_custom(sortVectorsByYX)
		divideIntoRectanglesVertical()
		
func divideIntoRectanglesHorizontal():
	var results=[]
	var start_x
	var end_x
	var look_for_y
	while tilemap_locations.size()>0:
		results.clear()
		var tile1=tilemap_locations[0]
		start_x=tile1.x
		look_for_y=tile1.y+1
		tilemap_locations.remove_at(0)
		results.append(tile1)
		while tilemap_locations.size()>0:
			var tile2=tilemap_locations[0]
			if tile2.x-tile1.x==1 and tile2.y==tile1.y:
				results.append(tile2)
				tilemap_locations.remove_at(0)
				tile1=tile2
			else:
				break
		end_x=tile1.x
			
		var look_for_x
		var start_y=look_for_y
		var looking_down=true
		while looking_down:
			var first_in_block=-1
			look_for_x=start_x
			var i=0
			var found_block=false
			# Need to add in some optimzation to avoid checking earlier y values
			for tm in tilemap_locations:
				if tm.y==look_for_y:
					if tm.x==start_x and start_x==end_x and first_in_block==-1:
						first_in_block=i
						found_block=true
						break
					elif tm.x==look_for_x:
						if first_in_block==-1:
							first_in_block=i
						elif tm.x==end_x:
							found_block=true
							break
						look_for_x+=1
				elif tm.y>look_for_y:
					looking_down=false
					break	
				i+=1
			if found_block:
				for delete in range(end_x-start_x+1):
					tilemap_locations.remove_at(first_in_block)
				look_for_y+=1
			else:
				looking_down=false
		var collider=createCollisionShape(Vector2(start_x,start_y-1),end_x-start_x+1,look_for_y-start_y+1)
		add_child(collider, true)
		if random_debug_collision_colours:
			collider.debug_color = Color(randf(),randf(),randf(),0.4)
		collider.owner = get_tree().edited_scene_root		

func divideIntoRectanglesVertical():
	var results=[]
	var start_y
	var end_y
	var look_for_x
	while tilemap_locations.size()>0:
		results.clear()
		var tile1=tilemap_locations[0]
		start_y=tile1.y
		look_for_x=tile1.x+1
		tilemap_locations.remove_at(0)
		results.append(tile1)
		while tilemap_locations.size()>0:
			var tile2=tilemap_locations[0]
			if tile2.y-tile1.y==1 and tile2.x==tile1.x:
				results.append(tile2)
				tilemap_locations.remove_at(0)
				tile1=tile2
			else:
				break
		end_y=tile1.y
			
		var look_for_y
		var start_x=look_for_x
		var looking_down=true
		while looking_down:
			var first_in_block=-1
			look_for_y=start_y
			var i=0
			var found_block=false
			for tm in tilemap_locations:
				if tm.x==look_for_x:
					if tm.y==start_y and start_y==end_y and first_in_block==-1:
						first_in_block=i
						found_block=true
						break
					elif tm.y==look_for_y:
						if first_in_block==-1:
							first_in_block=i
						elif tm.y==end_y:
							found_block=true
							break
						look_for_y+=1
				elif tm.x>look_for_x:
					looking_down=false
					break	
				i+=1
			if found_block:
				for delete in range(end_y-start_y+1):
					tilemap_locations.remove_at(first_in_block)
				look_for_x+=1
			else:
				looking_down=false
		var collider=createCollisionShape(Vector2(start_x-1,start_y),look_for_x-start_x+1,end_y-start_y+1)
		add_child(collider, true)
		if random_debug_collision_colours:
			collider.debug_color = Color(randf(),randf(),randf(),0.4)
		collider.owner = get_tree().edited_scene_root		
	
func divideIntoPolygons():
	while tilemap_locations.size()!=0:
		var tile1=getTileVertices(tilemap_locations[0])
		tilemap_locations.remove_at(0)
	
		while tilemap_locations.size()!=0:
			var no_change=true
			for index in range(tilemap_locations.size()-1,-1,-1):
				var tile2=getTileVertices(tilemap_locations[index])
				var merged=mergeVertices(tile1,tile2)
				var merged_size=merged.size()
				if merged_size==1:
					tile1=merged[0]
					tilemap_locations.remove_at(index)
					no_change=false
			if no_change:
				break
		createCollisionPolygon2D(tile1)
			
func mergeVertices(v1,v2) -> Array[PackedVector2Array]:
	var merged_vertices=Geometry2D.merge_polygons(v1,v2) 
	return merged_vertices	

func getTileVertices(tile) -> PackedVector2Array:
	var tiledata=tile_map.get_cell_tile_data(target_tiles_layer, tile)
	var poly_count=tiledata.get_collision_polygons_count(physics_layer)	
	var pv2a=tiledata.get_collision_polygon_points(physics_layer,0)
	var offset = Vector2(tile.x*tile_size.x,tile.y*tile_size.y)
	offset+=Vector2(tile_size.x/2,tile_size.y/2)
	for point in range(0,pv2a.size()):
		pv2a[point]+=offset
	return pv2a

func createCollisionShape(pos,width,height) -> CollisionShape2D:
	pos.x=pos.x*tile_size.x
	pos.y=pos.y*tile_size.y
	pos.x+=width*tile_size.x/2
	pos.y+=height*tile_size.y/2
	var collisionShape = CollisionShape2D.new()
	var rectangleShape = RectangleShape2D.new()
	
	rectangleShape.size = Vector2(width*tile_size.x,height*tile_size.y)
	collisionShape.set_shape(rectangleShape)
	collisionShape.position = pos
	
	return collisionShape
		
func createCollisionPolygon2D(vertices) -> CollisionPolygon2D:
	var collisionPolygon = CollisionPolygon2D.new()
	collisionPolygon.build_mode=CollisionPolygon2D.BUILD_SOLIDS
	collisionPolygon.polygon = vertices
	add_child(collisionPolygon,true)
	collisionPolygon.owner=get_tree().edited_scene_root		
	return collisionPolygon
	
func delete_children():
	for child in get_children():
		child.queue_free()

func clearAll(_fake_bool = null):
	delete_children()
