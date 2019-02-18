// Unit tests for PriorityQueue binary min-heap.

import "../test_framework" for TestRunner
import "../../src/wren/core/priority_queue" for PriorityQueue

TestRunner.describe("PriorityQueue Min-Heap Operations", Fn.new {
  TestRunner.test("initial state is empty", Fn.new {
    var pq = PriorityQueue.new()
    TestRunner.assertTrue(pq.isEmpty, "New queue should be empty")
    TestRunner.assertEqual(0, pq.count, "New queue count should be 0")
    TestRunner.assertNull(pq.peek(), "Peek on empty queue should return null")
    TestRunner.assertNull(pq.pop(), "Pop on empty queue should return null")
  })

  TestRunner.test("single element insertion and removal", Fn.new {
    var pq = PriorityQueue.new()
    pq.push("task-1", 10)
    TestRunner.assertFalse(pq.isEmpty, "Queue should not be empty")
    TestRunner.assertEqual(1, pq.count, "Queue count should be 1")
    TestRunner.assertEqual("task-1", pq.peek(), "Peek should return task-1")
    TestRunner.assertEqual(10, pq.peekPriority(), "Peek priority should return 10")
    var popped = pq.pop()
    TestRunner.assertEqual("task-1", popped, "Pop should return task-1")
    TestRunner.assertTrue(pq.isEmpty, "Queue should be empty after pop")
  })

  TestRunner.test("ordered retrieval by priority", Fn.new {
    var pq = PriorityQueue.new()
    pq.push("c", 30)
    pq.push("a", 10)
    pq.push("d", 40)
    pq.push("b", 20)

    TestRunner.assertEqual(4, pq.count, "Count should be 4")
    TestRunner.assertEqual("a", pq.pop(), "First pop should be lowest priority element 'a'")
    TestRunner.assertEqual("b", pq.pop(), "Second pop should be 'b'")
    TestRunner.assertEqual("c", pq.pop(), "Third pop should be 'c'")
    TestRunner.assertEqual("d", pq.pop(), "Fourth pop should be 'd'")
    TestRunner.assertTrue(pq.isEmpty, "Queue should be empty")
  })

  TestRunner.test("duplicate priority handling", Fn.new {
    var pq = PriorityQueue.new()
    pq.push("job-1", 5)
    pq.push("job-2", 5)
    pq.push("job-3", 1)

    TestRunner.assertEqual("job-3", pq.pop(), "Lowest priority job-3 should pop first")
    var item2 = pq.pop()
    var item3 = pq.pop()
    TestRunner.assertTrue((item2 == "job-1" && item3 == "job-2") || (item2 == "job-2" && item3 == "job-1"), "Both duplicate items should be popped")
    TestRunner.assertTrue(pq.isEmpty, "Queue should be empty")
  })

  TestRunner.test("queue clear resets all state", Fn.new {
    var pq = PriorityQueue.new()
    pq.push("x", 1)
    pq.push("y", 2)
    pq.clear()
    TestRunner.assertTrue(pq.isEmpty, "Queue should be empty after clear")
    TestRunner.assertEqual(0, pq.count, "Count should be 0 after clear")
  })
})
