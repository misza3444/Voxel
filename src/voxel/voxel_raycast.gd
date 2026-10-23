extends RefCounted
class_name VFVoxelRaycast
## Grid DDA, independent of delayed collision/render meshes. Ties skip zero-volume touches.

static func cast(world: VFWorldManager, origin: Vector3, direction: Vector3, reach: float = 6.0) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000001 or not is_finite(reach) or reach <= 0 or reach > 256:
		return {}
	var ray := direction.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(int(signf(ray.x)), int(signf(ray.y)), int(signf(ray.z)))
	var delta := Vector3(INF, INF, INF)
	var next := Vector3(INF, INF, INF)
	for axis in range(3):
		if absf(ray[axis]) > 0.0000001:
			delta[axis] = absf(1.0 / ray[axis])
			var boundary := float(cell[axis] + (1 if step[axis] > 0 else 0))
			next[axis] = maxf(0.0, (boundary - origin[axis]) / ray[axis])
	var distance := 0.0
	var normal := Vector3i.ZERO
	for iteration in range(ceili(reach * 3.0) + 4):
		if world.get_block_global(cell) != VFChunkData.Block.AIR:
			return {"block": cell, "normal": normal, "place": cell + normal, "distance": distance}
		distance = minf(next.x, minf(next.y, next.z))
		if distance > reach: return {}
		normal = Vector3i.ZERO
		for axis in range(3):
			if next[axis] <= distance + 0.0000001:
				cell[axis] += step[axis]
				next[axis] += delta[axis]
				if normal == Vector3i.ZERO: normal[axis] = -step[axis]
	return {}
