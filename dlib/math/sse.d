﻿/*
Copyright (c) 2015 Timur Gafarov 

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

module dlib.math.sse;

import dlib.math.vector;
import dlib.math.matrix;

/*
 * This module implements some frequently used vector and matrix operations
 * using SSE instructions. Implementation is in WIP status.
 */

Vector4f sseAdd4(Vector4f a, Vector4f b)
{
    asm
    {
        movups XMM0, a;
        movups XMM1, b;
        addps XMM0, XMM1;
        movups a, XMM0;
    }

    return a;
}

Vector4f sseSub4(Vector4f a, Vector4f b)
{
    asm
    {
        movups XMM0, a;
        movups XMM1, b;
        subps XMM0, XMM1;
        movups a, XMM0;
    }

    return a;
}

Vector4f sseMul4(Vector4f a, Vector4f b)
{
    asm
    {
        movups XMM0, a;
        movups XMM1, b;
        mulps XMM0, XMM1;
        movups a, XMM0;
    }

    return a;
}

Vector4f sseDiv4(Vector4f a, Vector4f b)
{
    asm
    {
        movups XMM0, a;
        movups XMM1, b;
        divps XMM0, XMM1;
        movups a, XMM0;
    }

    return a;
}

float sseDot4(Vector4f a, Vector4f b)
{
    asm
    {
        movups XMM0, a;
        movups XMM1, b;
        mulps XMM0, XMM1;

        // Horizontal addition
        movhlps XMM1, XMM0;     
        addps XMM0, XMM1;      
        movups XMM1, XMM0;
        shufps XMM1, XMM1, 0x55;
        addps XMM0, XMM1;

        movups a, XMM0;
    }

    return a[0];
}

Vector4f sseCross3(Vector4f a, Vector4f b)
{
    asm
    {
        movups XMM0, a;
        movups XMM1, b;
        movaps XMM2, XMM0;
        movaps XMM3, XMM1;

        shufps XMM0, XMM0, 0xC9;
        shufps XMM1, XMM1, 0xD2;
        shufps XMM2, XMM2, 0xD2;
        shufps XMM3, XMM3, 0xC9;

        mulps XMM0, XMM1;
        mulps XMM2, XMM3;

        subps XMM0, XMM2;

        movups a, XMM0;
    }

    return a;
}

Matrix4x4f sseMulMat4(Matrix4x4f a, Matrix4x4f b)
{
    Matrix4x4f r;
    Vector4f a_line, b_line, r_line;
    float _b;
    uint i, j;
    Vector4f* _rp;
    for (i = 0; i < 16; i += 4)
    {
        a_line = *cast(Vector4f*)(a.arrayof.ptr);
        _b = *(b.arrayof.ptr + i);
        asm
        {
            movups XMM0, a_line;
            
            mov EAX, _b;
            movd XMM1, EAX;
            shufps XMM1, XMM1, 0;
            
            mulps XMM0, XMM1;
            movups r_line, XMM0;
        }
        
        for (j = 1; j < 4; j++)
        {
            a_line = *cast(Vector4f*)(a.arrayof.ptr + j * 4);
            _b = *(b.arrayof.ptr + i + j); // i
            asm
            {
                movups XMM0, a_line;
                
                mov EAX, _b;
                movd XMM1, EAX;
                shufps XMM1, XMM1, 0;
                
                mulps XMM0, XMM1;
                
                movups XMM2, r_line;
                addps XMM0, XMM2;
                
                movups r_line, XMM0;
            }
        }

        _rp = cast(Vector4f*)(r.arrayof.ptr + i);
        asm
        {
            mov EAX, _rp;
            movups [EAX], XMM0;
        }
    }
    
    return r;
}
