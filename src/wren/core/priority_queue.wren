// Binary min-heap priority queue implementation in Wren.
// Used for fiber scheduling, task queues, and durable timer dispatch.
// Elements with lower priority numerical values are dequeued first.

class HeapNode {
  construct new(item, priority) {
    _item = item
    _priority = priority
  }

  item { _item }
  priority { _priority }

  toString { "HeapNode(priority: %(_priority), item: %(_item))" }
}

class PriorityQueue {
  construct new() {
    _heap = []
  }

  count { _heap.count }
  isEmpty { _heap.count == 0 }

  // Inserts an item with an associated numeric priority.
  // Time complexity: O(log N)
  push(item, priority) {
    var node = HeapNode.new(item, priority)
    _heap.add(node)
    _siftUp(_heap.count - 1)
  }

  // Returns the item with the lowest priority value without removing it.
  // Time complexity: O(1)
  peek() {
    if (isEmpty) return null
    return _heap[0].item
  }

  // Returns the lowest priority value without removing the item.
  peekPriority() {
    if (isEmpty) return null
    return _heap[0].priority
  }

  // Removes and returns the item with the lowest priority value.
  // Time complexity: O(log N)
  pop() {
    if (isEmpty) return null
    var top = _heap[0].item
    var last = _heap.removeAt(-1)
    if (_heap.count > 0) {
      _heap[0] = last
      _siftDown(0)
    }
    return top
  }

  // Clears all elements from the priority queue.
  clear() {
    _heap.clear()
  }

  // Internal helper to restore min-heap invariant upward.
  _siftUp(index) {
    var parent = ((index - 1) / 2).floor
    while (index > 0 && _heap[index].priority < _heap[parent].priority) {
      _swap(index, parent)
      index = parent
      parent = ((index - 1) / 2).floor
    }
  }

  // Internal helper to restore min-heap invariant downward.
  _siftDown(index) {
    var length = _heap.count
    while (true) {
      var smallest = index
      var left = 2 * index + 1
      var right = 2 * index + 2

      if (left < length && _heap[left].priority < _heap[smallest].priority) {
        smallest = left
      }
      if (right < length && _heap[right].priority < _heap[smallest].priority) {
        smallest = right
      }

      if (smallest != index) {
        _swap(index, smallest)
        index = smallest
      } else {
        break
      }
    }
  }

  _swap(i, j) {
    var temp = _heap[i]
    _heap[i] = _heap[j]
    _heap[j] = temp
  }
}
