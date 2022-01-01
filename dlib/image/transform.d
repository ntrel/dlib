/*
Copyright (c) 2016-2022 Timur Gafarov

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

/**
 * Geometric ransformations of images
 *
 * Copyright: Timur Gafarov 2016-2022.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov
 */
module dlib.image.transform;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.utils;

import dlib.image.image;
import dlib.image.color;

/// Tranforms an image with affine 3x3 matrix
SuperImage affineTransformImage(SuperImage img, SuperImage outp, Matrix3x3f m)
{
    SuperImage res;
    if (outp)
        res = outp;
    else
        res = img.createSameFormat(img.width, img.height);

    foreach(y; 0..res.height)
    foreach(x; 0..res.width)
    {
        Vector2f v1 = Vector2f(x, y).affineTransform2D(m);
        res[x, y] = bilinearPixel(img, v1.x, v1.y);
    }

    return res;
}

/// ditto
SuperImage affineTransformImage(SuperImage img, Matrix3x3f m)
{
    return affineTransformImage(img, null, m);
}

/// Translates an image (positive x goes right, positive y goes down)
SuperImage translateImage(SuperImage img, SuperImage outp, Vector2f t)
{
    Matrix3x3f m = translationMatrix2D(-t);
    return affineTransformImage(img, outp, m);
}

/// ditto
SuperImage translateImage(SuperImage img, Vector2f t)
{
    return translateImage(img, null, t);
}

/// Rotates an image clockwise around its center. Angle is in degrees.
SuperImage rotateImage(SuperImage img, SuperImage outp, float angle)
{
    Vector2f center = Vector2f(img.width, img.height) * 0.5f;
    Matrix3x3f m =
      translationMatrix2D(center) *
      rotationMatrix2D(degtorad(angle)) *
      translationMatrix2D(-center);
    return affineTransformImage(img, outp, m);
}

/// ditto
SuperImage rotateImage(SuperImage img, float angle)
{
    return rotateImage(img, null, angle);
}

/// Scales an image
SuperImage scaleImage(SuperImage img, SuperImage outp, Vector2f s)
{
    Matrix3x3f m = scaleMatrix2D(Vector2f(1, 1) / s);
    return affineTransformImage(img, outp, m);
}

/// ditto
SuperImage scaleImage(SuperImage img, Vector2f s)
{
    return scaleImage(img, null, s);
}

/// Uniformly scales an image
SuperImage scaleImage(SuperImage img, SuperImage outp, float s)
{
    float sinv = 1.0f / s;
    Matrix3x3f m = scaleMatrix2D(Vector2f(sinv, sinv));
    return affineTransformImage(img, outp, m);
}

/// ditto
SuperImage scaleImage(SuperImage img, float s)
{
    return scaleImage(img, null, s);
}
