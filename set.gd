## SOURCE : https://gist.github.com/NoodleSushi/3eb9cc08eb1d1c369bef308262804f1e

class_name Set extends RefCounted
## A custom implementation of a set data structure in GDScript.
##
## Usage Example:
## [codeblock]
## var mySet = Set.new([1, 2, 3])
## var otherSet = Set.new([2, 3, 4])
## 
## var differenceSet = mySet.difference(otherSet)
## print(differenceSet.elements())  # Output: [1]
## 
## mySet.intersection_update(otherSet)
## print(mySet.elements())  # Output: [2, 3]
## [/codeblock]


var _set := {}

## The constructor initializes the set with elements from the specified object,
## supporting various data types. Unsupported types trigger an assertion error.
func _init(obj: Variant = null) -> void:
	match typeof(obj):
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_COLOR_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, \
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
		TYPE_PACKED_STRING_ARRAY:
			for element in obj:
				add(element)
		TYPE_NIL: pass
		_:
			assert(false, "Type %s unsupported for Set objects" % [typeof(obj)])

## Adds an [param element] to the set.
func add(element: Variant) -> void:
	_set[element] = 0

## Clears all elements from the set.
func clear() -> void:
	_set.clear()

## Creates and returns a new [Set] containing the same elements as the current set.
func duplicate() -> Set:
	var new_set := Set.new()
	new_set._set = _set.duplicate()
	return new_set

# O(min(|self|, |set|))
## Returns a new [Set] containing elements that are present in the current set 
## but not in the provided [param set].
func difference(set: Set) -> Set:
	if set.hash() == self.hash():
		return Set.new()
	var out := self.duplicate()
	if set.size() > self.size():
		for element in self.elements():
			if set.has(element):
				out.erase(element)
	else:
		for element in set.elements():
			out.erase(element)
	return out

# O(min(|self|, |set|))
## Modifies the current [Set] to contain elements present in the current set\
## but not in the provided [param set].
func difference_update(set: Set) -> void:
	if set.hash() == self.hash():
		self.clear()
		return
	if set.size() > self.size():
		for element in self.elements():
			if set.has(element):
				self.erase(element)
	else:
		for element in set.elements():
			self.erase(element)

# O(min(|self|, |set|))
## Returns a new [Set] containing elements common to both the current set and 
## the provided [param set].
func intersection(set: Set) -> Set:
	if set.hash() == self.hash():
		return duplicate()
	var out := Set.new()
	if set.size() > self.size():
		for element in self.elements():
			if set.has(element):
				out.add(element)
	else:
		for element in set.elements():
			if self.has(element):
				out.add(element)
	return out

# O(min(|self|, |set|))
## Modifies the current set to contain only elements common to both the 
## current set and the provided [param set].
func intersection_update(set: Set) -> void:
	if set.hash() == self.hash():
		return
	var out := Set.new()
	if set.size() > self.size():
		for element in self.elements():
			if set.has(element):
				out.add(element)
	else:
		for element in set.elements():
			if self.has(element):
				out.add(element)
	self.clear()
	self._set = out._set

# O([1, min(|self|, |set|)])
## Returns [code]true[/code] if the sets have no elements in common;
## otherwise, returns [code]false[/code].
func isdisjoint(set: Set) -> bool:
	if set.size() > self.size():
		for element in self.elements():
			if set.has(element):
				return false
	else:
		for element in set.elements():
			if self.has(element):
				return false
	return true

# O([1, |self|])
## Returns [code]true[/code] if every element of the current set is present
## in the provided [param set]; otherwise, returns [code]false[/code].
func issubset(set: Set) -> bool:
	if set.size() < self.size():
		return false
	else:
		for element in self.elements():
			if !set.has(element):
				return false
	return true

# O([1, |set|])
## Returns [code]true[/code] if every element of the provided [param set]
## is present in the current set; otherwise, returns [code]false[/code].
func issuperset(set: Set) -> bool:
	if self.size() < set.size():
		return false
	else:
		for element in set.elements():
			if !self.has(element):
				return false
	return true

# O(|self|) ?
## Removes and returns an arbitrary element from the set.
func pop() -> Variant:
	assert(self.size() > 0)
	var element = self.elements()[randi() % self.size()]
	self.erase(element)
	return element

## Removes the specified [param element] from the set.
func erase(element: Variant) -> void:
	_set.erase(element)

# O(min(|self|, |set|))
## Returns a new [Set] containing elements that are present in either
## the current set or the provided [param set], but not in both.
func symmetric_difference(set: Set) -> Set:
	if set.hash() == self.hash():
		return Set.new()
	if set.size() > self.size():
		var out := set.duplicate()
		for element in self.elements():
			if set.has(element):
				out.remove(element)
		return out
	else:
		var out := self.duplicate()
		for element in set.elements():
			if self.has(element):
				out.remove(element)
		return out

# O(min(|self|, |set|))
## Modifies the current set to contain elements that are present in either
## the current set or the provided [param set], but not in both.
func symmetric_difference_update(set: Set) -> void:
	if set.size() > self.size():
		var temp := set.duplicate()
		for element in self.elements():
			if temp.has(element):
				temp.erase(element)
			else:
				temp.add(element)
		self._set = temp._set
	else:
		for element in set.elements():
			if self.has(element):
				self.erase(element)
			else:
				self.add(element)

# O(min(|self|, |set|))
## Returns a new [Set] containing all elements from both the current 
## set and the provided [param set].
func union(set: Set) -> Set:
	if set.size() > self.size():
		var out := set.duplicate()
		for element in self.elements():
			out.add(element)
		return out
	else:
		var out := self.duplicate()
		for element in set.elements():
			out.add(element)
		return out

# O(min(|self|, |set|))
## Modifies the current set to contain all elements from both the current set
## and the provided [param set].
func update(set: Set) -> void:
	if set.size() > self.size():
		var temp := set.duplicate()
		for element in self.elements():
			temp.add(element)
		self._dict = temp._dict
	else:
		var temp := self.duplicate()
		for element in set.elements():
			temp.add(element)
		self._dict = temp.dict

## Returns an [Array] containing all elements of the set.
func elements() -> Array:
	return _set.keys()

## Returns [code]true[/code] if the set contains the specified [param element];
## otherwise, returns [code]false[/code].
func has(element: Variant) -> bool:
	return _set.has(element)

## Returns the number of elements in the set.
func size() -> int:
	return _set.size()

## Returns a hash value for the set.
func hash() -> int:
	return _set.hash()
