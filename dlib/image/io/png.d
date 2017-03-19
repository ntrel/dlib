/*
Copyright (c) 2011-2017 Timur Gafarov, Martin Cejp, Vadim Lopatin

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

module dlib.image.io.png;

private
{
    import std.stdio;
    import std.math;
    import std.string;
    import std.range;

    import dlib.core.memory;
    import dlib.core.stream;
    import dlib.core.compound;
    import dlib.filesystem.local;
    import dlib.math.utils;
    import dlib.coding.zlib;
    import dlib.image.image;
    import dlib.image.animation;
    import dlib.image.io.io;
}

// uncomment this to see debug messages:
//version = PNGDebug;

static const ubyte[8] PNGSignature = [137, 80, 78, 71, 13, 10, 26, 10];
static const ubyte[4] IHDR = ['I', 'H', 'D', 'R'];
static const ubyte[4] IEND = ['I', 'E', 'N', 'D'];
static const ubyte[4] IDAT = ['I', 'D', 'A', 'T'];
static const ubyte[4] PLTE = ['P', 'L', 'T', 'E'];
static const ubyte[4] tRNS = ['t', 'R', 'N', 'S'];
static const ubyte[4] bKGD = ['b', 'K', 'G', 'D'];
static const ubyte[4] tEXt = ['t', 'E', 'X', 't'];
static const ubyte[4] iTXt = ['i', 'T', 'X', 't'];
static const ubyte[4] zTXt = ['z', 'T', 'X', 't'];

// APNG chunks
static const ubyte[4] acTL = ['a', 'c', 'T', 'L'];
static const ubyte[4] fcTL = ['f', 'c', 'T', 'L'];
static const ubyte[4] fdAT = ['f', 'd', 'A', 'T'];

enum ColorType: ubyte
{
    Greyscale = 0,      // allowed bit depths: 1, 2, 4, 8 and 16
    RGB = 2,            // allowed bit depths: 8 and 16
    Palette = 3,        // allowed bit depths: 1, 2, 4 and 8
    GreyscaleAlpha = 4, // allowed bit depths: 8 and 16
    RGBA = 6,           // allowed bit depths: 8 and 16
    Any = 7             // one of the above
}

enum FilterMethod: ubyte
{
    None = 0,
    Sub = 1,
    Up = 2,
    Average = 3,
    Paeth = 4
}

struct PNGChunk
{
    uint length;
    ubyte[4] type;
    ubyte[] data;
    uint crc;

    void free()
    {
        if (data.ptr)
            Delete(data);
    }
}

struct APNGacTLChunk
{
    uint numFrames;
    uint numPlays;

    void readFrom(ubyte[] data)
    {
        *(&numFrames) = *(cast(uint*)data.ptr);
        numFrames = bigEndian(numFrames);
        *(&numPlays) = *(cast(uint*)(data.ptr+4));
        numPlays = bigEndian(numPlays);
    }
}

struct APNGfcTLChunk
{
    uint sequenceNumber;
    uint frameWidth;
    uint frameHeight;
    uint frameX;
    uint frameY;
    ushort delayNumerator;
    ushort delayDenominator;
    ubyte disposeOp;
    ubyte blendOp;

    void readFrom(ubyte[] data)
    {
        *(&sequenceNumber) = *(cast(uint*)data.ptr);
        sequenceNumber = bigEndian(sequenceNumber);
        *(&frameWidth) = *(cast(uint*)(data.ptr+4));
        frameWidth = bigEndian(frameWidth);
        *(&frameHeight) = *(cast(uint*)(data.ptr+8));
        frameHeight = bigEndian(frameHeight);
        *(&frameX) = *(cast(uint*)(data.ptr+12));
        frameX = bigEndian(frameX);
        *(&frameY) = *(cast(uint*)(data.ptr+16));
        frameY = bigEndian(frameY);
        *(&delayNumerator) = *(cast(ushort*)(data.ptr+20));
        delayNumerator = bigEndian(delayNumerator);
        *(&delayDenominator) = *(cast(ushort*)(data.ptr+22));
        delayDenominator = bigEndian(delayDenominator);
        disposeOp = data[24];
        blendOp = data[25];
    }
}

enum APNGDisposeOp
{
    None = 0,
    Background = 1,
    Previous = 2
}

enum APNGBlendOp
{
    Source = 0,
    Over = 1
}

struct PNGHeader
{
    union
    {
        struct
        {
            uint width;
            uint height;
            ubyte bitDepth;
            ubyte colorType;
            ubyte compressionMethod;
            ubyte filterMethod;
            ubyte interlaceMethod;
        };
        ubyte[13] bytes;
    }

    uint x;
    uint y;
}

class PNGLoadException: ImageLoadException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

/*
 * Load PNG from file using local FileSystem.
 * Causes GC allocation
 */
SuperImage loadPNG(string filename)
{
    InputStream input = openForInput(filename);
    auto img = loadPNG(input);
    input.close();
    return img;
}

/*
 * Load animated PNG (APNG) from file using local FileSystem.
 * Causes GC allocation
 */
SuperAnimatedImage loadAPNG(string filename)
{
    InputStream input = openForInput(filename);
    auto img = loadAPNG(input);
    input.close();
    return img;
}

/*
 * Save PNG to file using local FileSystem.
 * Causes GC allocation
 */
void savePNG(SuperImage img, string filename)
{
    OutputStream output = openForOutput(filename);
    Compound!(bool, string) res =
        savePNG(img, output);
    output.close();

    if (!res[0])
        throw new PNGLoadException(res[1]);
}

/*
 * Load PNG from stream using default image factory.
 * Causes GC allocation
 */
SuperImage loadPNG(InputStream istrm)
{
    Compound!(SuperImage, string) res =
        loadPNG(istrm, defaultImageFactory);
    if (res[0] is null)
        throw new PNGLoadException(res[1]);
    else
        return res[0];
}

/*
 * Load animated PNG (APNG) from stream using default animated image factory.
 * Causes GC allocation
 */
SuperAnimatedImage loadAPNG(InputStream istrm)
{
    Compound!(SuperImage, string) res =
        loadPNG(istrm, animatedImageFactory);
    if (res[0] is null)
        throw new PNGLoadException(res[1]);
    else
        return cast(SuperAnimatedImage)res[0];
}

/*
 * Load PNG from stream using specified image factory.
 * GC-free
 */
Compound!(SuperImage, string) loadPNG(
    InputStream istrm,
    SuperImageFactory imgFac)
{
    SuperImage img = null;
    Compound!(SuperImage, string) res = compound(img, "");

    Compound!(SuperImage, string) error(string errorMsg)
    {
        if (img)
        {
            img.free();
            img = null;
        }
        return compound(img, errorMsg);
    }

    bool readChunk(PNGChunk* chunk)
    {
        if (!istrm.readBE!uint(&chunk.length)
            || !istrm.fillArray(chunk.type))
        {
            return false;
        }

        version(PNGDebug) writefln("Chunk length = %s", chunk.length);
        version(PNGDebug) writefln("Chunk type = %s", cast(char[])chunk.type);

        if (chunk.length > 0)
        {
            chunk.data = New!(ubyte[])(chunk.length);

            if (!istrm.fillArray(chunk.data))
            {
                return false;
            }
        }

        version(PNGDebug) writefln("Chunk data.length = %s", chunk.data.length);

        if (!istrm.readBE!uint(&chunk.crc))
        {
            return false;
        }

        // TODO: reimplement CRC check with ranges instead of concatenation
        uint calculatedCRC = crc32(chain(chunk.type[0..$], chunk.data));

        version(PNGDebug)
        {
            writefln("Chunk CRC = %X", chunk.crc);
            writefln("Calculated CRC = %X", calculatedCRC);
            writeln("-------------------");
        }

        if (chunk.crc != calculatedCRC)
        {
            return false;
        }

        return true;
    }

    bool readHeader(PNGHeader* hdr, PNGChunk* chunk)
    {
        hdr.bytes[] = chunk.data[];
        hdr.width = bigEndian(hdr.width);
        hdr.height = bigEndian(hdr.height);

        version(PNGDebug)
        {
            writefln("width = %s", hdr.width);
            writefln("height = %s", hdr.height);
            writefln("bitDepth = %s", hdr.bitDepth);
            writefln("colorType = %s", hdr.colorType);
            writefln("compressionMethod = %s", hdr.compressionMethod);
            writefln("filterMethod = %s", hdr.filterMethod);
            writefln("interlaceMethod = %s", hdr.interlaceMethod);
            writeln("----------------");
        }

        return true;
    }

    ubyte[8] signatureBuffer;

    if (!istrm.fillArray(signatureBuffer))
    {
        return error("loadPNG error: signature check failed");
    }

    version(PNGDebug)
    {
        writeln("----------------");
        writeln("PNG Signature: ", signatureBuffer);
        writeln("----------------");
    }

    PNGHeader hdr;
    hdr.x = 0;
    hdr.y = 0;
    uint numChannels;
    uint bitDepth;
    uint bytesPerPixel;

    ZlibDecoder zlibDecoder;

    ubyte[] palette;
    ubyte[] transparency;
    uint paletteSize = 0;

    // Apply filtering and substitude palette colors if necessary
    Compound!(SuperImage, string) postProcessData(ZlibDecoder* decoder, PNGHeader hdr, size_t frameDataSize)
    {
        ubyte[] imgBuffer;

        Compound!(SuperImage, string) ppError(string errorMsg)
        {
            if (img)
            {
                img.free();
                img = null;
            }

            if (imgBuffer.length)
                Delete(imgBuffer);

            return compound(img, errorMsg);
        }

        ubyte[] buf = decoder.buffer;
        version(PNGDebug) writefln("buf.length = %s", buf.length);

        bool indexed = (hdr.colorType == ColorType.Palette);

        // apply filtering to the image data
        string errorMsg;
        if (!filter(&hdr, img.channels, indexed, buf, imgBuffer, errorMsg))
        {
            return ppError(errorMsg);
        }

        // if a palette is used, substitute target colors
        if (indexed)
        {
            if (palette.length == 0)
                return ppError("loadPNG error: palette chunk not found");

            ubyte[] pdata = New!(ubyte[])(hdr.width * hdr.height * img.channels);//(img.width * img.height * img.channels);
            if (hdr.bitDepth == 8)
            {
                for (int i = 0; i < imgBuffer.length; ++i)
                {
                    ubyte b = imgBuffer[i];
                    pdata[i * img.channels + 0] = palette[b * 3 + 0];
                    pdata[i * img.channels + 1] = palette[b * 3 + 1];
                    pdata[i * img.channels + 2] = palette[b * 3 + 2];
                    if (transparency.length > 0)
                        pdata[i * img.channels + 3] =
                            b < transparency.length ? transparency[b] : 0;
                }
            }
            else // bit depths 1, 2, 4
            {
                int srcindex = 0;
                int srcshift = 8 - hdr.bitDepth;
                ubyte mask = cast(ubyte)((1 << hdr.bitDepth) - 1);
                int sz = hdr.width * hdr.height; //img.width * img.height;
                for (int dstindex = 0; dstindex < sz; dstindex++)
                {
                    auto b = ((imgBuffer[srcindex] >> srcshift) & mask);
                    //assert(b * 3 + 2 < palette.length);
                    pdata[dstindex * img.channels + 0] = palette[b * 3 + 0];
                    pdata[dstindex * img.channels + 1] = palette[b * 3 + 1];
                    pdata[dstindex * img.channels + 2] = palette[b * 3 + 2];

                    if (transparency.length > 0)
                        pdata[dstindex * img.channels + 3] =
                            b < transparency.length ? transparency[b] : 0;

                    if (srcshift <= 0)
                    {
                        srcshift = 8 - hdr.bitDepth;
                        srcindex++;
                    }
                    else
                    {
                        srcshift -= hdr.bitDepth;
                    }
                }
            }

            if (imgBuffer.length)
                Delete(imgBuffer);

            imgBuffer = pdata;
        }

        //if (img.data.length != imgBuffer.length)
        //    return ppError("loadPNG error: uncompressed data length mismatch");

        if (img.data.length == imgBuffer.length)
            img.data[] = imgBuffer[];
        else
            blitImage(img, imgBuffer, hdr.width, hdr.height, hdr.x, hdr.y);

        Delete(imgBuffer);

        return compound(img, "");
    }

    // APNG-related data 
    SuperAnimatedImage animImg;
    bool isAPNG = false;
    bool decodingFirstFrame = true;
    uint numFrames = 1;
    uint numLoops = 0;
    uint sequenceNumber = 0;
    uint frameWidth;
    uint frameHeight;
    uint frameX;
    uint frameY;
    APNGDisposeOp disposeOp;
    APNGBlendOp blendOp;
    ZlibDecoder zlibDecoderAPNG;

    uint frameDataLength;
    ubyte[] frameBuffer;

    void finalize()
    {
        // delete all temporary buffers
        if (zlibDecoder.buffer.length)
            Delete(zlibDecoder.buffer);

        if (frameBuffer.length)
            Delete(frameBuffer);

        if (palette.length)
            Delete(palette);

        if (transparency.length > 0)
            Delete(transparency);

        // don't close the stream, just release our reference
        istrm = null;
    }

    bool endChunk = false;
    while (!endChunk && istrm.readable)
    {
        PNGChunk chunk;
        bool r = readChunk(&chunk);
        if (!r)
        {
            chunk.free();
            return error("loadPNG error: failed to read chunk");
        }
        else
        {
            if (chunk.type == IEND)
            {
                endChunk = true;
                chunk.free();
            }
            else if (chunk.type == IHDR)
            {
                if (chunk.data.length < hdr.bytes.length)
                    return error("loadPNG error: illegal header chunk");

                readHeader(&hdr, &chunk);
                chunk.free();

                bool supportedIndexed =
                    (hdr.colorType == ColorType.Palette) &&
                    (hdr.bitDepth == 1 ||
                     hdr.bitDepth == 2 ||
                     hdr.bitDepth == 4 ||
                     hdr.bitDepth == 8);

                if (hdr.bitDepth != 8 && hdr.bitDepth != 16 && !supportedIndexed)
                    return error("loadPNG error: unsupported bit depth");

                if (hdr.compressionMethod != 0)
                    return error("loadPNG error: unsupported compression method");

                if (hdr.filterMethod != 0)
                    return error("loadPNG error: unsupported filter method");

                if (hdr.interlaceMethod != 0)
                    return error("loadPNG error: interlacing is not supported");

                if (hdr.colorType == ColorType.Greyscale)                    numChannels = 1;
                else if (hdr.colorType == ColorType.GreyscaleAlpha)
                    numChannels = 2;
                else if (hdr.colorType == ColorType.RGB)
                    numChannels = 3;
                else if (hdr.colorType == ColorType.RGBA)
                    numChannels = 4;
                else if (hdr.colorType == ColorType.Palette)
                {
                    if (transparency.length > 0)
                        numChannels = 4;
                    else
                        numChannels = 3;
                }
                else
                    return error("loadPNG error: unsupported color type");

                if (hdr.colorType == ColorType.Palette)
                    bitDepth = 8;
                else
                    bitDepth = hdr.bitDepth;

                bytesPerPixel = bitDepth / 8;

                uint bufferLength = hdr.width * hdr.height * numChannels * bytesPerPixel + hdr.height; 
                ubyte[] buffer = New!(ubyte[])(bufferLength);

                zlibDecoder = ZlibDecoder(buffer);

                version(PNGDebug)
                {
                    writefln("buffer.length = %s", bufferLength);
                    writeln("----------------");
                }
            }
            else if (chunk.type == IDAT)
            {
                zlibDecoder.decode(chunk.data);
                chunk.free();
                decodingFirstFrame = false;
            }
            else if (chunk.type == PLTE)
            {
                palette = chunk.data;
            }
            else if (chunk.type == tRNS)
            {
                transparency = chunk.data;
                version(PNGDebug)
                {
                    writeln("----------------");
                    writefln("transparency.length = %s", transparency.length);
                    writeln("----------------");
                }
            }
            else if (chunk.type == acTL)
            {
                APNGacTLChunk animControl;
                animControl.readFrom(chunk.data); 
                numFrames = animControl.numFrames;
                numLoops = animControl.numPlays;
                isAPNG = true;

                version(PNGDebug)
                {
                    writefln("numFrames = %s", numFrames);
                    writefln("numLoops = %s", numLoops);
                    writeln("----------------");
                }

                chunk.free();
            }
            else if (chunk.type == fcTL)
            {
                APNGfcTLChunk frameControl;
                frameControl.readFrom(chunk.data);

                sequenceNumber = frameControl.sequenceNumber;
                frameWidth = frameControl.frameWidth;
                frameHeight = frameControl.frameHeight;
                frameX = frameControl.frameX;
                frameY = frameControl.frameY;

                disposeOp = cast(APNGDisposeOp)frameControl.disposeOp;
                blendOp = cast(APNGBlendOp)frameControl.blendOp;

                version(PNGDebug)
                {
                    writefln("sequenceNumber = %s", sequenceNumber);
                    writefln("frameWidth = %s", frameWidth);
                    writefln("frameHeight = %s", frameHeight);
                    writefln("frameX = %s", frameX);
                    writefln("frameY = %s", frameY);
                    writefln("disposeOp = %s", disposeOp);
                    writefln("blendOp = %s", blendOp);
                    writeln("----------------");
                }

                if (!decodingFirstFrame)
                {
                    frameDataLength = frameWidth * frameHeight * numChannels * bytesPerPixel + frameHeight;
                    //writeln(frameDataLength);
                    if (!frameBuffer.length)
                        frameBuffer = New!(ubyte[])(hdr.width * hdr.height * numChannels * bytesPerPixel + hdr.height);
                    zlibDecoderAPNG = ZlibDecoder(frameBuffer);
                }

                chunk.free();
            }
            else if (chunk.type == fdAT)
            {
                uint dataSequenceNumber;
                *(&dataSequenceNumber) = *(cast(uint*)chunk.data.ptr);
                dataSequenceNumber = bigEndian(dataSequenceNumber);

                zlibDecoderAPNG.decode(chunk.data[4..$]);
                chunk.free();
            }
            else
            {
                chunk.free();
            }

            if (zlibDecoder.hasEnded)
            {
                if (img is null)
                {
                    img = imgFac.createImage(hdr.width, hdr.height, numChannels, bitDepth, numFrames);

                    PNGHeader mainhdr = hdr;
                    res = postProcessData(&zlibDecoder, mainhdr, zlibDecoder.buffer.length);
                    if (!res[0])
                    {
                        finalize();
                        return res;
                    }

                    if (isAPNG)
                    {
                        animImg = cast(SuperAnimatedImage)img;
                    }
                }
            }

            if (zlibDecoderAPNG.hasEnded)
            {
                frameBuffer = zlibDecoderAPNG.buffer;

                if (animImg)
                {
                    if (animImg)
                        animImg.advanceFrame();

                    PNGHeader framehdr = hdr;
                    framehdr.width = frameWidth;
                    framehdr.height = frameHeight;
                    framehdr.x = frameX;
                    framehdr.y = frameY;
                    res = postProcessData(&zlibDecoderAPNG, framehdr, frameDataLength);
                    if (!res[0])
                    {
                        finalize();
                        return res;
                    }
                }
            }
        }
    }

    finalize();

    return res;
}

/*
 * Load animated PNG (APNG) from stream using specified image factory.
 * GC-free
 */
Compound!(SuperAnimatedImage, string) loadAPNG(
    InputStream istrm,
    SuperImageFactory imgFac)
{
    SuperAnimatedImage img = null;
    auto res = loadPNG(istrm, imgFac);
    if (res[0])
        img = cast(SuperAnimatedImage)res[0];
    return compound(img, res[1]);
}

/*
 * Save PNG to stream.
 * GC-free
 */
Compound!(bool, string) savePNG(SuperImage img, OutputStream output)
in
{
    assert (img.data.length);
}
body
{
    Compound!(bool, string) error(string errorMsg)
    {
        return compound(false, errorMsg);
    }

    if (img.bitDepth != 8)
        return error("savePNG error: only 8-bit images are supported by encoder");

    bool writeChunk(ubyte[4] chunkType, ubyte[] chunkData)
    {
        PNGChunk hdrChunk;
        hdrChunk.length = cast(uint)chunkData.length;
        hdrChunk.type = chunkType;
        hdrChunk.data = chunkData;
        hdrChunk.crc = crc32(chain(chunkType[0..$], hdrChunk.data));

        if (!output.writeBE!uint(hdrChunk.length)
            || !output.writeArray(hdrChunk.type))
            return false;

        if (chunkData.length)
            if (!output.writeArray(hdrChunk.data))
                return false;

        if (!output.writeBE!uint(hdrChunk.crc))
            return false;

        return true;
    }

    bool writeHeader()
    {
        PNGHeader hdr;
        hdr.width = networkByteOrder(img.width);
        hdr.height = networkByteOrder(img.height);
        hdr.bitDepth = 8;
        if (img.channels == 4)
            hdr.colorType = ColorType.RGBA;
        else if (img.channels == 3)
            hdr.colorType = ColorType.RGB;
        else if (img.channels == 2)
            hdr.colorType = ColorType.GreyscaleAlpha;
        else if (img.channels == 1)
            hdr.colorType = ColorType.Greyscale;
        hdr.compressionMethod = 0;
        hdr.filterMethod = 0;
        hdr.interlaceMethod = 0;

        return writeChunk(IHDR, hdr.bytes);
    }

    output.writeArray(PNGSignature);
    if (!writeHeader())
        return error("savePNG error: write failed (disk full?)");

    //TODO: filtering
    ubyte[] raw = New!(ubyte[])(img.width * img.height * img.channels + img.height);
    foreach(y; 0..img.height)
    {
        auto rowStart = y * (img.width * img.channels + 1);
        raw[rowStart] = 0; // No filter

        foreach(x; 0..img.width)
        {
            auto dataIndex = (y * img.width + x) * img.channels;
            auto rawIndex = rowStart + 1 + x * img.channels;

            foreach(ch; 0..img.channels)
                raw[rawIndex + ch] = img.data[dataIndex + ch];
        }
    }

    ubyte[] buffer = New!(ubyte[])(64 * 1024);
    ZlibBufferedEncoder zlibEncoder = ZlibBufferedEncoder(buffer, raw);
    while (!zlibEncoder.ended)
    {
        auto len = zlibEncoder.encode();
        if (len > 0)
            writeChunk(IDAT, zlibEncoder.buffer[0..len]);
    }

    writeChunk(IEND, []);

    Delete(buffer);
    Delete(raw);

    return compound(true, "");
}

// TODO: support disposeOp and blendOp
void blitImage(SuperImage img, ubyte[] data, uint width, uint height, uint px, uint py)
{
    for(uint y = 0; y < height; y++)
    {
        for(uint x = 0; x < width; x++)
        {
            for(uint ch = 0; ch < img.channels; ch++)
                img.data[(((py + y) * img.width) + (px + x)) * img.channels + ch] = 
                    data[((y * width) + x) * img.channels + ch];
        }
    }
}

/*
 * performs the paeth PNG filter from pixels values:
 *   a = back
 *   b = up
 *   c = up and back
 */
pure ubyte paeth(ubyte a, ubyte b, ubyte c)
{
    int p = a + b - c;
    int pa = std.math.abs(p - a);
    int pb = std.math.abs(p - b);
    int pc = std.math.abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    else if (pb <= pc) return b;
    else return c;
}

bool filter(PNGHeader* hdr,
            uint channels,
            bool indexed,
            ubyte[] ibuffer,
        out ubyte[] obuffer,
        out string errorMsg)
{
    uint dataSize = cast(uint)ibuffer.length;
    uint scanlineSize;

    uint calculatedSize;
    if (indexed)
    {
        calculatedSize = hdr.width * hdr.height * hdr.bitDepth / 8 + hdr.height;
        scanlineSize = hdr.width * hdr.bitDepth / 8 + 1;
    }
    else
    {
        calculatedSize = hdr.width * hdr.height * channels + hdr.height;
        scanlineSize = hdr.width * channels + 1;
    }

    version(PNGDebug)
    {
        writefln("[filter] dataSize = %s", dataSize);
        writefln("[filter] calculatedSize = %s", calculatedSize);
    }

    if (dataSize != calculatedSize)
    {
        errorMsg = "loadPNG error: image size and data mismatch";
        return false;
    }

    obuffer = New!(ubyte[])(calculatedSize - hdr.height);

    ubyte pback, pup, pupback, cbyte;

    for (int i = 0; i < hdr.height; ++i)
    {
        pback = 0;

        // get the first byte of a scanline
        ubyte scanFilter = ibuffer[i * scanlineSize];

        if (indexed)
        {
            // TODO: support filtering for indexed images
            if (scanFilter != FilterMethod.None)
            {
                errorMsg = "loadPNG error: filtering is not supported for indexed images";
                return false;
            }

            for (int j = 1; j < scanlineSize; ++j)
            {
                ubyte b = ibuffer[(i * scanlineSize) + j];
                obuffer[(i * (scanlineSize-1) + j - 1)] = b;
            }
            continue;
        }

        for (int j = 0; j < hdr.width; ++j)
        {
            for (int k = 0; k < channels; ++k)
            {
                if (i == 0)    pup = 0;
                else pup = obuffer[((i-1) * hdr.width + j) * channels + k]; // (hdr.height-(i-1)-1)
                if (j == 0)    pback = 0;
                else pback = obuffer[(i * hdr.width + j-1) * channels + k];
                if (i == 0 || j == 0) pupback = 0;
                else pupback = obuffer[((i-1) * hdr.width + j - 1) * channels + k];

                // get the current byte from ibuffer
                cbyte = ibuffer[i * (hdr.width * channels + 1) + j * channels + k + 1];

                // filter, then set the current byte in data
                switch (scanFilter)
                {
                    case FilterMethod.None:
                        obuffer[(i * hdr.width + j) * channels + k] = cbyte;
                        break;
                    case FilterMethod.Sub:
                        obuffer[(i * hdr.width + j) * channels + k] = cast(ubyte)(cbyte + pback);
                        break;
                    case FilterMethod.Up:
                        obuffer[(i * hdr.width + j) * channels + k] = cast(ubyte)(cbyte + pup);
                        break;
                    case FilterMethod.Average:
                        obuffer[(i * hdr.width + j) * channels + k] = cast(ubyte)(cbyte + (pback + pup) / 2);
                        break;
                    case FilterMethod.Paeth:
                        obuffer[(i * hdr.width + j) * channels + k] = cast(ubyte)(cbyte + paeth(pback, pup, pupback));
                        break;
                    default:
                        errorMsg = format("loadPNG error: unknown scanline filter (%s)", scanFilter);
                        return false;
                }
            }
        }
    }

    return true;
}

uint crc32(R)(R range, uint inCrc = 0) if (isInputRange!R)
{
    uint[256] generateTable()
    {
        uint[256] table;
        uint crc;
        for (int i = 0; i < 256; i++)
        {
            crc = i;
            for (int j = 0; j < 8; j++)
                crc = crc & 1 ? (crc >> 1) ^ 0xEDB88320UL : crc >> 1;
            table[i] = crc;
        }
        return table;
    }

    static const uint[256] table = generateTable();

    uint crc;

    crc = inCrc ^ 0xFFFFFFFF;
    foreach(v; range)
        crc = (crc >> 8) ^ table[(crc ^ v) & 0xFF];

    return (crc ^ 0xFFFFFFFF);
}

unittest
{
    import std.base64;

    InputStream png() {
        string minimal =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADklEQVR42mL4z8AAEGAAAwEBAGb9nyQAAAAASUVORK5CYII=";

        ubyte[] bytes = Base64.decode(minimal);
        return new ArrayStream(bytes, bytes.length);
    }

    SuperImage img = loadPNG(png());

    assert(img.width == 1);
    assert(img.height == 1);
    assert(img.channels == 3);
    assert(img.pixelSize == 3);
    assert(img.data == [0xff, 0x00, 0x00]);

    createDir("tests", false);
    savePNG(img, "tests/minimal.png");
    loadPNG("tests/minimal.png");
}
