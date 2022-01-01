/*
Copyright (c) 2015-2022 Timur Gafarov

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
 * GC-free filesystem
 * Copyright: Timur Gafarov 2015-2022.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov
 */
module dlib.filesystem.stdfs;

import core.stdc.stdio;
import std.file;
import std.string;
import std.datetime;
import dlib.core.memory;
import dlib.core.stream;
import dlib.container.dict;
import dlib.container.array;
import dlib.text.str;
import dlib.filesystem.filesystem;

version(Posix)
{
    import dlib.filesystem.posix.common;
    import dlib.filesystem.stdposixdir;
}
version(Windows)
{
    import std.stdio;
    import dlib.filesystem.windows.common;
    import dlib.filesystem.stdwindowsdir;
}

import dlib.text.utils;
import dlib.text.utf16;

// TODO: where are these definitions in druntime?
version(Windows)
{
   extern(C) int _wmkdir(const wchar*);
   extern(C) int _wremove(const wchar*);

   extern(Windows) int RemoveDirectoryW(const wchar*);
}

/// InputStream that wraps FILE
class StdInFileStream: InputStream
{
    FILE* file;
    StreamSize _size;
    bool eof;

    this(FILE* file)
    {
        this.file = file;

        fseek(file, 0, SEEK_END);
        _size = ftell(file);
        fseek(file, 0, SEEK_SET);

        eof = false;
    }

    ~this()
    {
        fclose(file);
    }

    StreamPos getPosition() @property
    {
        return ftell(file);
    }

    bool setPosition(StreamPos p)
    {
        import core.stdc.config: c_long;
        return !fseek(file, cast(c_long)p, SEEK_SET);
    }

    StreamSize size()
    {
        return _size;
    }

    void close()
    {
        fclose(file);
    }

    bool seekable()
    {
        return true;
    }

    bool readable()
    {
        return !eof;
    }

    size_t readBytes(void* buffer, size_t count)
    {
        auto bytesRead = fread(buffer, 1, count, file);
        if (count > bytesRead)
            eof = true;
        return bytesRead;
    }
}

/// OutputStream that wraps FILE
class StdOutFileStream: OutputStream
{
    FILE* file;
    bool _writeable;

    this(FILE* file)
    {
        this.file = file;
        this._writeable = true;
    }

    ~this()
    {
        fclose(file);
    }

    StreamPos getPosition() @property
    {
        return 0;
    }

    bool setPosition(StreamPos pos)
    {
        return false;
    }

    StreamSize size()
    {
        return 0;
    }

    void close()
    {
        fclose(file);
    }

    bool seekable()
    {
        return false;
    }

    void flush()
    {
        fflush(file);
    }

    bool writeable()
    {
        return _writeable;
    }

    size_t writeBytes(const void* buffer, size_t count)
    {
        size_t res = fwrite(buffer, 1, count, file);
        if (res != count)
            _writeable = false;
        return res;
    }
}

/// IOStream that wraps FILE
class StdIOStream: IOStream
{
    FILE* file;
    StreamSize _size;
    bool _eof;
    bool _writeable;

    this(FILE* file)
    {
        this.file = file;
        this._writeable = true;

        fseek(file, 0, SEEK_END);
        this._size = ftell(file);
        fseek(file, 0, SEEK_SET);

        this._eof = false;
    }

    ~this()
    {
        fclose(file);
    }

    StreamPos getPosition() @property
    {
        return ftell(file);
    }

    bool setPosition(StreamPos p)
    {
        import core.stdc.config : c_long;
        return !fseek(file, cast(c_long)p, SEEK_SET);
    }

    StreamSize size()
    {
        return _size;
    }

    void close()
    {
        fclose(file);
    }

    bool seekable()
    {
        return true;
    }

    bool readable()
    {
        return !_eof;
    }

    size_t readBytes(void* buffer, size_t count)
    {
        auto bytesRead = fread(buffer, 1, count, file);
        if (count > bytesRead)
            _eof = true;
        return bytesRead;
    }

    void flush()
    {
        fflush(file);
    }

    bool writeable()
    {
        return _writeable;
    }

    size_t writeBytes(const void* buffer, size_t count)
    {
        size_t res = fwrite(buffer, 1, count, file);
        if (res != count)
            _writeable = false;
        return res;
    }
}

/// FileSystem that wraps libc filesystem functions + some Posix and WinAPI parts for additional functionality
class StdFileSystem: FileSystem
{
    Dict!(Directory, string) openedDirs;
    Array!string openedDirPaths;

    this()
    {
        openedDirs = New!(Dict!(Directory, string));
    }

    ~this()
    {
        foreach(k, v; openedDirs)
            Delete(v);
        Delete(openedDirs);

        foreach(p; openedDirPaths)
            Delete(p);
        openedDirPaths.free();
    }

    bool stat(string filename, out FileStat stat)
    {
        if (std.file.exists(filename))
        {
            with(stat)
            {
                version (Posix)
                {
                    stat_t st;
                    String filenamez = String(filename);
                    stat_(filenamez.ptr, &st);
                    filenamez.free();

                    isFile = S_ISREG(st.st_mode);
                    isDirectory = S_ISDIR(st.st_mode);
                    sizeInBytes = st.st_size;
                    creationTimestamp = SysTime(unixTimeToStdTime(st.st_ctime));
                    auto modificationStdTime = unixTimeToStdTime(st.st_mtime);
                    static if (is(typeof(st.st_mtimensec)))
                    {
                        modificationStdTime += st.st_mtimensec / 100;
                    }
                    modificationTimestamp = SysTime(modificationStdTime);

                    if ((st.st_mode & S_IRUSR) | (st.st_mode & S_IRGRP) | (st.st_mode & S_IROTH))
                        permissions |= PRead;
                    if ((st.st_mode & S_IWUSR) | (st.st_mode & S_IWGRP) | (st.st_mode & S_IWOTH))
                        permissions |= PWrite;
                    if ((st.st_mode & S_IXUSR) | (st.st_mode & S_IXGRP) | (st.st_mode & S_IXOTH))
                        permissions |= PExecute;
                }
                else version(Windows)
                {
                    wchar[] filename_utf16 = convertUTF8toUTF16(filename, true);

                    WIN32_FILE_ATTRIBUTE_DATA data;

                    if (!GetFileAttributesExW(filename_utf16.ptr, GET_FILEEX_INFO_LEVELS.GetFileExInfoStandard, &data))
                        return false;

                    if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                        isDirectory = true;
                    else
                        isFile = true;

                    sizeInBytes = (cast(FileSize) data.nFileSizeHigh << 32) | data.nFileSizeLow;
                    creationTimestamp = SysTime(FILETIMEToStdTime(&data.ftCreationTime));
                    modificationTimestamp = SysTime(FILETIMEToStdTime(&data.ftLastWriteTime));

                    permissions = 0;

                    PACL pacl;
                    PSECURITY_DESCRIPTOR secDesc;
                    TRUSTEE_W trustee;
                    trustee.pMultipleTrustee = null;
                    trustee.MultipleTrusteeOperation = MULTIPLE_TRUSTEE_OPERATION.NO_MULTIPLE_TRUSTEE;
                    trustee.TrusteeForm = TRUSTEE_FORM.TRUSTEE_IS_NAME;
                    trustee.TrusteeType = TRUSTEE_TYPE.TRUSTEE_IS_UNKNOWN;
                    trustee.ptstrName = cast(wchar*)"CURRENT_USER"w.ptr;
                    GetNamedSecurityInfoW(filename_utf16.ptr, SE_OBJECT_TYPE.SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, null, null, &pacl, null, &secDesc);
                    if (pacl)
                    {
                        uint access;
                        GetEffectiveRightsFromAcl(pacl, &trustee, &access);

                        if (access & ACTRL_FILE_READ)
                            permissions |= PRead;
                        if ((access & ACTRL_FILE_WRITE) && !(data.dwFileAttributes & FILE_ATTRIBUTE_READONLY))
                            permissions |= PWrite;
                        if (access & ACTRL_FILE_EXECUTE)
                            permissions |= PExecute;
                    }

                    Delete(filename_utf16);
                }
                else
                {
                    isFile = std.file.isFile(filename);
                    isDirectory = std.file.isDir(filename);
                    sizeInBytes = std.file.getSize(filename);
                    getTimes(filename,
                        modificationTimestamp,
                        modificationTimestamp);
                }
            }
            return true;
        }
        else
            return false;
    }

    StdInFileStream openForInput(string filename)
    {
        version(Posix)
        {
            String filenamez = String(filename);
            FILE* file = fopen(filenamez.ptr, "rb");
            filenamez.free();
        }
        version(Windows)
        {
            wchar[] filename_utf16 = convertUTF8toUTF16(filename, true);
            wchar[] mode_utf16 = convertUTF8toUTF16("rb", true);
            FILE* file = _wfopen(filename_utf16.ptr, mode_utf16.ptr);
            Delete(filename_utf16);
            Delete(mode_utf16);
        }
        return New!StdInFileStream(file);
    }

    StdOutFileStream openForOutput(string filename, uint creationFlags = FileSystem.create)
    {
        version(Posix)
        {
            String filenamez = String(filename);
            FILE* file = fopen(filenamez.ptr, "wb");
            filenamez.free();
        }
        version(Windows)
        {
            wchar[] filename_utf16 = convertUTF8toUTF16(filename, true);
            wchar[] mode_utf16 = convertUTF8toUTF16("wb", true);
            FILE* file = _wfopen(filename_utf16.ptr, mode_utf16.ptr);
            Delete(filename_utf16);
            Delete(mode_utf16);
        }
        return New!StdOutFileStream(file);
    }

    StdIOStream openForIO(string filename, uint creationFlags = FileSystem.create)
    {
        version(Posix)
        {
            String filenamez = String(filename);
            FILE* file = fopen(filename.ptr, "rb+");
            filenamez.free();
        }
        version(Windows)
        {
            wchar[] filename_utf16 = convertUTF8toUTF16(filename, true);
            wchar[] mode_utf16 = convertUTF8toUTF16("rb+", true);
            FILE* file = _wfopen(filename_utf16.ptr, mode_utf16.ptr);
            Delete(filename_utf16);
            Delete(mode_utf16);
        }
        return New!StdIOStream(file);
    }

    Directory openDir(string path)
    {
        FileStat ps;
        if (!stat(path, ps))
            return null;
        if (!ps.isDirectory)
            return null;
    
        if (path in openedDirs)
        {
            Directory d = openedDirs[path];
            Delete(d);
        }

        Directory dir;

        version(Posix)
        {
            dir = New!StdPosixDirectory(path);
        }
        version(Windows)
        {
            string s = catStr(path, "\\*.*");
            wchar[] ws = convertUTF8toUTF16(s, true);
            Delete(s);
            dir = New!StdWindowsDirectory(ws.ptr);
        }

        auto p = New!(char[])(path.length);
        p[] = path[];
        openedDirPaths.append(cast(string)p);
        openedDirs[cast(string)p] = dir;
        
        return dir;
    }

    bool createDir(string path, bool recursive = true)
    {
        version(Posix)
        {
            String pathz = String(path);
            int res = mkdir(pathz.ptr, 777);
            pathz.free();
            return (res == 0);
        }
        version(Windows)
        {
            wchar[] wp = convertUTF8toUTF16(path, true);
            int res = _wmkdir(wp.ptr);
            Delete(wp);
            return (res == 0);
        }
    }

    bool remove(string path, bool recursive = true)
    {
        version(Posix)
        {
            String pathz = String(path);
            int res = core.stdc.stdio.remove(pathz.ptr);
            pathz.free();
            return (res == 0);
        }
        version(Windows)
        {
            import std.stdio;
            bool res;
            if (std.file.isDir(path))
            {
                if (recursive)
                foreach(e; openDir(path).contents)
                {
                    string path2 = catStr(path, "\\");
                    string path3 = catStr(path2, e.name);
                    Delete(path2);
                    this.remove(path3, recursive);
                    Delete(path3);
                }

                wchar[] wp = convertUTF8toUTF16(path, true);
                res = RemoveDirectoryW(wp.ptr) != 0;
                Delete(wp);
            }
            else
            {
                wchar[] wp = convertUTF8toUTF16(path, true);
                res = _wremove(wp.ptr) == 0;
                Delete(wp);
            }
            return res;
        }
    }
}

///
version(Windows)
unittest
{
    StdFileSystem fs = New!StdFileSystem();
    
    string path = "tests/stdfs";
    
    FileStat ps;
    if (fs.stat(path, ps))
    {
        fs.remove(path, true);
        assert(fs.openDir(path) is null);
    }
    assert(fs.createDir(path, true));
    
    string filename = "tests/stdfs/hello_world.txt";
    
    OutputStream outp = fs.openForOutput(filename, FileSystem.create | FileSystem.truncate);
    assert(outp);
    string data = "Hello, World!\n";
    assert(outp.writeArray(data));
    outp.close();
    
    InputStream inp = fs.openForInput(filename);
    assert(inp);
    string text = readText(inp);
    assert(text == data);
    inp.close();
    
    FileStat s;
    assert(fs.stat(filename, s));
    assert(s.isFile);
    assert(s.sizeInBytes == 14);
}

/// Reads string from InputStream and stores it in unmanaged memory
string readText(InputStream istrm)
{
    ubyte[] arr = New!(ubyte[])(cast(size_t)istrm.size);
    istrm.fillArray(arr);
    istrm.setPosition(0);
    return cast(string)arr;
}

/// Reads struct from InputStream
T readStruct(T)(InputStream istrm) if (is(T == struct))
{
    T res;
    istrm.readBytes(&res, T.sizeof);
    return res;
}

enum MAX_PATH_LEN = 4096;

struct PathBuilder
{
    // TODO: use dlib.text.unmanaged.String instead
    char[MAX_PATH_LEN] str;
    uint length = 0;

    void append(string s)
    {
        if (length && str[length-1] != '/')
        {
            str[length] = '/';
            length++;
        }

        str[length..length+s.length] = s[];
        length += s.length;
    }

    string toString() return
    {
        if (length)
            return cast(string)(str[0..length]);
        else
            return "";
    }
}

struct RecursiveFileIterator
{
    PathBuilder pb;
    ReadOnlyFileSystem rofs;
    string directory;
    bool rec;

    this(ReadOnlyFileSystem fs, string dir, bool recursive)
    {
        rofs = fs;
        directory = dir;
        pb.append(dir);
        rec = recursive;
    }

    int opApply(scope int delegate(string path, ref dlib.filesystem.filesystem.DirEntry) dg)
    {
        int result = 0;

        if (!rofs)
            return 0;

        foreach(e; rofs.openDir(directory).contents)
        {
            uint pathPos = pb.length;
            pb.append(e.name);

            string oldPath = directory;
            directory = pb.toString;

            result = dg(directory, e);
            if (result)
                break;

            if (e.isDirectory && rec)
                result = opApply(dg);

            directory = oldPath;
            pb.length = pathPos;

            if (result)
                break;
        }

        return 0;
    }

    int opApply(scope int delegate(ref dlib.filesystem.filesystem.DirEntry) dg)
    {
        int result = 0;

        auto dir = rofs.openDir(directory);

        foreach(e; dir.contents)
        {
            uint pathPos = pb.length;
            pb.append(e.name);

            string oldPath = directory;
            directory = pb.toString;

            result = dg(e);
            if (result)
                break;

            if (e.isDirectory)
                result = opApply(dg);

            directory = oldPath;
            pb.length = pathPos;

            if (result)
                break;
        }

        return 0;
    }
}

/// Enumerate directory contents, optionally recursive
RecursiveFileIterator traverseDir(ReadOnlyFileSystem rofs, string baseDir, bool recursive)
{
    FileStat s;
    if (!rofs.stat(baseDir, s))
        return RecursiveFileIterator(null, baseDir, recursive);
    else
        return RecursiveFileIterator(rofs, baseDir, recursive);
}
