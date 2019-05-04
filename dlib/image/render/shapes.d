/*
Copyright (c) 2015-2019 Oleg Baharev, Timur Gafarov

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

module dlib.image.render.shapes;

import std.math;
import dlib.image.image;
import dlib.image.color;

enum Black = Color4f(0, 0, 0, 1);
enum White = Color4f(1, 1, 1, 1);

void fillColor(SuperImage simg, Color4f col)
{
    foreach(y; simg.col)
    foreach(x; simg.row)
        simg[x, y] = col;
}

void drawLine(SuperImage img, Color4f color, int x1, int y1, int x2, int y2)
{
    int dx = x2 - x1;
    int ix = (dx > 0) - (dx < 0);
    int dx2 = abs(dx) * 2;
    int dy = y2 - y1;
    int iy = (dy > 0) - (dy < 0);
    int dy2 = abs(dy) * 2;
    img[x1, y1] = color;

    if (dx2 >= dy2)
    {
        int error = dy2 - (dx2 / 2);
        while (x1 != x2)
        {
            if (error >= 0 && (error || (ix > 0)))
            {
                error -= dx2;
                y1 += iy;
            }

            error += dy2;
            x1 += ix;
            img[x1, y1] = color;
        }
    }
    else
    {
        int error = dx2 - (dy2 / 2);
        while (y1 != y2)
        {
            if (error >= 0 && (error || (iy > 0)))
            {
                error -= dy2;
                x1 += ix;
            }

            error += dx2;
            y1 += iy;
            img[x1, y1] = color;
        }
    }
}

void drawCircle(SuperImage img, Color4f col, int x0, int y0, uint r)
{
    int f = 1 - r;
    int ddF_x = 0;
    int ddF_y = -2 * r;
    int x = 0;
    int y = r;

    img[x0, y0 + r] = col;
    img[x0, y0 - r] = col;
    img[x0 + r, y0] = col;
    img[x0 - r, y0] = col;

    while(x < y)
    {
        if(f >= 0)
        {
            y--;
            ddF_y += 2;
            f += ddF_y;
        }
        x++;
        ddF_x += 2;
        f += ddF_x + 1;
        img[x0 + x, y0 + y] = col;
        img[x0 - x, y0 + y] = col;
        img[x0 + x, y0 - y] = col;
        img[x0 - x, y0 - y] = col;
        img[x0 + y, y0 + x] = col;
        img[x0 - y, y0 + x] = col;
        img[x0 + y, y0 - x] = col;
        img[x0 - y, y0 - x] = col;
    }
}
