/*
Copyright (c) 2015-2019 Timur Gafarov

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

module dlib.image.unmanaged;

import dlib.image.image;
import dlib.core.memory;

/*
 * This module provides GC-free SuperImage implementation
 */

class UnmanagedImage(PixelFormat fmt): Image!(fmt)
{
    override @property SuperImage dup()
    {
        auto res = New!(UnmanagedImage!(fmt))(_width, _height);
        res.data[] = data[];
        return res;
    }

    override SuperImage createSameFormat(uint w, uint h)
    {
        return New!(UnmanagedImage!(fmt))(w, h);
    }

    this(uint w, uint h)
    {
        super(w, h);
    }

    ~this()
    {
        Delete(_data);
    }

    protected override void allocateData()
    {
        _data = New!(ubyte[])(_width * _height * _pixelSize);
    }

    override void free()
    {
        Delete(this);
    }
}

alias UnmanagedImageL8 = UnmanagedImage!(PixelFormat.L8);
alias UnmanagedImageLA8 = UnmanagedImage!(PixelFormat.LA8);
alias UnmanagedImageRGB8 = UnmanagedImage!(PixelFormat.RGB8);
alias UnmanagedImageRGBA8 = UnmanagedImage!(PixelFormat.RGBA8);

alias UnmanagedImageL16 = UnmanagedImage!(PixelFormat.L16);
alias UnmanagedImageLA16 = UnmanagedImage!(PixelFormat.LA16);
alias UnmanagedImageRGB16 = UnmanagedImage!(PixelFormat.RGB16);
alias UnmanagedImageRGBA16 = UnmanagedImage!(PixelFormat.RGBA16);

class UnmanagedImageFactory: SuperImageFactory
{
    SuperImage createImage(uint w, uint h, uint channels, uint bitDepth, uint numFrames = 1)
    {
        return unmanagedImage(w, h, channels, bitDepth);
    }
}

SuperImage unmanagedImage(uint w, uint h, uint channels = 3, uint bitDepth = 8)
in
{
    assert(channels > 0 && channels <= 4);
    assert(bitDepth == 8 || bitDepth == 16);
}
body
{
    switch(channels)
    {
        case 1:
        {
            if (bitDepth == 8)
                return New!UnmanagedImageL8(w, h);
            else
                return New!UnmanagedImageL16(w, h);
        }
        case 2:
        {
            if (bitDepth == 8)
                return New!UnmanagedImageLA8(w, h);
            else
                return New!UnmanagedImageLA16(w, h);
        }
        case 3:
        {
            if (bitDepth == 8)
                return New!UnmanagedImageRGB8(w, h);
            else
                return New!UnmanagedImageRGB16(w, h);
        }
        case 4:
        {
            if (bitDepth == 8)
                return New!UnmanagedImageRGBA8(w, h);
            else
                return New!UnmanagedImageRGBA16(w, h);
        }
        default:
            assert(0);
    }
}
