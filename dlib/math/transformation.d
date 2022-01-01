/*
Copyright (c) 2013-2022 Timur Gafarov, Martin Cejp

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
 * Matrix-based geometric transformations
 * 
 * Copyright: Timur Gafarov 2013-2022.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov
 */
module dlib.math.transformation;

import std.math;

import dlib.math.utils;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;

/**
 * Setup a rotation matrix, given Euler angles in radians
 */
Matrix!(T,4) fromEuler(T) (Vector!(T,3) v)
{
    auto res = Matrix!(T,4).identity;

    T cx = cos(v.x);
    T sx = sin(v.x);
    T cy = cos(v.y);
    T sy = sin(v.y);
    T cz = cos(v.z);
    T sz = sin(v.z);

    T sxsy = sx * sy;
    T cxsy = cx * sy;

    res.a11 =  (cy * cz);
    res.a12 =  (sxsy * cz) + (cx * sz);
    res.a13 = -(cxsy * cz) + (sx * sz);

    res.a21 = -(cy * sz);
    res.a22 = -(sxsy * sz) + (cx * cz);
    res.a23 =  (cxsy * sz) + (sx * cz);

    res.a31 =  (sy);
    res.a32 = -(sx * cy);
    res.a33 =  (cx * cy);

    return res;
}

/**
 * Setup the Euler angles in radians, given a rotation matrix
 */
Vector!(T,3) toEuler(T) (Matrix!(T,4) m)
do
{
    Vector!(T,3) v;

    v.y = asin(m.a31);

    T cy = cos(v.y);
    T oneOverCosY = 1.0 / cy;

    if (fabs(cy) > 0.001)
    {
        v.x = atan2(-m.a32 * oneOverCosY, m.a33 * oneOverCosY);
        v.z = atan2(-m.a21 * oneOverCosY, m.a11 * oneOverCosY);
    }
    else
    {
        v.x = 0.0;
        v.z = atan2(m.a12, m.a22);
    }

    return v;
}

/**
 * Right vector of the matrix
 */
Vector!(T,3) right(T) (Matrix!(T,4) m)
do
{
    return Vector!(T,3)(m.a11, m.a21, m.a31);
}

/**
 * Up vector of the matrix
 */
Vector!(T,3) up(T) (Matrix!(T,4) m)
do
{
    return Vector!(T,3)(m.a12, m.a22, m.a32);
}

/**
 * Forward vector of the matrix
 */
Vector!(T,3) forward(T) (Matrix!(T,4) m)
do
{
    return Vector!(T,3)(m.a13, m.a23, m.a33);
}

/**
 * Translation vector of the matrix
 */
Vector!(T,3) translation(T) (Matrix!(T,4) m)
do
{
    return Vector!(T,3)(m.a14, m.a24, m.a34);
}

///
unittest
{
    Matrix4f tm = matrixf(
        1.0f, 0.0f, 0.0f, 3.0f,
        0.0f, 1.0f, 0.0f, 5.0f,
        0.0f, 0.0f, 1.0f, 2.5f,
        0.0f, 0.0f, 0.0f, 1.0f,
    );
    
    Vector3f t = translation(tm);
    
    assert(t == Vector3f(3.0f, 5.0f, 2.5f));
}

/**
 * Scaling vector of the matrix
 */
Vector!(T,3) scaling(T) (Matrix!(T,4) m)
do
{
    T sx = Vector!(T,3)(m.a11, m.a12, m.a13).length;
    T sy = Vector!(T,3)(m.a21, m.a22, m.a23).length;
    T sz = Vector!(T,3)(m.a31, m.a32, m.a33).length;
    return Vector!(T,3)(sx, sy, sz);
}

/**
 * Create a matrix to perform a rotation about a world axis
 * (theta in radians)
 */
Matrix!(T,4) rotationMatrix(T) (uint rotaxis, T theta)
do
{
    auto res = Matrix!(T,4).identity;

    T s = sin(theta);
    T c = cos(theta);

    switch (rotaxis)
    {
        case Axis.x:
            res.a11 = 1.0; res.a12 = 0.0; res.a13 = 0.0;
            res.a21 = 0.0; res.a22 = c;   res.a23 =  s;
            res.a31 = 0.0; res.a32 = -s;  res.a33 =  c;
            break;

        case Axis.y:
            res.a11 = c;   res.a12 = 0.0; res.a13 = -s;
            res.a21 = 0.0; res.a22 = 1.0; res.a23 = 0.0;
            res.a31 = s;   res.a32 = 0.0; res.a33 = c;
            break;

        case Axis.z:
            res.a11 = c;   res.a12 =  s;  res.a13 = 0.0;
            res.a21 = -s;  res.a22 =  c;  res.a23 = 0.0;
            res.a31 = 0.0; res.a32 = 0.0; res.a33 = 1.0;
            break;

        default:
            assert(0);
    }

    return res;
}

/**
 * Create a translation matrix given a translation vector
 */
Matrix!(T,4) translationMatrix(T) (Vector!(T,3) v)
do
{
    auto res = Matrix!(T,4).identity;
    res.a14 = v.x;
    res.a24 = v.y;
    res.a34 = v.z;
    return res;
}

///
unittest
{
    Matrix4f tm = translationMatrix(Vector3f(3.0f, 5.0f, 2.5f));
    Vector3f t = translation(tm);
    assert(t == Vector3f(3.0f, 5.0f, 2.5f));
}

/**
 * Create a matrix to perform scale on each axis
 */
Matrix!(T,4) scaleMatrix(T) (Vector!(T,3) v)
do
{
    auto res = Matrix!(T,4).identity;
    res.a11 = v.x;
    res.a22 = v.y;
    res.a33 = v.z;
    return res;
}

/**
 * Setup the matrix to perform scale along an arbitrary axis
 */
Matrix!(T,4) scaleAlongAxisMatrix(T) (Vector!(T,3) scaleAxis, T k)
in
{
    assert (fabs (dot(scaleAxis, scaleAxis) - 1.0) < 0.001);
}
do
{
    auto res = Matrix!(T,4).identity;

    T a = k - 1.0;
    T ax = a * scaleAxis.x;
    T ay = a * scaleAxis.y;
    T az = a * scaleAxis.z;

    res.a11 = (ax * scaleAxis.x) + 1.0;
    res.a22 = (ay * scaleAxis.y) + 1.0;
    res.a33 = (az * scaleAxis.z) + 1.0;

    res.a12 = res.a21 = (ax * scaleAxis.y);
    res.a13 = res.a31 = (ax * scaleAxis.z);
    res.a23 = res.a32 = (ay * scaleAxis.z);

    return res;
}

/**
 * Setup the matrix to perform a shear
 */
Matrix!(T,4) shearMatrix(T) (uint shearAxis, T s, T t)
do
{
    // NOTE: needs test
    auto res = Matrix!(T,4).identity;

    switch (shearAxis)
    {
        case Axis.x:
            res.a11 = 1.0; res.a12 = 0.0; res.a13 = 0.0;
            res.a21 = s;   res.a22 = 1.0; res.a23 = 0.0;
            res.a31 = t;   res.a32 = 0.0; res.a33 = 1.0;
            break;

        case Axis.y:
            res.a11 = 1.0; res.a12 = s;   res.a13 = 0.0;
            res.a21 = 0.0; res.a22 = 1.0; res.a23 = 0.0;
            res.a31 = 0.0; res.a32 = t;   res.a33 = 1.0;
            break;

        case Axis.z:
            res.a11 = 1.0; res.a12 = 0.0; res.a13 = s;
            res.a21 = 0.0; res.a22 = 1.0; res.a23 = t;
            res.a31 = 0.0; res.a32 = 0.0; res.a33 = 1.0;
            break;

        default:
            assert(0);
    }

    return res;
}

/**
 * Setup the matrix to perform a projection onto a plane passing
 * through the origin. The plane is perpendicular to the
 * unit vector n.
 */
Matrix!(T,4) projectionMatrix(T) (Vector!(T,3) n)
in
{
    assert (fabs(dot(n, n) - 1.0) < 0.001);
}
do
{
    // NOTE: needs test
    auto res = Matrix!(T,4).identity;

    res.a11 = 1.0 - (n.x * n.x);
    res.a22 = 1.0 - (n.y * n.y);
    res.a33 = 1.0 - (n.z * n.z);

    res.a12 = res.a21 = -(n.x * n.y);
    res.a13 = res.a31 = -(n.x * n.z);
    res.a23 = res.a32 = -(n.y * n.z);

    return res;
}

/**
 * Setup the matrix to perform a reflection about a plane parallel
 * to a cardinal plane.
 */
Matrix!(T,4) reflectionMatrix(T) (Axis reflectionAxis, T k)
do
{
    auto res = Matrix!(T,4).identity;

    switch (reflectionAxis)
    {
        case Axis.x:
            res.a11 = -1.0; res.a21 =  0.0; res.a31 =  0.0; res.a41 = 2.0 * k;
            res.a12 =  0.0; res.a22 =  1.0; res.a32 =  0.0; res.a42 = 0.0;
            res.a13 =  0.0; res.a23 =  0.0; res.a33 =  1.0; res.a43 = 0.0;
            break;

        case Axis.y:
            res.a11 =  1.0; res.a21 =  0.0; res.a31 =  0.0; res.a41 = 0.0;
            res.a12 =  0.0; res.a22 = -1.0; res.a32 =  0.0; res.a42 = 2.0 * k;
            res.a13 =  0.0; res.a23 =  0.0; res.a33 =  1.0; res.a43 = 0.0;
            break;

        case Axis.z:
            res.a11 =  1.0; res.a21 =  0.0; res.a31 =  0.0; res.a41 = 0.0;
            res.a12 =  0.0; res.a22 =  1.0; res.a32 =  0.0; res.a42 = 0.0;
            res.a13 =  0.0; res.a23 =  0.0; res.a33 = -1.0; res.a43 = 2.0 * k;
            break;

        default:
            assert(0);
    }

    return res;
}

/**
 * Setup the matrix to perform a reflection about an arbitrary plane
 * through the origin. The unit vector n is perpendicular to the plane.
 */
Matrix!(T,4) axisReflectionMatrix(T) (Vector!(T,3) n)
in
{
    assert (fabs(dot(n, n) - 1.0) < 0.001);
}
do
{
    auto res = Matrix!(T,4).identity;

    T ax = -2.0 * n.x;
    T ay = -2.0 * n.y;
    T az = -2.0 * n.z;

    res.a11 = 1.0 + (ax * n.x);
    res.a22 = 1.0 + (ay * n.y);
    res.a32 = 1.0 + (az * n.z);

    res.a12 = res.a21 = (ax * n.y);
    res.a13 = res.a31 = (ax * n.z);
    res.a23 = res.a32 = (ay * n.z);

    return res;
}

/**
 * Setup the matrix to perform a "Look At" transformation
 * like a first person camera
 */
Matrix!(T,4) lookAtMatrix(T) (Vector!(T,3) eye, Vector!(T,3) center, Vector!(T,3) up)
do
{
    auto Result = Matrix!(T,4).identity;

    auto f = (center - eye).normalized;
    auto u = (up).normalized;
    auto s = cross(f, u).normalized;
    u = cross(s, f);

    Result[0,0] = s.x;
    Result[0,1] = s.y;
    Result[0,2] = s.z;
    Result[1,0] = u.x;
    Result[1,1] = u.y;
    Result[1,2] = u.z;
    Result[2,0] =-f.x;
    Result[2,1] =-f.y;
    Result[2,2] =-f.z;
    Result[0,3] =-dot(s, eye);
    Result[1,3] =-dot(u, eye);
    Result[2,3] = dot(f, eye);
    return Result;
}

/**
 * Setup a frustum matrix given the left, right, bottom, top, near, and far
 * values for the frustum boundaries.
 */
Matrix!(T,4) frustumMatrix(T) (T l, T r, T b, T t, T n, T f)
in
{
    assert (n >= 0.0);
    assert (f >= 0.0);
}
do
{
    auto res = Matrix!(T,4).identity;

    T width  = r - l;
    T height = t - b;
    T depth  = f - n;

    res.arrayof[0] = (2 * n) / width;
    res.arrayof[1] = 0.0;
    res.arrayof[2] = 0.0;
    res.arrayof[3] = 0.0;

    res.arrayof[4] = 0.0;
    res.arrayof[5] = (2 * n) / height;
    res.arrayof[6] = 0.0;
    res.arrayof[7] = 0.0;

    res.arrayof[8] = (r + l) / width;
    res.arrayof[9] = (t + b) / height;
    res.arrayof[10]= -(f + n) / depth;
    res.arrayof[11]= -1.0;

    res.arrayof[12]= 0.0;
    res.arrayof[13]= 0.0;
    res.arrayof[14]= -(2 * f * n) / depth;
    res.arrayof[15]= 0.0;

    return res;
}

/**
 * Setup a perspective matrix given the field-of-view in the Y direction
 * in degrees, the aspect ratio of Y/X, and near and far plane distances
 */
Matrix!(T,4) perspectiveMatrix(T) (T fovY, T aspect, T n, T f)
do
{
    auto res = Matrix!(T,4).identity;

    T angle;
    T cot;

    angle = fovY / 2.0;
    angle = degtorad(angle);

    cot = cos(angle) / sin(angle);

    res.arrayof[0] = cot / aspect;
    res.arrayof[1] = 0.0;
    res.arrayof[2] = 0.0;
    res.arrayof[3] = 0.0;

    res.arrayof[4] = 0.0;
    res.arrayof[5] = cot;
    res.arrayof[6] = 0.0;
    res.arrayof[7] = 0.0;

    res.arrayof[8] = 0.0;
    res.arrayof[9] = 0.0;
    res.arrayof[10]= -(f + n) / (f - n);
    res.arrayof[11]= -1.0f; //-(2 * f * n) / (f - n);

    res.arrayof[12]= 0.0;
    res.arrayof[13]= 0.0;
    res.arrayof[14]= -(2 * f * n) / (f - n); //-1.0;
    res.arrayof[15]= 0.0;

    return res;
}

/**
 * Setup an orthographic Matrix4x4 given the left, right, bottom, top, near,
 * and far values for the frustum boundaries.
 */
Matrix!(T,4) orthoMatrix(T) (T l, T r, T b, T t, T n, T f)
do
{
    auto res = Matrix!(T,4).identity;

    T width  = r - l;
    T height = t - b;
    T depth  = f - n;

    res.arrayof[0] =  2.0 / width;
    res.arrayof[1] =  0.0;
    res.arrayof[2] =  0.0;
    res.arrayof[3] =  0.0;

    res.arrayof[4] =  0.0;
    res.arrayof[5] =  2.0 / height;
    res.arrayof[6] =  0.0;
    res.arrayof[7] =  0.0;

    res.arrayof[8] =  0.0;
    res.arrayof[9] =  0.0;
    res.arrayof[10]= -2.0 / depth;
    res.arrayof[11]=  0.0;

    res.arrayof[12]= -(r + l) / width;
    res.arrayof[13]= -(t + b) / height;
    res.arrayof[14]= -(f + n) / depth;
    res.arrayof[15]=  1.0;

    return res;
}

/**
 * Setup an orientation matrix using 3 basis normalized vectors
 */
Matrix!(T,4) orthoNormalMatrix(T) (Vector!(T,3) xdir, Vector!(T,3) ydir, Vector!(T,3) zdir)
do
{
    auto res = Matrix!(T,4).identity;

    res.arrayof[0] = xdir.x; res.arrayof[4] = ydir.x; res.arrayof[8] = zdir.x; res.arrayof[12] = 0.0;
    res.arrayof[1] = xdir.y; res.arrayof[5] = ydir.y; res.arrayof[9] = zdir.y; res.arrayof[13] = 0.0;
    res.arrayof[2] = xdir.z; res.arrayof[6] = ydir.z; res.arrayof[10]= zdir.z; res.arrayof[14] = 0.0;
    res.arrayof[3] = 0.0;    res.arrayof[7] = 0.0;    res.arrayof[11]= 0.0;    res.arrayof[15] = 1.0;

    return res;
}

/**
 * Setup a matrix that flattens geometry into a plane,
 * as if it were casting a shadow from a light
 */
Matrix!(T,4) shadowMatrix(T) (Vector!(T,4) groundplane, Vector!(T,4) lightpos)
{
    T d = dot(groundplane, lightpos);

    auto res = Matrix!(T,4).identity;

    res.a11 = d-lightpos.x * groundplane.x;
    res.a12 =  -lightpos.x * groundplane.y;
    res.a13 =  -lightpos.x * groundplane.z;
    res.a14 =  -lightpos.x * groundplane.w;

    res.a21 =  -lightpos.y * groundplane.x;
    res.a22 = d-lightpos.y * groundplane.y;
    res.a23 =  -lightpos.y * groundplane.z;
    res.a24 =  -lightpos.y * groundplane.w;

    res.a31 =  -lightpos.z * groundplane.x;
    res.a32 =  -lightpos.z * groundplane.y;
    res.a33 = d-lightpos.z * groundplane.z;
    res.a34 =  -lightpos.z * groundplane.w;

    res.a41 =  -lightpos.w * groundplane.x;
    res.a42 =  -lightpos.w * groundplane.y;
    res.a43 =  -lightpos.w * groundplane.z;
    res.a44 = d-lightpos.w * groundplane.w;

    return res;
}

/**
 * Setup an orientation matrix using forward direction vector
 */
Matrix!(T,4) directionToMatrix(T) (Vector!(T,3) zdir)
{
    Vector!(T,3) xdir = Vector!(T,3)(0, 0, 1);
    Vector!(T,3) ydir;
    float d = zdir.z;

    if (d > -0.999999999 && d < 0.999999999)
    {
        xdir = xdir - zdir * d;
        xdir.normalize();
        ydir = cross(zdir, xdir);
    }
    else
    {
        xdir = Vector!(T,3)(zdir.z, 0, -zdir.x);
        ydir = Vector!(T,3)(0, 1, 0);
    }

    auto m = Matrix!(T,4).identity;

    m.a13 = zdir.x;
    m.a23 = zdir.y;
    m.a33 = zdir.z;

    m.a11 = xdir.x;
    m.a21 = xdir.y;
    m.a31 = xdir.z;

    m.a12 = ydir.x;
    m.a22 = ydir.y;
    m.a32 = ydir.z;

    return m;
}

/**
 * Setup an orientation matrix that performs rotation
 * between two vectors
 *
 * Currently this is just a shortcut
 * for dlib.math.quaternion.rotationBetween
 */
Matrix!(T,4) rotationBetweenVectors(T) (Vector!(T,3) source, Vector!(T,3) target)
{
    return rotationBetween(source, target).toMatrix4x4;
}

///
unittest
{
    bool isAlmostZero4(Vector4f v)
    {
        float e = 0.002f;

        return abs(v.x) < e &&
               abs(v.y) < e &&
               abs(v.z) < e &&
               abs(v.w) < e;
    }

    // build ModelView (World to Camera)
    vec3 center = vec3(0.0f, 0.0f, 0.0f);
    vec3 eye = center + vec3(0.0f, 1.0f, 1.0f);
    vec3 up = vec3(0.0f, -0.707f, 0.707f);

    Matrix4f modelView = lookAtMatrix(eye, center, up);

    // build Projection (Camera to Eye)
    Matrix4f projection = perspectiveMatrix(45.0f, 16.0f / 9.0f, 1.0f, 100.0f);

    // compose into one transformation
    Matrix4f projectionModelView = projection * modelView;

    vec4 positionInWorld = vec4(0.0f, 0.0f, 0.0f, 1.0f);

    vec4 transformed1 =
        positionInWorld * projectionModelView;

    vec4 transformed2 =
        (positionInWorld * modelView) * projection;

    assert(isAlmostZero4(transformed1 - transformed2));
}

/**
 * Affine transformations in 2D space
 */
 Vector!(T,2) affineTransform2D(T)(Vector!(T,2) v, Matrix!(T,3) m)
{
    return Vector!(T,2)
    (
        (v.x * m.a11) + (v.y * m.a12) + m.a13,
        (v.x * m.a21) + (v.y * m.a22) + m.a23
    );
}

/**
 * Translation in 2D space
 */
Matrix!(T,3) translationMatrix2D(T) (Vector!(T,2) t)
do
{
    Matrix!(T,3) res;
    res.a11 = 1; res.a12 = 0; res.a13 = t.x;
    res.a21 = 0; res.a22 = 1; res.a23 = t.y;
    res.a31 = 0; res.a32 = 0; res.a33 = 1;
    return res;
}

alias translation2 = translationMatrix2D;

/**
 * Rotation in 2D space
 */
Matrix!(T,3) rotationMatrix2D(T) (T theta)
do
{
    Matrix!(T,3) res;
    T s = sin(theta);
    T c = cos(theta);
    res.a11 = c;  res.a12 = s; res.a13 = 0;
    res.a21 = -s; res.a22 = c; res.a23 = 0;
    res.a31 = 0;  res.a32 = 0; res.a33 = 1;
    return res;
}

alias rotation2 = rotationMatrix2D;

/**
 * Scale in 2D space
 */
Matrix!(T,3) scaleMatrix2D(T) (Vector!(T,2) s)
do
{
    Matrix!(T,3) res;
    res.a11 = s.x; res.a12 = 0;   res.a13 = 0;
    res.a21 = 0;   res.a22 = s.y; res.a23 = 0;
    res.a31 = 0;   res.a32 = 0;   res.a33 = 1;
    return res;
}

alias scale2 = scaleMatrix2D;

///
unittest
{
    bool isAlmostZero2(Vector2f v)
    {
        float e = 0.002f;

        return abs(v.x) < e &&
               abs(v.y) < e;
    }
    
    vec2 v = vec2(1, 0);
    Matrix3f tm = translationMatrix2D(vec2(2, 3));
    vec2 vt = affineTransform2D(v, tm);
    assert(isAlmostZero2(vt - vec2(3, 3)));
    
    Matrix3f rm = rotationMatrix2D(cast(float)PI);
    vt = affineTransform2D(v, rm);
    assert(isAlmostZero2(vt - vec2(-1, 0)));
    
    Matrix3f sm = scaleMatrix2D(vec2(2, 2));
    vt = affineTransform2D(v, sm);
    assert(isAlmostZero2(vt - vec2(2, 0)));
}
