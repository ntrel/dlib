/*
Copyright (c) 2011-2019 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dlib.container.stack;

private
{
    import dlib.container.linkedlist;
}

public:

/**
 * Stack implementation based on LinkedList.
 */
struct Stack(T)
{
    private LinkedList!(T, true) list;

    public:
    /**
     * Push element to stack.
     */
    void push(T v)
    {
        list.insertBeginning(v);
    }

    /**
     * Pop top element out.
     * Returns: Removed element.
     * Throws: Exception on underflow.
     */
    T pop()
    {
        if (empty)
            throw new Exception("Stack!(T): underflow");

        T res = list.head.datum;
        list.removeBeginning();
        return res;
    }

    /**
     * Top stack element.
     * Note: Stack must be non-empty.
     */
    T top()
    {
        return list.head.datum;
    }

    T* topPtr()
    {
        return &(list.head.datum);
    }

    /**
     * Check if stack has no elements.
     */
    @property bool empty()
    {
        return (list.head is null);
    }

    /**
     * Free memory allocated by Stack.
     */
    void free()
    {
        list.free();
    }
}

///
unittest
{
    import std.exception : assertThrown;

    Stack!int s;
    assertThrown(s.pop());
    s.push(100);
    s.push(3);
    s.push(76);
    assert(s.top() == 76);
    assert(s.pop() == 76);
    assert(s.pop() == 3);
    assert(s.pop() == 100);
    s.free();
}
