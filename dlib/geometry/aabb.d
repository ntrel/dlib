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

module dlib.geometry.aabb;

private
{
    import std.math;
    import std.algorithm;
    import dlib.math.vector;
    import dlib.geometry.sphere;
}

struct AABB
{
    Vector3f center;
    Vector3f size;
    Vector3f pmin, pmax;

    this(Vector3f newPosition, Vector3f newSize)
    {
        center = newPosition;
        size = newSize;

        pmin = center - size;
        pmax = center + size;
    }

    @property float topHeight()
    {
        return (center.y + size.y);
    }

    @property float bottomHeight()
    {
        return (center.y - size.y);
    }

    Vector3f closestPoint(Vector3f point)
    {
        Vector3f closest;
        closest.x = (point.x < pmin.x)? pmin.x : ((point.x > pmax.x)? pmax.x : point.x);
        closest.y = (point.y < pmin.y)? pmin.y : ((point.y > pmax.y)? pmax.y : point.y);
        closest.z = (point.z < pmin.z)? pmin.z : ((point.z > pmax.z)? pmax.z : point.z);
        return closest;
    }

    bool containsPoint(Vector3f point)
    {
        return !(point.x < pmin.x || point.x > pmax.x ||
                 point.y < pmin.y || point.y > pmax.y ||
                 point.z < pmin.z || point.z > pmax.z);
    }

    // TODO: move the following into
    // separate intersection module

    bool intersectsAABB(AABB b)
    {
        Vector3f t = b.center - center;
        return fabs(t.x) <= (size.x + b.size.x) &&
               fabs(t.y) <= (size.y + b.size.y) &&
               fabs(t.z) <= (size.z + b.size.z);
    }

    bool intersectsSphere(
        Sphere sphere,
        out Vector3f collisionNormal,
        out float penetrationDepth)
    {
        penetrationDepth = 0.0f;
        collisionNormal = Vector3f(0.0f, 0.0f, 0.0f);

        if (containsPoint(sphere.center))
            return true;

        Vector3f xClosest = closestPoint(sphere.center);
        Vector3f xDiff = sphere.center - xClosest;

        float fDistSquared = xDiff.lengthsqr();
        if (fDistSquared > sphere.radius * sphere.radius)
            return false;

        float fDist = sqrt(fDistSquared);
        penetrationDepth = sphere.radius - fDist;
        collisionNormal = xDiff / fDist;
        collisionNormal.normalize();
        return true;
    }

    private bool intersectsRaySlab(
        float slabmin,
        float slabmax,
        float raystart,
        float rayend,
        ref float tbenter,
        ref float tbexit)
    {
        float raydir = rayend - raystart;

        if (fabs(raydir) < 1.0e-9f)
        {
            if (raystart < slabmin || raystart > slabmax)
                return false;
            else
                return true;
        }

        float tsenter = (slabmin - raystart) / raydir;
        float tsexit = (slabmax - raystart) / raydir;

        if (tsenter > tsexit)
        {
            swap(tsenter, tsexit);
        }

        if (tbenter > tsexit || tsenter > tbexit)
        {
            return false;
        }
        else
        {
            tbenter = max(tbenter, tsenter);
            tbexit = min(tbexit, tsexit);
            return true;
        }
    }

    bool intersectsSegment(
        Vector3f segStart,
        Vector3f segEnd,
        ref float intersectionTime)
    {
        float tenter = 0.0f, texit = 1.0f;

        if (!intersectsRaySlab(pmin.x, pmax.x, segStart.x, segEnd.x, tenter, texit))
            return false;

        if (!intersectsRaySlab(pmin.y, pmax.y, segStart.y, segEnd.y, tenter, texit))
            return false;

        if (!intersectsRaySlab(pmin.z, pmax.z, segStart.z, segEnd.z, tenter, texit))
            return false;

        intersectionTime = tenter;

        return true;
    }
}

AABB boxFromMinMaxPoints(Vector3f mi, Vector3f ma)
{
    AABB box;
    box.pmin = mi;
    box.pmax = ma;
    box.center = (box.pmax + box.pmin) * 0.5f;
    box.size = box.pmax - box.center;
    box.size.x = abs(box.size.x);
    box.size.y = abs(box.size.y);
    box.size.z = abs(box.size.z);
    return box;
}
