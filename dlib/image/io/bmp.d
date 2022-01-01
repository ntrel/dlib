/*
Copyright (c) 2014-2022 Timur Gafarov, Roman Chistokhodov

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
 * Decode and encode BMP images
 *
 * Copyright: Timur Gafarov, Roman Chistokhodov 2014-2022.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov, Roman Chistokhodov
 */
module dlib.image.io.bmp;

import std.stdio;
import dlib.core.stream;
import dlib.core.memory;
import dlib.core.compound;
import dlib.image.image;
import dlib.image.color;
import dlib.image.io;
import dlib.image.io.utils;
import dlib.filesystem.local;

// uncomment this to see debug messages:
//version = BMPDebug;

static const ubyte[2] BMPMagic = ['B', 'M'];

struct BMPFileHeader
{
    ubyte[2] type;        // magic number "BM"
    uint size;            // file size
    ushort reserved1;
    ushort reserved2;
    uint offset;          // offset to image data
}

struct BMPInfoHeader
{
    uint size;            // size of bitmap info header
    int width;            // image width
    int height;           // image height
    ushort planes;        // must be equal to 1
    ushort bitsPerPixel;  // bits per pixel
    uint compression;     // compression type
    uint imageSize;       // size of pixel data
    int xPixelsPerMeter;  // pixels per meter on x-axis
    int yPixelsPerMeter;  // pixels per meter on y-axis
    uint colorsUsed;      // number of used colors
    uint colorsImportant; // number of important colors
}

struct BMPCoreHeader
{
    uint size;            // size of bitmap core header
    ushort width;         // image with
    ushort height;        // image height
    ushort planes;        // must be equal to 1
    ushort bitsPerPixel;  // bits per pixel
}

struct BMPCoreInfo
{
    BMPCoreHeader header;
    ubyte[3] colors;
}

enum BMPOSType
{
    Win,
    OS2
}

// BMP compression type constants
enum BMPCompressionType
{
    RGB          = 0,
    RLE8         = 1,
    RLE4         = 2,
    BitFields    = 3
}

// RLE byte type constants
enum RLE
{
    Command      = 0,
    EndOfLine    = 0,
    EndOfBitmap  = 1,
    Delta        = 2
}

enum BMPInfoSize
{
    OLD  = 12,
    WIN  = 40,
    OS2  = 64,
    WIN4 = 108,
    WIN5 = 124,
}

class BMPLoadException: ImageLoadException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

private ubyte calculateShift(uint mask) nothrow pure
{
    ubyte result = 0;
    while (mask && !(mask & 1)) {
        result++;
        mask >>= 1;
    }
    return result;
}

unittest
{
    assert(calculateShift(0xff) == 0);
    assert(calculateShift(0xff00) == 8);
    assert(calculateShift(0xff0000) == 16);
    assert(calculateShift(0xff000000) == 24);
}

private ubyte applyMask(uint value, uint mask, ubyte shift, ubyte scale) nothrow pure
{
    return cast(ubyte) (((value & mask) >> shift) * scale);
}

private ubyte calculateScale(uint mask, ubyte shift) nothrow pure
{
    return cast(ubyte) (256 / calculateDivisor(mask, shift));
}

private uint calculateDivisor(uint mask, ubyte shift) nothrow pure
{
    return (mask >> shift) + 1;
}

private bool checkIndex(uint index, const(ubyte)[] colormap) nothrow pure {
    return index + 2 < colormap.length;
}

/**
 * Load BMP from file using local FileSystem.
 * Causes GC allocation
 */
SuperImage loadBMP(string filename)
{
    InputStream input = openForInput(filename);

    try
    {
        return loadBMP(input);
    }
    catch (BMPLoadException ex)
    {
        throw new Exception("'" ~ filename ~ "' :" ~ ex.msg, ex.file, ex.line, ex.next);
    }
    finally
    {
        input.close();
    }
}

/**
 * Load BMP from stream using default image factory.
 * Causes GC allocation
 */
SuperImage loadBMP(InputStream istrm)
{
    Compound!(SuperImage, string) res =
        loadBMP(istrm, defaultImageFactory);
    if (res[0] is null)
        throw new BMPLoadException(res[1]);
    else
        return res[0];
}

/**
 * Load BMP from stream using specified image factory.
 * GC-free
 */
Compound!(SuperImage, string) loadBMP(
    InputStream istrm,
    SuperImageFactory imgFac)
{
    SuperImage img = null;

    BMPFileHeader bmpfh;
    BMPInfoHeader bmpih;
    BMPCoreHeader bmpch;

    BMPOSType osType;

    uint compression;
    uint bitsPerPixel;

    uint redMask, greenMask, blueMask, alphaMask;

    ubyte[] colormap;
    int colormapSize;

    Compound!(SuperImage, string) error(string errorMsg)
    {
        if (img)
        {
            img.free();
            img = null;
        }
        if (colormap.length)
            Delete(colormap);
        return compound(img, errorMsg);
    }

    bmpfh = readStruct!BMPFileHeader(istrm);

    auto bmphPos = istrm.position;

    version(BMPDebug)
    {
        writefln("bmpfh.type = %s", cast(char[])bmpfh.type);
        writefln("bmpfh.size = %s", bmpfh.size);
        writefln("bmpfh.reserved1 = %s", bmpfh.reserved1);
        writefln("bmpfh.reserved2 = %s", bmpfh.reserved2);
        writefln("bmpfh.offset = %s", bmpfh.offset);
        writeln("-------------------");
    }

    if (bmpfh.type != BMPMagic)
        return error("loadBMP error: input data is not BMP");

    uint numChannels = 3;
    uint width, height;

    bmpih = readStruct!BMPInfoHeader(istrm);

    version(BMPDebug)
    {
        writefln("bmpih.size = %s", bmpih.size);
        writefln("bmpih.width = %s", bmpih.width);
        writefln("bmpih.height = %s", bmpih.height);
        writefln("bmpih.planes = %s", bmpih.planes);
        writefln("bmpih.bitsPerPixel = %s", bmpih.bitsPerPixel);
        writefln("bmpih.compression = %s", bmpih.compression);
        writefln("bmpih.imageSize = %s", bmpih.imageSize);
        writefln("bmpih.xPixelsPerMeter = %s", bmpih.xPixelsPerMeter);
        writefln("bmpih.yPixelsPerMeter = %s", bmpih.yPixelsPerMeter);
        writefln("bmpih.colorsUsed = %s", bmpih.colorsUsed);
        writefln("bmpih.colorsImportant = %s", bmpih.colorsImportant);
        writeln("-------------------");
    }

    if (bmpih.compression > 3)
    {
        /*
         * This is an OS/2 bitmap file, we don't use
         * bitmap info header but bitmap core header instead
         */

        // We must go back to read bitmap core header
        istrm.position = bmphPos;
        bmpch = readStruct!BMPCoreHeader(istrm);

        osType = BMPOSType.OS2;
        compression = BMPCompressionType.RGB;
        bitsPerPixel = bmpch.bitsPerPixel;

        width = bmpch.width;
        height = bmpch.height;
    }
    else
    {
        // Windows style
        osType = BMPOSType.Win;
        compression = bmpih.compression;
        bitsPerPixel = bmpih.bitsPerPixel;

        width = bmpih.width;
        height = bmpih.height;
    }

    version(BMPDebug)
    {
        writefln("osType = %s", [BMPOSType.OS2: "OS/2", BMPOSType.Win: "Windows"][osType]);
        writefln("width = %s", width);
        writefln("height = %s", height);
        writefln("bitsPerPixel = %s", bitsPerPixel);
        writefln("compression = %s", compression);
        writeln("-------------------");
    }

    if (bmpih.size >= BMPInfoSize.WIN4 || (compression == BMPCompressionType.BitFields && (bitsPerPixel == 16 || bitsPerPixel == 32)))
    {
        bool ok = true;
        ok = ok && istrm.readLE(&redMask);
        ok = ok && istrm.readLE(&greenMask);
        ok = ok && istrm.readLE(&blueMask);

        version(BMPDebug)
        {
            writeln("File has bitfields masks");
            writefln("redMask = %#x", redMask);
            writefln("greenMask = %#x", greenMask);
            writefln("blueMask = %#x", blueMask);
            writeln("-------------------");
        }

        if (ok && bmpih.size >= BMPInfoSize.WIN4)
        {
            version(BMPDebug)
            {
                writeln("File is at least version 4");
            }

            int CSType;
            int[9] coords;
            int gammaRed;
            int gammaGreen;
            int gammaBlue;

            ok = ok && istrm.readLE(&alphaMask);
            ok = ok && istrm.readLE(&CSType);
            istrm.fillArray(coords);
            ok = ok && istrm.readLE(&gammaRed);
            ok = ok && istrm.readLE(&gammaGreen);
            ok = ok && istrm.readLE(&gammaBlue);

            if (ok && bmpih.size >= BMPInfoSize.WIN5)
            {
                version(BMPDebug)
                {
                    writeln("File is at least version 5");
                }

                int intent;
                int profileData;
                int profileSize;
                int reserved;

                ok = ok && istrm.readLE(&intent);
                ok = ok && istrm.readLE(&profileData);
                ok = ok && istrm.readLE(&profileSize);
                ok = ok && istrm.readLE(&reserved);
            }
        }
        if (!ok)
            return error("loadBMP error: failed to read data of size specified in bmp info structure");
    }

    if (compression != BMPCompressionType.RGB && compression != BMPCompressionType.BitFields && compression != BMPCompressionType.RLE8)
        return error("loadBMP error: unsupported compression type (RLE4 is not supported yet)");

    if (bitsPerPixel != 4 && bitsPerPixel != 8 && bitsPerPixel != 16 && bitsPerPixel != 24 && bitsPerPixel != 32)
        return error("loadBMP error: unsupported color depth");

    uint numberOfColors;
    ubyte colormapEntrySize = (osType == BMPOSType.OS2)? 3 : 4;

    ubyte blueShift, greenShift, redShift, alphaShift;
    ubyte blueScale = 1, greenScale = 1, redScale = 1, alphaScale;

    if (bitsPerPixel == 8 || bitsPerPixel == 4)
    {
        numberOfColors = bmpih.colorsUsed ? bmpih.colorsUsed : (1 << bitsPerPixel);
        if (numberOfColors == 0 || numberOfColors > 256)
            return error("loadBMP error: strange number of used colors");
    }
    else if (compression == BMPCompressionType.BitFields && (bitsPerPixel == 16 || bitsPerPixel == 32))
    {
        redShift = calculateShift(redMask);
        greenShift = calculateShift(greenMask);
        blueShift = calculateShift(blueMask);
        alphaShift = calculateShift(alphaMask);

        version(BMPDebug)
        {
            writefln("redShift = %#x", redShift);
            writefln("greenShift = %#x", greenShift);
            writefln("blueShift = %#x", blueShift);
            writefln("alphaShift = %#x", alphaShift);
        }

        //scales are used to get equivalent weights for every color channel fit in byte

        if (calculateDivisor(redMask, redShift) == 0 || calculateDivisor(greenMask, greenShift) == 0 ||
            calculateDivisor(blueMask, blueShift) == 0 || calculateDivisor(alphaMask, alphaShift) == 0)
            return error("loadBMP error: division by zero when calculating scale");

        redScale = calculateScale(redMask, redShift);
        greenScale = calculateScale(greenMask, greenShift);
        blueScale = calculateScale(blueMask, blueShift);
        alphaScale = calculateScale(alphaMask, alphaShift);

        version(BMPDebug)
        {
            writefln("redScale = %#x", redScale);
            writefln("greenScale = %#x", greenScale);
            writefln("blueScale = %#x", blueScale);
            writefln("alphaScale = %#x", alphaScale);
        }
    }
    else if (compression == BMPCompressionType.RGB && (bitsPerPixel == 24 || bitsPerPixel == 32))
    {
        blueMask = 0x000000ff;
        greenMask = 0x0000ff00;
        redMask = 0x00ff0000;
        blueShift = 0;
        greenShift = 8;
        redShift = 16;
    }
    else if (compression == BMPCompressionType.RGB && bitsPerPixel == 16)
    {
        blueMask = 0x001f;
        greenMask = 0x03e0;
        redMask = 0x7c00;
        blueShift = 0;
        greenShift = 2;
        redShift = 7;
        blueScale = 8;
    }
    else
        return error("loadBMP error: unknown compression type / color depth combination");

    // Look for palette data if present
    if (numberOfColors)
    {
        colormapSize = numberOfColors * colormapEntrySize;
        colormap = New!(ubyte[])(colormapSize);
        istrm.fillArray(colormap);
    }

    // Go to begining of pixel data
    istrm.position = bmpfh.offset;

    const bool transparent = alphaMask != 0 && compression == BMPCompressionType.BitFields;

    // Create image
    img = imgFac.createImage(width, height, transparent ? 4 : 3, 8);

    enum wrongIndexError = "wrong index for colormap";

    if (bitsPerPixel == 4 && compression == BMPCompressionType.RGB)
    {
        foreach(y; 0..img.height)
        {
            //4 bits per pixel, so width/2 iterations
            foreach(x; 0..img.width/2)
            {
                ubyte[1] buf;
                istrm.fillArray(buf);
                const uint first = (buf[0] >> 4)*colormapEntrySize;
                const uint second = (buf[0] & 0x0f)*colormapEntrySize;
                
                if (!checkIndex(first, colormap) || !checkIndex(second, colormap))
                    return error(wrongIndexError);
                
                img[x*2, img.height-y-1] = Color4f(ColorRGBA(colormap[first+2], colormap[first+1], colormap[first]));
                img[x*2 + 1, img.height-y-1] = Color4f(ColorRGBA(colormap[second+2], colormap[second+1], colormap[second]));
            }
            //for odd widths
            if (img.width & 1)
            {
                ubyte[1] buf;
                istrm.fillArray(buf);
                const uint index = (buf[0] >> 4)*colormapEntrySize;
                if (!checkIndex(index, colormap))
                    return error(wrongIndexError);
                img[img.width-1, img.height-y-1] = Color4f(ColorRGBA(colormap[index+2], colormap[index+1], colormap[index]));
            }
        }
    }
    else if (bitsPerPixel == 8 && compression == BMPCompressionType.RGB)
    {
        foreach(y; 0..img.height)
        {
            foreach(x; 0..img.width)
            {
                ubyte[1] buf;
                istrm.fillArray(buf);
                const uint index = buf[0]*colormapEntrySize;
                if (!checkIndex(index, colormap))
                    return error(wrongIndexError);
                img[x, img.height-y-1] = Color4f(ColorRGBA(colormap[index+2], colormap[index+1], colormap[index]));
            }
        }
    }
    else if (bitsPerPixel == 8 && compression == BMPCompressionType.RLE8)
    {
        int x, y;
        
        while(y < img.height)
        {
            ubyte value;
            
            if (!istrm.readLE(&value))
                break;
            
            if (value == 0)
            {
                if (!istrm.readLE(&value) || value == 1)
                    break;
                else
                {
                    if (value == 0)
                    {
                        x = 0;
                        y++;
                    }
                    else if (value == 2)
                    {
                        version(BMPDebug) writeln("in delta");
                        
                        ubyte xdelta, ydelta;
                        istrm.readLE(&xdelta);
                        istrm.readLE(&ydelta);
                        x += xdelta;
                        y += ydelta;
                    }
                    else
                    {
                        version(BMPDebug) writeln("in absolute mode");
                        
                        foreach(i; 0..value)
                        {
                            ubyte j;
                            istrm.readLE(&j);
                            const uint index = j*colormapEntrySize;
                            if (!checkIndex(index, colormap))
                                return error(wrongIndexError);
                            img[x++, img.height-y-1] = Color4f(ColorRGBA(colormap[index+2], colormap[index+1], colormap[index]));
                        }
                        if (value & 1)
                        {
                            ubyte padding;
                            istrm.readLE(&padding);
                        }
                    }
                }
            }
            else
            {
                ubyte j;
                istrm.readLE(&j);
                const uint index = j*colormapEntrySize;
                if (!checkIndex(index, colormap))
                    return error(wrongIndexError);
                
                foreach(i; 0..value)
                    img[x++, img.height-y-1] = Color4f(ColorRGBA(colormap[index+2], colormap[index+1], colormap[index]));
            }
        }
    }
    else if (bitsPerPixel == 16 || bitsPerPixel == 24 || bitsPerPixel == 32)
    {
        const bytesPerPixel = bitsPerPixel / 8;
        const bytesPerRow = ((bitsPerPixel*width+31)/32)*4; //round to multiple of 4
        const bytesPerLine = bytesPerPixel * width;
        const padding = bytesPerRow - bytesPerLine;

        if (bitsPerPixel == 24)
        {
            foreach(y; 0..img.height)
            {
                foreach(x; 0..img.width)
                {
                    ubyte[3] bgr;
                    istrm.fillArray(bgr);
                    img[x, img.height-y-1] = Color4f(ColorRGBA(bgr[2], bgr[1], bgr[0]));
                }

                istrm.seek(padding);
            }
        }
        else if (bitsPerPixel == 16)
        {
            foreach(y; 0..img.height)
            {
                foreach(x; 0..img.width)
                {
                    ushort bgr;
                    istrm.readLE(&bgr);
                    const uint p = bgr;
                    const ubyte r = applyMask(p, redMask, redShift, redScale);
                    const ubyte g = applyMask(p, greenMask, greenShift, greenScale);
                    const ubyte b = applyMask(p, blueMask, blueShift, blueScale);

                    img[x, img.height-y-1] = Color4f(ColorRGBA(r,g,b));
                }

                istrm.seek(padding);
            }
        }
        else if (bitsPerPixel == 32)
        {
            foreach(y; 0..img.height)
            {
                foreach(x; 0..img.width)
                {
                    uint p;
                    istrm.readLE(&p);

                    const ubyte r = applyMask(p, redMask, redShift, redScale);
                    const ubyte g = applyMask(p, greenMask, greenShift, greenScale);
                    const ubyte b = applyMask(p, blueMask, blueShift, blueScale);

                    img[x, img.height-y-1] = Color4f(ColorRGBA(r, g, b, transparent ? applyMask(p, alphaMask, alphaShift, alphaScale) : 0xff));
                }

                istrm.seek(padding);
            }
        }
    }
    else
        return error("loadBMP error: unknown or unsupported compression type / color depth combination");

    if (colormap.length)
        Delete(colormap);

    return compound(img, "");
}

///
unittest
{
    import dlib.core.stream;
    import std.stdio;

    SuperImage img;

    //32 bit with bitfield masks
    ubyte[] bmpData32 =
    [
        66, 77, 72, 1, 0, 0, 0, 0, 0, 0, 70, 0, 0, 0, 56, 0, 0, 0, 8, 0, 0, 0, 8, 0,
        0, 0, 1, 0, 32, 0, 3, 0, 0, 0, 2, 1, 0, 0, 18, 11, 0, 0, 18, 11, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 255,
        255, 255, 0, 245, 235, 224, 0, 229, 199, 154, 0, 248, 227, 185, 0, 255, 229,
        181, 0, 236, 203, 152, 0, 244, 234, 223, 0, 255, 255, 255, 0, 244, 234, 224, 0,
        202, 139, 76, 0, 242, 199, 126, 0, 202, 217, 187, 0, 117, 190, 218, 0, 167,
        177, 160, 0, 209, 140, 72, 0, 243, 231, 221, 0, 196, 149, 107, 0, 166, 97, 16,
        0, 208, 143, 34, 0, 161, 188, 160, 0, 59, 207, 255, 0, 52, 168, 228, 0, 182,
        115, 42, 0, 196, 144, 97, 0, 196, 151, 116, 0, 192, 136, 51, 0, 226, 169, 71,
        0, 231, 202, 160, 0, 170, 199, 178, 0, 101, 178, 172, 0, 176, 156, 116, 0, 201,
        153, 112, 0, 204, 162, 127, 0, 185, 156, 134, 0, 136, 155, 170, 0, 153, 201,
        201, 0, 161, 211, 186, 0, 69, 179, 136, 0, 123, 151, 103, 0, 210, 164, 133, 0,
        215, 183, 153, 0, 201, 174, 166, 0, 34, 94, 208, 0, 29, 132, 228, 0, 125, 188,
        190, 0, 112, 178, 134, 0, 120, 144, 104, 0, 213, 181, 154, 0, 246, 240, 233, 0,
        221, 193, 168, 0, 167, 168, 213, 0, 127, 147, 220, 0, 220, 224, 236, 0, 255,
        239, 232, 0, 220, 191, 169, 0, 245, 238, 230, 0, 255, 255, 255, 0, 247, 240,
        233, 0, 235, 213, 186, 0, 252, 237, 216, 0, 245, 231, 217, 0, 231, 212, 193, 0,
        246, 239, 230, 0, 255, 255, 255, 0, 0
    ];
    auto bmpStream32 = new ArrayStream(bmpData32);
    img = loadBMP(bmpStream32);
    assert(img[2,2].convert(8) == Color4(208, 94, 34, 255));
    assert(img[5,2].convert(8) == Color4(134, 178, 112, 255));
    assert(img[2,5].convert(8) == Color4(34, 143, 208, 255));
    assert(img[5,5].convert(8) == Color4(228, 168, 52, 255));

    //32 bit with transparency
    ubyte[] bmpData32_alpha =
    [
        66, 77, 122, 1, 0, 0, 0, 0, 0, 0, 122, 0, 0, 0, 108, 0, 0, 0, 8, 0, 0, 0, 8,
        0, 0, 0, 1, 0, 32, 0, 3, 0, 0, 0, 0, 1, 0, 0, 109, 11, 0, 0, 109, 11, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 0, 0, 0, 255, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255,
        249, 173, 0, 206, 142, 67, 52, 231, 194, 127, 176, 248, 229, 183, 239, 249,
        229, 182, 240, 235, 196, 126, 179, 207, 143, 68, 55, 255, 255, 238, 0, 168, 86,
        17, 50, 198, 128, 57, 207, 230, 188, 116, 255, 200, 211, 179, 255, 131, 192,
        209, 255, 164, 172, 153, 255, 199, 131, 60, 211, 171, 88, 18, 55, 162, 88, 23,
        171, 171, 103, 22, 255, 203, 147, 48, 255, 165, 188, 159, 255, 78, 202, 251,
        255, 71, 168, 211, 255, 174, 119, 55, 255, 166, 89, 21, 179, 190, 142, 100,
        233, 191, 137, 58, 255, 215, 167, 81, 255, 216, 198, 158, 255, 162, 198, 181,
        255, 106, 177, 169, 255, 171, 153, 111, 255, 193, 142, 98, 239, 198, 155, 120,
        232, 184, 154, 130, 255, 140, 155, 166, 255, 149, 194, 197, 255, 153, 206, 185,
        255, 84, 180, 141, 255, 129, 151, 106, 255, 198, 154, 121, 238, 196, 152, 117,
        168, 191, 166, 157, 255, 59, 109, 202, 255, 51, 140, 222, 255, 127, 188, 190,
        255, 119, 179, 141, 255, 129, 146, 106, 255, 188, 149, 117, 175, 193, 147, 111,
        47, 213, 186, 167, 203, 164, 163, 201, 255, 138, 156, 216, 255, 212, 216, 226,
        255, 237, 225, 212, 255, 213, 189, 168, 207, 190, 148, 112, 52, 255, 255, 255,
        0, 212, 179, 149, 47, 236, 218, 201, 169, 247, 237, 227, 233, 246, 237, 229,
        234, 233, 217, 203, 172, 214, 182, 154, 50, 255, 255, 255, 0
    ];
    auto bmpStream32_alpha = new ArrayStream(bmpData32_alpha);
    img = loadBMP(bmpStream32_alpha);
    assert(img[1,1].convert(8) == Color4(167, 186, 213, 203));
    assert(img[1,6].convert(8) == Color4(57, 128, 198, 207));
    assert(img[2,2].convert(8) == Color4(202, 109, 59, 255));
    assert(img[5,5].convert(8) == Color4(211, 168, 71, 255));

    //24 bit
    ubyte[] bmpData24 =
    [
        66, 77, 248, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 8, 0, 0, 0, 8, 0,
        0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 194, 0, 0, 0, 18, 11, 0, 0, 18, 11, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 255, 255, 255, 245, 235, 224, 229, 199, 154, 248, 227, 185,
        255, 229, 181, 236, 203, 152, 244, 234, 223, 255, 255, 255, 244, 234, 224, 202,
        139, 76, 242, 199, 126, 202, 217, 187, 117, 190, 218, 167, 177, 160, 209, 140,
        72, 243, 231, 221, 196, 149, 107, 166, 97, 16, 208, 143, 34, 161, 188, 160, 59,
        207, 255, 52, 168, 228, 182, 115, 42, 196, 144, 97, 196, 151, 116, 192, 136,
        51, 226, 169, 71, 231, 202, 160, 170, 199, 178, 101, 178, 172, 176, 156, 116,
        201, 153, 112, 204, 162, 127, 185, 156, 134, 136, 155, 170, 153, 201, 201, 161,
        211, 186, 69, 179, 136, 123, 151, 103, 210, 164, 133, 215, 183, 153, 201, 174,
        166, 34, 94, 208, 29, 132, 228, 125, 188, 190, 112, 178, 134, 120, 144, 104,
        213, 181, 154, 246, 240, 233, 221, 193, 168, 167, 168, 213, 127, 147, 220, 220,
        224, 236, 255, 239, 232, 220, 191, 169, 245, 238, 230, 255, 255, 255, 247, 240,
        233, 235, 213, 186, 252, 237, 216, 245, 231, 217, 231, 212, 193, 246, 239, 230,
        255, 255, 255, 0, 0
    ];
    auto bmpStream24 = new ArrayStream(bmpData24);
    img = loadBMP(bmpStream24);
    assert(img[2,2].convert(8) == Color4(208, 94, 34, 255));
    assert(img[5,5].convert(8) == Color4(228, 168, 52, 255));

    //16 bit X1 R5 G5 B5
    ubyte[] bmpData16_1_5_5_5 =
    [
        66, 77, 184, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 8, 0, 0, 0, 8, 0,
        0, 0, 1, 0, 16, 0, 0, 0, 0, 0, 130, 0, 0, 0, 18, 11, 0, 0, 18, 11, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 255, 127, 190, 111, 28, 79, 158, 91, 159, 91, 61, 75, 158,
        111, 255, 127, 158, 111, 57, 38, 29, 63, 89, 95, 238, 110, 212, 78, 57, 38,
        158, 111, 88, 54, 148, 9, 57, 18, 244, 78, 39, 127, 134, 114, 214, 21, 88, 50,
        88, 58, 55, 26, 187, 38, 60, 79, 21, 91, 204, 86, 117, 58, 120, 58, 153, 62,
        118, 66, 113, 86, 19, 99, 84, 95, 200, 70, 79, 54, 154, 66, 218, 78, 184, 82,
        100, 101, 4, 114, 239, 94, 206, 66, 79, 54, 218, 78, 190, 115, 251, 82, 148,
        106, 79, 110, 123, 119, 191, 115, 251, 86, 190, 115, 255, 127, 190, 115, 93,
        95, 191, 107, 158, 107, 92, 95, 190, 115, 255, 127, 0, 0
    ];
    auto bmpStream16_1_5_5_5 = new ArrayStream(bmpData16_1_5_5_5);
    img = loadBMP(bmpStream16_1_5_5_5);

    /*TODO: pixel comparisons
     * GIMP shows slightly different pixel values on the same images.
     */

    //16 bit X4 R4 G4 B4
    ubyte[] bmpData16_4_4_4_4 =
    [
        66, 77, 200, 0, 0, 0, 0, 0, 0, 0, 70, 0, 0, 0, 56, 0, 0, 0, 8, 0, 0, 0, 8, 0,
        0, 0, 1, 0, 16, 0, 3, 0, 0, 0, 130, 0, 0, 0, 18, 11, 0, 0, 18, 11, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 15, 0, 0, 240, 0, 0, 0, 15, 0, 0, 0, 0, 0, 0, 0, 255, 15,
        238, 13, 205, 9, 223, 11, 223, 11, 206, 9, 238, 13, 255, 15, 238, 13, 140, 4,
        206, 7, 220, 11, 183, 13, 170, 9, 140, 4, 238, 13, 156, 6, 106, 1, 140, 2, 185,
        9, 195, 15, 163, 13, 123, 2, 140, 6, 156, 7, 139, 3, 173, 4, 206, 9, 202, 10,
        166, 10, 154, 7, 156, 7, 172, 7, 155, 8, 152, 10, 201, 12, 201, 11, 180, 8,
        151, 6, 172, 8, 189, 9, 172, 10, 98, 12, 130, 13, 183, 11, 167, 8, 135, 6, 189,
        9, 238, 14, 189, 10, 170, 13, 151, 13, 221, 14, 239, 14, 189, 10, 238, 14, 255,
        15, 239, 14, 222, 11, 239, 13, 238, 13, 206, 11, 238, 14, 255, 15, 0, 0
    ];
    auto bmpStream16_4_4_4_4 = new ArrayStream(bmpData16_4_4_4_4);
    img = loadBMP(bmpStream16_4_4_4_4);

    /*TODO: pixel comparisons
     * GIMP shows slightly different pixel values on the same images.
     */

    //16 bit R5 G6 B5
    ubyte[] bmpData16_5_6_5 =
    [
        66, 77, 200, 0, 0, 0, 0, 0, 0, 0, 70, 0, 0, 0, 56, 0, 0, 0, 8, 0, 0, 0, 8, 0,
        0, 0, 1, 0, 16, 0, 3, 0, 0, 0, 130, 0, 0, 0, 18, 11, 0, 0, 18, 11, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 248, 0, 0, 224, 7, 0, 0, 31, 0, 0, 0, 0, 0, 0, 0, 255,
        255, 94, 223, 60, 158, 30, 183, 63, 183, 93, 150, 94, 223, 255, 255, 94, 223,
        89, 76, 61, 126, 217, 190, 238, 221, 148, 157, 121, 76, 62, 223, 184, 108, 20,
        19, 121, 36, 212, 157, 103, 254, 70, 229, 150, 43, 152, 100, 184, 116, 87, 52,
        91, 77, 92, 158, 53, 182, 140, 173, 245, 116, 216, 116, 25, 125, 246, 132, 209,
        172, 83, 198, 148, 190, 136, 141, 175, 108, 58, 133, 186, 157, 120, 165, 228,
        202, 36, 228, 207, 189, 142, 133, 143, 108, 186, 157, 126, 231, 27, 166, 84,
        213, 143, 220, 251, 238, 127, 231, 251, 173, 126, 231, 255, 255, 126, 231, 189,
        190, 127, 215, 62, 215, 156, 190, 126, 231, 255, 255, 0, 0
    ];
    auto bmpStream16_5_6_5 = new ArrayStream(bmpData16_5_6_5);
    img = loadBMP(bmpStream16_5_6_5);

    /*TODO: pixel comparisons
     * GIMP shows slightly different pixel values on the same images.
     */

    //4 bit
    ubyte[] bmpData4 =
    [
        66, 77, 150, 0, 0, 0, 0, 0, 0, 0, 118, 0, 0, 0, 40, 0, 0, 0, 8, 0, 0, 0, 8, 0,
        0, 0, 1, 0, 4, 0, 0, 0, 0, 0, 32, 0, 0, 0, 196, 14, 0, 0, 196, 14, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 128, 0, 0, 0, 128, 128, 0, 128,
        0, 0, 0, 128, 0, 128, 0, 128, 128, 0, 0, 128, 128, 128, 0, 192, 192, 192, 0, 0,
        0, 255, 0, 0, 255, 0, 0, 0, 255, 255, 0, 255, 0, 0, 0, 255, 0, 255, 0, 255,
        255, 0, 0, 255, 255, 255, 0, 255, 136, 136, 255, 246, 136, 136, 111, 116, 103,
        187, 103, 118, 104, 131, 119, 119, 120, 131, 119, 136, 147, 135, 40, 248, 135,
        255, 143, 255, 255, 255, 255
    ];
    auto bmpStream4 = new ArrayStream(bmpData4);
    img = loadBMP(bmpStream4);
    assert(img[2,2].convert(8) == Color4(255,0,0,255));
    assert(img[1,1].convert(8) == Color4(192,192,192,255));
    assert(img[6,2].convert(8) == Color4(0,128,0,255));
}

/**
 * Save BMP to file using local FileSystem.
 * Causes GC allocation
 */
void saveBMP(SuperImage img, string filename)
{
    OutputStream output = openForOutput(filename);
    Compound!(bool, string) res =
        saveBMP(img, output);
    output.close();

    if (!res[0])
        throw new BMPLoadException(res[1]);
}

/**
 * Save BMP to stream.
 * GC-free
 */
Compound!(bool, string) saveBMP(SuperImage img, OutputStream output)
{
    Compound!(bool, string) error(string errorMsg)
    {
        return compound(false, errorMsg);
    }

    uint bytesPerRow = (img.width * 24 + 31) / 32 * 4;
    uint dataOffset = 12 + BMPInfoSize.WIN;
    uint fileSize = dataOffset + img.height * bytesPerRow;

    output.writeArray(BMPMagic);
    output.writeLE(fileSize);
    output.writeLE(cast(ushort)0);
    output.writeLE(cast(ushort)0);
    output.writeLE(dataOffset);

    output.writeLE(BMPInfoSize.WIN);
    output.writeLE(img.width);
    output.writeLE(img.height);
    output.writeLE(cast(ushort)1);
    output.writeLE(cast(ushort)24);
    output.writeLE(BMPCompressionType.RGB);
    output.writeLE(bytesPerRow * img.height);
    output.writeLE(2834);
    output.writeLE(2834);
    output.writeLE(0);
    output.writeLE(0);

    foreach_reverse(y; 0..img.height)
    {
        foreach(x; 0..img.width)
        {
            ubyte[3] rgb;
            ColorRGBA color = img[x, y].convert(8);
            rgb[0] = cast(ubyte)color[2];
            rgb[1] = cast(ubyte)color[1];
            rgb[2] = cast(ubyte)color[0];
            output.writeArray(rgb);
        }
        
        //padding
        for(uint i=0; i<(bytesPerRow-img.width*3); ++i)
        {
            output.writeLE(cast(ubyte)0);
        }
    }

    return compound(true, "");
}
