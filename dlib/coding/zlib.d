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

module dlib.coding.zlib;

private
{
    import etc.c.zlib;
    import dlib.core.memory;
}

struct ZlibBufferedEncoder
{
    z_stream zlibStream;
    ubyte[] buffer;
    ubyte[] input;
    bool ended = true;

    this(ubyte[] buf, ubyte[] inp)
    {
        buffer = buf;
        input = inp;
        zlibStream.next_out = buffer.ptr;
        zlibStream.avail_out = cast(uint)buffer.length;
        zlibStream.data_type = Z_BINARY;
        zlibStream.zalloc = null;
        zlibStream.zfree = null;
        zlibStream.opaque = null;

        zlibStream.next_in = inp.ptr;
        zlibStream.avail_in = cast(uint)inp.length;

        deflateInit(&zlibStream, Z_BEST_COMPRESSION);
        ended = false;
    }

    size_t encode()
    {
        zlibStream.next_out = buffer.ptr;
        zlibStream.avail_out = cast(uint)buffer.length;
        zlibStream.total_out = 0;

        while (zlibStream.avail_out > 0)
        {
            int msg = deflate(&zlibStream, Z_FINISH);

            if (msg == Z_STREAM_END)
            {
                deflateEnd(&zlibStream);
                ended = true;
                return zlibStream.total_out;
            }
            else if (msg != Z_OK)
            {
                deflateEnd(&zlibStream);
                return 0;
            }
        }

        return zlibStream.total_out;
    }
}

struct ZlibDecoder
{
    z_stream zlibStream;
    ubyte[] buffer;
    int msg = 0;

    bool isInitialized = false;
    bool hasEnded = false;

    this(ubyte[] buf)
    {
        buffer = buf;
        zlibStream.next_out = buffer.ptr;
        zlibStream.avail_out = cast(uint)buffer.length;
        zlibStream.data_type = Z_BINARY;
    }

    bool decode(ubyte[] input)
    {
        zlibStream.next_in = input.ptr;
        zlibStream.avail_in = cast(uint)input.length;

        if (!isInitialized)
        {
            isInitialized = true;
            msg = inflateInit(&zlibStream);
            if (msg)
            {
                inflateEnd(&zlibStream);
                return false;
            }
        }

        while (zlibStream.avail_in)
        {
            msg = inflate(&zlibStream, Z_NO_FLUSH);
            if (msg == Z_STREAM_END)
            {
                inflateEnd(&zlibStream);
                hasEnded = true;
                reallocateBuffer(zlibStream.total_out);
                return true;
            }
            else if (msg != Z_OK)
            {
                inflateEnd(&zlibStream);
                return false;
            }
            else if (zlibStream.avail_out == 0)
            {
                reallocateBuffer(buffer.length * 2);
                zlibStream.next_out = &buffer[buffer.length / 2];
                zlibStream.avail_out = cast(uint)(buffer.length / 2);
            }
        }

        return true;
    }

    void reallocateBuffer(size_t len)
    {
        ubyte[] buffer2 = New!(ubyte[])(len);
        for(uint i = 0; i < buffer2.length; i++)
            if (i < buffer.length)
                buffer2[i] = buffer[i];
        Delete(buffer);
        buffer = buffer2;
    }

    void free()
    {
        Delete(buffer);
    }
}
