extends SceneTree

func _init() -> void:
    for class_name_value in ["GraphEdit", "GraphNode", "GraphElement"]:
        print("=== %s ===" % class_name_value)
        for method in ClassDB.class_get_method_list(class_name_value):
            print("METHOD ", method.get("name", ""), " ", method.get("args", []))
        for property in ClassDB.class_get_property_list(class_name_value):
            print("PROPERTY ", property.get("name", ""), " type=", property.get("type", -1))
    quit(0)
