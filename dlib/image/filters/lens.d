/*
Copyright (c) 2014-2019 Timur Gafarov

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

module dlib.image.filters.lens;

import std.math;
import dlib.image.image;

SuperImage lensDistortion(
    SuperImage img,
    float strength,
    float zoom,
    bool interpolation = true)
{
    return lensDistortion(img, null, strength, zoom, interpolation);
}

SuperImage lensDistortion(
    SuperImage img,
    SuperImage outp,
    float strength,
    float zoom,
    bool interpolation = true)
{
    SuperImage res;
    if (outp)
        res = outp;
    else
        res = img.dup;

    float halfWidth = cast(float)img.width / 2.0f;
    float halfHeight = cast(float)img.height / 2.0f;

    float correctionRadius = sqrt(cast(float)(img.width ^^ 2 + img.height ^^ 2)) / strength;

    foreach(y; 0..img.height)
    foreach(x; 0..img.width)
    {
        float newX = x - halfWidth;
        float newY = y - halfHeight;

        float distance = sqrt(newX ^^ 2 + newY ^^ 2);
        float r = distance / correctionRadius;

        float theta;
        if (r == 0)
            theta = 1;
        else
            theta = atan(r) / r;

        float sourceX = (halfWidth + theta * newX * zoom);
        float sourceY = (halfHeight + theta * newY * zoom);

        if (interpolation)
            res[x, y] = img.bilinearPixel(sourceX, sourceY);
        else
            res[x, y] = img[cast(int)sourceX, cast(int)sourceY];
    }

    return res;
}
