/*
Copyright (c) 2014-2019 Martin Cejp

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

module dlib.filesystem.posix.file;

version (Posix)
{
    import dlib.core.stream;
    import dlib.core.memory;
    import dlib.filesystem.filesystem;
    import dlib.filesystem.posix.common;

    static import core.sys.posix.unistd;

    class PosixFile: IOStream
    {
        int fd;
        uint accessFlags;
        bool eof = false;

        this(int fd, uint accessFlags)
        {
            this.fd = fd;
            this.accessFlags = accessFlags;
        }

        ~this()
        {
            close();
        }

        override void close()
        {
            if (fd != -1)
            {
                core.sys.posix.unistd.close(fd);
                fd = -1;
            }
        }

        override bool seekable()
        {
            return true;
        }

        override StreamPos getPosition()
        {
            import core.sys.posix.stdio;

            return lseek(fd, 0, SEEK_CUR);
        }

        override bool setPosition(StreamPos pos)
        {
            import core.sys.posix.stdio;

            return lseek(fd, pos, SEEK_SET) == pos;
        }

        override StreamSize size()
        {
            import core.sys.posix.stdio;

            auto off = lseek(fd, 0, SEEK_CUR);
            auto end = lseek(fd, 0, SEEK_END);
            lseek(fd, off, SEEK_SET);
            return end;
        }

        override bool readable()
        {
            return fd != -1 && (accessFlags & FileSystem.read) && !eof;
        }

        override size_t readBytes(void* buffer, size_t count)
        {
            immutable size_t got = core.sys.posix.unistd.read(fd, buffer, count);

            if (count > got)
                eof = true;

            return got;
        }

        override bool writeable()
        {
            return fd != -1 && (accessFlags & FileSystem.write);
        }

        override size_t writeBytes(const void* buffer, size_t count)
        {
            return core.sys.posix.unistd.write(fd, buffer, count);
        }

        override void flush()
        {
        }
    }
}
