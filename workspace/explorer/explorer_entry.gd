@tool
extends RefCounted
class_name EditorExplorerEntry

const ENTRY_SCRIPT := preload("res://workspace/explorer/explorer_entry.gd")
const ID_PATTERN := "^[A-Za-z][A-Za-z0-9_.:-]*$"

## 通用 Explorer 的一个显示条目。
##
## 条目只保存显示层需要的稳定身份、标题、父子关系和显式搜索文本。metadata 对
## 显示框架保持不透明，数据源可用它保存自己的稳定引用，但 Explorer 不会解释、
## 搜索或修改其中的内容。

const ICON_HINT_GENERIC := "generic"
const ICON_HINT_CONTAINER := "container"
const ICON_HINT_DOCUMENT := "document"

var entry_id: String
var title: String
var parent_id: String
var is_container: bool
var icon_hint: String
var search_terms: Array
var metadata: Dictionary

func _init(
        p_entry_id: String = "",
        p_title: String = "",
        p_parent_id: String = "",
        p_is_container: bool = false,
        p_icon_hint: String = ICON_HINT_GENERIC,
        p_search_terms: Array = [],
        p_metadata: Dictionary = {},
) -> void:
    entry_id = p_entry_id
    title = p_title
    parent_id = p_parent_id
    is_container = p_is_container
    icon_hint = p_icon_hint
    search_terms = p_search_terms.duplicate()
    metadata = p_metadata.duplicate(true)

static func root(
        p_entry_id: String,
        p_title: String,
        p_search_terms: Array = [],
        p_metadata: Dictionary = {},
):
    return ENTRY_SCRIPT.new(
        p_entry_id, p_title, "", true,
        ICON_HINT_CONTAINER, p_search_terms, p_metadata,
    )

static func container(
        p_entry_id: String,
        p_title: String,
        p_parent_id: String,
        p_search_terms: Array = [],
        p_metadata: Dictionary = {},
        p_icon_hint: String = ICON_HINT_CONTAINER,
):
    return ENTRY_SCRIPT.new(
        p_entry_id, p_title, p_parent_id, true,
        p_icon_hint, p_search_terms, p_metadata,
    )

static func document(
        p_entry_id: String,
        p_title: String,
        p_parent_id: String,
        p_search_terms: Array = [],
        p_metadata: Dictionary = {},
        p_icon_hint: String = ICON_HINT_DOCUMENT,
):
    return ENTRY_SCRIPT.new(
        p_entry_id, p_title, p_parent_id, false,
        p_icon_hint, p_search_terms, p_metadata,
    )

func duplicate_entry():
    return ENTRY_SCRIPT.new(
        entry_id, title, parent_id, is_container,
        icon_hint, search_terms, metadata,
    )

func matches_query(query: String) -> bool:
    var normalized_query := query.strip_edges().to_lower()
    if normalized_query.is_empty() or title.to_lower().contains(normalized_query):
        return true
    for raw_term in search_terms:
        if str(raw_term).to_lower().contains(normalized_query):
            return true
    return false

func validate_self() -> Array:
    var errors: Array = []
    if not _is_valid_id(entry_id):
        errors.append("entry_id must match %s" % ID_PATTERN)
    if title.strip_edges().is_empty():
        errors.append("entry '%s' title must not be empty" % entry_id)
    if not parent_id.is_empty() and not _is_valid_id(parent_id):
        errors.append("entry '%s' parent_id must match %s" % [entry_id, ID_PATTERN])
    if icon_hint.strip_edges().is_empty():
        errors.append("entry '%s' icon_hint must not be empty" % entry_id)
    for index in range(search_terms.size()):
        if not search_terms[index] is String:
            errors.append("entry '%s' search_terms[%d] must be a string" % [entry_id, index])
    return errors

static func _is_valid_id(value: String) -> bool:
    var regex := RegEx.new()
    return regex.compile(ID_PATTERN) == OK and regex.search(value) != null
