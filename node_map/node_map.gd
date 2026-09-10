extends RefCounted

## 模块入口显式导出领域类型，不依赖全局类缓存和编辑器视图。
const NodeMapNode := preload("res://node_map/model/node_map_node.gd")
const SubgraphNode := preload("res://node_map/model/subgraph_node.gd")
const PortSpec := preload("res://node_map/model/port_spec.gd")
const ParameterSpec := preload("res://node_map/model/parameter_spec.gd")
const GraphInterface := preload("res://node_map/model/graph_interface.gd")
const NodeLink := preload("res://node_map/model/node_link.gd")
const NodeGraph := preload("res://node_map/model/node_graph.gd")
const NodeMapDocument := preload("res://node_map/model/node_map_document.gd")
const NodeDefinition := preload("res://node_map/registry/node_definition.gd")
const NodeRegistry := preload("res://node_map/registry/node_registry.gd")
const BuiltinNodes := preload("res://node_map/registry/builtin_nodes.gd")
const NodeMapCompiler := preload("res://node_map/compiler/node_map_compiler.gd")
const RuntimePackageWriter := preload("res://node_map/compiler/runtime_package_writer.gd")
const EngineCliBridge := preload("res://node_map/integration/engine_cli_bridge.gd")
const ProjectFileCodec := preload("res://node_map/serialization/project_file_codec.gd")
const NodeMapProjectFile := preload("res://node_map/serialization/node_map_project_file.gd")
