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

module dlib.math.interpolation;

private
{
    import std.math;
}

T interpLinear(T) (T a, T b, float t)
{
    return a + (b - a) * t;
}

alias lerp = interpLinear;

T interpNearest(T) (T x, T y, float t)
{
    if (t < 0.5f)
        return x;
    else
        return y;
}

T interpCatmullRom(T) (T p0, T p1, T p2, T p3, float t)
{
    return 0.5 * ((2 * p1) +
                  (-p0 + p2) * t +
                  (2 * p0 - 5 * p1 + 4 * p2 - p3) * t^^2 +
                  (-p0 + 3 * p1 - 3 * p2 + p3) * t^^3);
}

T interpCatmullRomDerivative(T) (T p0, T p1, T p2, T p3, float t)
{
    return 0.5 * ((2 * p1) +
                  (-p0 + p2) +
                  2 * (2 * p0 - 5 * p1 + 4 * p2 - p3) * t +
                  3 * (-p0 + 3 * p1 - 3 * p2 + p3) * t^^2);
}

T interpHermite(T) (T x, T tx, T y, T ty, float t)
{
    T h1 = 2 * t^^3 - 3 * t^^2 + 1;
    T h2 = -2* t^^3 + 3 * t^^2;
    T h3 = t^^3 - 2 * t^^2 + t;
    T h4 = t^^3 - t^^2;
    return h1 * x + h3 * tx + h2 * y + h4 * ty;
}
