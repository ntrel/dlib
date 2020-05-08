/*
Copyright (c) 2016-2020 Timur Gafarov

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

module dlib.filesystem.stdposixdir;

import std.string;
import std.conv;
import std.range;
import core.stdc.string;
version(Posix)
{
    import core.sys.posix.dirent;
}
import dlib.core.memory;
import dlib.filesystem.filesystem;

version(Posix):

class StdPosixDirEntryRange: InputRange!(DirEntry)
{
    DIR* dir;
    dirent* de = null;
    DirEntry currentEntry;
    bool _empty = false;

    this(DIR* dir)
    {
        this.dir = dir;
        readNextEntry();
    }

    void readNextEntry()
    {
        de = readdir(dir);
        if (de)
        {
            string name = getFileName(de);
            if (name == "." || name == "..")
                readNextEntry();
            else
            {
                bool isFile = (de.d_type == DT_REG);
                bool isDir = (de.d_type == DT_DIR);
                currentEntry = DirEntry(getFileName(de), isFile, isDir);
            }
        }
        else
            _empty = true;
    }

    string getFileName(dirent* d)
    {
        return cast(string)d.d_name[0..strlen(d.d_name.ptr)];
    }

    void reset()
    {
        rewinddir(dir);
        _empty = false;
    }

    override DirEntry front()
    {
        return currentEntry;
    }

    override void popFront()
    {
        readNextEntry();
    }

    override DirEntry moveFront()
    {
        readNextEntry();
        return currentEntry;
    }

    override bool empty()
    {
        return _empty;
    }

    int opApply(scope int delegate(DirEntry) dg)
    {
        while(!_empty)
        {
            dg(currentEntry);
            readNextEntry();
        }

        return 0;
    }

    int opApply(scope int delegate(size_t, DirEntry) dg)
    {
        size_t i = 0;
        while(!_empty)
        {
            dg(i, currentEntry);
            readNextEntry();
            i++;
        }

        return 0;
    }
}

class StdPosixDirectory: Directory
{
    DIR* dir;
    StdPosixDirEntryRange drange;

    this(string path)
    {
        String pathz = String(path);
        dir = opendir(pathz.ptr);
        pathz.free();
    }

    ~this()
    {
        if (drange)
        {
            Delete(drange);
            drange = null;
        }

        close();
    }

    void close()
    {
        if (dir)
        {
            closedir(dir);
            dir = null;
        }
    }

    StdPosixDirEntryRange contents()
    {
        if (drange)
            drange.reset();
        else
            drange = New!StdPosixDirEntryRange(dir);
        return drange;
    }
}
