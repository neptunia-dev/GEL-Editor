extends "res://node_map/model/port_spec.gd"

## 只读查询投影的来源定位；接口本身不写入快照。
var interface_id: String = ""
var boundary_node_id: String = ""
var boundary_port_id: String = ""

func clone_snapshot():
	var copy = super.clone_snapshot()
	copy.interface_id = interface_id
	copy.boundary_node_id = boundary_node_id
	copy.boundary_port_id = boundary_port_id
	return copy
