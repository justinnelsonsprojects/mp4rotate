// mp4rotate - losslessly rotate MP4/MOV videos by editing the track header (tkhd)
// transformation matrix in place. No re-encoding; works for H.264 and HEVC alike,
// since the rotation lives in the container, not in the video stream.
//
// Usage:
//   mp4rotate left  <file> [file...]   rotate 90 degrees counter-clockwise
//   mp4rotate right <file> [file...]   rotate 90 degrees clockwise
//   mp4rotate 180   <file> [file...]   rotate 180 degrees
//   mp4rotate info  <file> [file...]   show current rotation, change nothing
//
// Installer use (registers the Windows 11 context menu package, see package\AppxManifest.xml):
//   mp4rotate --register | --unregister | --unregister-all
//   mp4rotate --restart-explorer   (Explorer only loads new context menu handlers on start)
//
// This is a windowless (WinExe) app so Explorer never flashes a console. When started from
// a terminal it attaches to that console for output; otherwise errors go to a message box.

using System.Buffers.Binary;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Mp4Rotate;

static partial class Program
{
    const string Usage =
        "Usage: mp4rotate <left|right|180|info> <file> [file...]\n" +
        "       mp4rotate <--register|--unregister|--unregister-all|--restart-explorer>";

    static bool hasConsole;

    static int Main(string[] args)
    {
        hasConsole = AttachConsole(ATTACH_PARENT_PROCESS);

        if (args.Length == 1 && args[0].StartsWith("--"))
            return RunPackageCommand(args[0].ToLowerInvariant());

        int? delta = args.Length < 2 ? -1 : args[0].ToLowerInvariant() switch
        {
            "left" or "ccw" => 270,
            "right" or "cw" => 90,
            "180" => 180,
            "info" => null,
            _ => -1,
        };
        if (delta == -1)
        {
            ReportErrors(Usage);
            return 2;
        }

        var errors = new List<string>();
        foreach (var path in args.Skip(1))
        {
            try
            {
                Mp4File.Rotate(path, delta);
            }
            catch (Exception ex)
            {
                errors.Add($"{path}: {ex.Message}");
            }
        }

        if (errors.Count > 0)
            ReportErrors(errors.Count == 1
                ? $"Could not rotate the video.\n\n{errors[0]}"
                : $"Could not rotate {errors.Count} videos.\n\n{string.Join("\n\n", errors)}");
        return errors.Count == 0 ? 0 : 1;
    }

    static int RunPackageCommand(string command)
    {
        try
        {
            switch (command)
            {
                case "--register": ShellPackage.Register(); break;
                case "--unregister": ShellPackage.Unregister(allUsers: false); break;
                case "--unregister-all": ShellPackage.Unregister(allUsers: true); break;
                case "--restart-explorer": ExplorerRestart.Run(); break;
                default: ReportErrors(Usage); return 2;
            }
            return 0;
        }
        catch (Exception ex)
        {
            // No message box here: these run from the installer and at logon (Active Setup),
            // which check the exit code instead.
            if (hasConsole)
                Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    static void ReportErrors(string message)
    {
        if (hasConsole)
            Console.Error.WriteLine(message);
        else
            MessageBoxW(IntPtr.Zero, message, "MP4 Rotate", MB_ICONERROR);
    }

    const int ATTACH_PARENT_PROCESS = -1;
    const uint MB_ICONERROR = 0x10;

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool AttachConsole(int processId);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int MessageBoxW(IntPtr owner, string text, string caption, uint type);
}

/// <summary>
/// Restarts the current user's Explorer the same way as the taskbar's hidden "Exit Explorer"
/// command (Ctrl+Shift+right-click the taskbar): ask the shell to exit cleanly, then start
/// it again. Must run as the logged-in user, not elevated, or
/// Explorer would come back elevated.
/// </summary>
static partial class ExplorerRestart
{
    const uint WM_EXIT_EXPLORER = 0x5B4;   // WM_USER + 436, what "Exit Explorer" sends

    public static void Run()
    {
        // Timings go to %TEMP%\mp4rotate-restart.log (overwritten each run) for troubleshooting.
        var clock = Stopwatch.StartNew();
        using var log = new StreamWriter(Path.Combine(Path.GetTempPath(), "mp4rotate-restart.log"), append: false);
        void Log(string message) => log.WriteLine($"{clock.ElapsedMilliseconds,6} ms  {message}");

        int session = Process.GetCurrentProcess().SessionId;
        Log($"session {session}, explorer pids: {string.Join(", ", ExplorerProcesses(session).Select(p => p.Id))}");

        // Ask the shell (taskbar) to exit cleanly.
        IntPtr tray = FindWindowW("Shell_TrayWnd", null);
        uint shellPid = 0;
        if (tray != IntPtr.Zero)
        {
            GetWindowThreadProcessId(tray, out shellPid);
            PostMessageW(tray, WM_EXIT_EXPLORER, IntPtr.Zero, IntPtr.Zero);
        }
        Log($"asked shell (pid {shellPid}) to exit");

        // The shell is done once its taskbar window is gone, even if the process lingers.
        bool trayGone = WaitUntil(() => FindWindowW("Shell_TrayWnd", null) == IntPtr.Zero, 3000);
        Log(trayGone ? "taskbar gone" : "taskbar still there after 3 s");

        // Close whatever is left right away: a lingering shell process, folder windows
        // running in a separate process, or a shell that ignored the request.
        bool killedShell = false;
        foreach (var p in ExplorerProcesses(session))
        {
            killedShell |= p.Id == shellPid;
            try { p.Kill(); p.WaitForExit(2000); } catch { }
            Log($"closed explorer pid {p.Id}");
        }

        // Killing the shell process can make Windows restart it by itself; don't start a second one.
        if (killedShell && WaitUntil(() => ExplorerProcesses(session).Any(), 1500))
            Log("Windows restarted the shell itself");
        else if (!ExplorerProcesses(session).Any())
        {
            Process.Start(new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"))
                { UseShellExecute = false });
            Log("started explorer.exe");
        }
        bool trayBack = WaitUntil(() => FindWindowW("Shell_TrayWnd", null) != IntPtr.Zero, 30000);
        Log(trayBack ? "taskbar is back" : "taskbar not back after 30 s");
    }

    static bool WaitUntil(Func<bool> condition, int timeoutMs)
    {
        var sw = Stopwatch.StartNew();
        while (!condition())
        {
            if (sw.ElapsedMilliseconds >= timeoutMs)
                return false;
            Thread.Sleep(50);
        }
        return true;
    }
    static IEnumerable<Process> ExplorerProcesses(int session) =>
        Process.GetProcessesByName("explorer").Where(p => p.SessionId == session);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr FindWindowW(string className, string? windowName);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PostMessageW(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

    [LibraryImport("user32.dll")]
    private static partial uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}

/// <summary>
/// Registers/unregisters the sparse MSIX package that puts "Rotate left/right" in the
/// Windows 11 main context menu. Uses PowerShell's Appx cmdlets, run without a window.
/// </summary>
static class ShellPackage
{
    const string PackageName = "JRNEnterprise.mp4rotate";

    public static void Register()
    {
        // The main context menu (and this package type) only exists on Windows 11.
        if (Environment.OSVersion.Version.Build < 22000)
            return;

        string dir = Quote(AppContext.BaseDirectory.TrimEnd('\\'));
        RunPowerShell(
            $"Get-AppxPackage -Name '{PackageName}' | Remove-AppxPackage; " +
            $"Add-AppxPackage -Path (Join-Path {dir} 'mp4rotate.msix') -ExternalLocation {dir}");
    }

    public static void Unregister(bool allUsers)
    {
        RunPowerShell(allUsers
            ? $"Get-AppxPackage -AllUsers -Name '{PackageName}' | Remove-AppxPackage -AllUsers"
            : $"Get-AppxPackage -Name '{PackageName}' | Remove-AppxPackage");
    }

    static string Quote(string s) => "'" + s.Replace("'", "''") + "'";

    static void RunPowerShell(string script)
    {
        var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"))
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
                                    "$ErrorActionPreference = 'Stop'; " + script })
            psi.ArgumentList.Add(arg);

        using var p = Process.Start(psi)!;
        var stdout = p.StandardOutput.ReadToEndAsync();
        string stderr = p.StandardError.ReadToEnd();
        p.WaitForExit();
        stdout.Wait();
        if (p.ExitCode != 0)
            throw new Exception(stderr.Trim().Length > 0 ? stderr.Trim() : $"PowerShell exited with code {p.ExitCode}");
    }
}

record Box(string Type, int Start, int HeaderSize, int Size)
{
    public int ContentStart => Start + HeaderSize;
    public int End => Start + Size;
}

static class Mp4File
{
    // Refuse to load absurdly large moov boxes into memory (normal ones are KB to a few MB).
    const long MaxMoovSize = 256L * 1024 * 1024;

    /// <summary>
    /// Adds <paramref name="delta"/> degrees (clockwise) to every video track's rotation.
    /// Pass null to only report the current rotation.
    /// </summary>
    public static void Rotate(string path, int? delta)
    {
        bool write = delta != null;

        using (var fs = new FileStream(path, FileMode.Open,
                   write ? FileAccess.ReadWrite : FileAccess.Read,
                   write ? FileShare.None : FileShare.Read))
        {
            var (moovOffset, moovSize, moovHeader) = FindMoov(fs)
                ?? throw new InvalidDataException("no 'moov' box found - not an MP4/MOV file?");
            if (moovSize > MaxMoovSize)
                throw new InvalidDataException($"'moov' box is unexpectedly large ({moovSize} bytes)");

            var buf = new byte[moovSize];
            fs.Position = moovOffset;
            fs.ReadExactly(buf);

            // Phase 1: locate and validate every video track's matrix before touching the file.
            var edits = new List<(int MatrixOffset, int TrackId, int OldAngle)>();
            foreach (var trak in Children(buf, moovHeader, buf.Length).Where(b => b.Type == "trak"))
            {
                var kids = Children(buf, trak.ContentStart, trak.End);
                if (HandlerType(buf, kids) != "vide")
                    continue;

                var tkhd = kids.FirstOrDefault(b => b.Type == "tkhd")
                    ?? throw new InvalidDataException("video track has no 'tkhd' box");
                int c = tkhd.ContentStart;
                int version = buf[c];
                int trackId = (int)BinaryPrimitives.ReadUInt32BigEndian(buf.AsSpan(c + (version == 1 ? 20 : 12)));
                int matrix = c + (version == 1 ? 52 : 40);
                if (matrix + 36 > tkhd.End)
                    throw new InvalidDataException($"track {trackId}: 'tkhd' box too short");

                int angle = AngleFromMatrix(buf.AsSpan(matrix, 36))
                    ?? throw new InvalidDataException($"track {trackId}: matrix is not a plain 0/90/180/270 rotation");
                edits.Add((matrix, trackId, angle));
            }

            if (edits.Count == 0)
                throw new InvalidDataException("no video tracks found");

            // Phase 2: overwrite just the 36-byte matrices. File size and everything else is untouched.
            foreach (var (matrix, trackId, oldAngle) in edits)
            {
                if (!write)
                {
                    Console.WriteLine($"{path}: video track {trackId}: {oldAngle} deg");
                    continue;
                }

                int newAngle = (oldAngle + delta!.Value) % 360;
                WriteMatrix(buf.AsSpan(matrix, 36), newAngle);
                fs.Position = moovOffset + matrix;
                fs.Write(buf, matrix, 36);
                Console.WriteLine($"{path}: video track {trackId}: {oldAngle} -> {newAngle} deg");
            }
        }

        // The modified date is deliberately left updated: Windows' thumbnail cache uses it to
        // detect changes, so restoring it would keep the old (unrotated) preview forever.
        // Then tell Explorer the file changed so open windows refresh the thumbnail now.
        if (write)
            SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSH, Path.GetFullPath(path), IntPtr.Zero);
    }

    const int SHCNE_UPDATEITEM = 0x00002000;
    const uint SHCNF_PATHW = 0x0005;
    const uint SHCNF_FLUSH = 0x1000;

    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);

    /// <summary>Walks top-level boxes without reading their contents (mdat can be gigabytes).</summary>
    static (long Offset, long Size, int HeaderSize)? FindMoov(FileStream fs)
    {
        var hdr = new byte[16];
        long pos = 0;
        while (pos + 8 <= fs.Length)
        {
            fs.Position = pos;
            fs.ReadExactly(hdr, 0, 8);
            long size = BinaryPrimitives.ReadUInt32BigEndian(hdr);
            string type = Encoding.ASCII.GetString(hdr, 4, 4);
            int header = 8;
            if (size == 1)
            {
                fs.ReadExactly(hdr, 8, 8);
                size = (long)BinaryPrimitives.ReadUInt64BigEndian(hdr.AsSpan(8));
                header = 16;
            }
            else if (size == 0)
            {
                size = fs.Length - pos;
            }

            // Anything that doesn't parse as a box is trailing data (e.g. Samsung's SEF trailer).
            if (size < header || pos + size > fs.Length)
                break;
            if (type == "moov")
                return (pos, size, header);
            pos += size;
        }
        return null;
    }

    /// <summary>Parses the child boxes in buf[start..end).</summary>
    static List<Box> Children(byte[] buf, int start, int end)
    {
        var list = new List<Box>();
        int pos = start;
        while (pos + 8 <= end)
        {
            long size = BinaryPrimitives.ReadUInt32BigEndian(buf.AsSpan(pos));
            string type = Encoding.ASCII.GetString(buf, pos + 4, 4);
            int header = 8;
            if (size == 1)
            {
                if (pos + 16 > end)
                    throw new InvalidDataException($"truncated '{type}' box");
                size = (long)BinaryPrimitives.ReadUInt64BigEndian(buf.AsSpan(pos + 8));
                header = 16;
            }
            else if (size == 0)
            {
                size = end - pos;
            }

            if (size < header || pos + size > end)
                throw new InvalidDataException($"corrupt '{type}' box at moov offset {pos}");
            list.Add(new Box(type, pos, header, (int)size));
            pos += (int)size;
        }
        return list;
    }

    /// <summary>Returns the track's handler type from trak/mdia/hdlr ("vide", "soun", ...).</summary>
    static string? HandlerType(byte[] buf, List<Box> trakChildren)
    {
        var mdia = trakChildren.FirstOrDefault(b => b.Type == "mdia");
        if (mdia == null)
            return null;
        var hdlr = Children(buf, mdia.ContentStart, mdia.End).FirstOrDefault(b => b.Type == "hdlr");
        if (hdlr == null || hdlr.ContentStart + 12 > hdlr.End)
            return null;
        // version/flags (4), pre_defined (4), handler_type (4)
        return Encoding.ASCII.GetString(buf, hdlr.ContentStart + 8, 4);
    }

    // The tkhd matrix is 9 big-endian int32s: { a, b, u, c, d, v, x, y, w }.
    // a,b,c,d,x,y are 16.16 fixed point; u,v,w are 2.30 fixed point.
    // Rotation (clockwise, as players display it) is encoded in a,b,c,d:
    //     0: [ 1  0 ; 0  1 ]     90: [ 0  1 ; -1  0 ]
    //   180: [-1  0 ; 0 -1 ]    270: [ 0 -1 ;  1  0 ]
    static int? AngleFromMatrix(ReadOnlySpan<byte> m)
    {
        int a = Math.Sign(BinaryPrimitives.ReadInt32BigEndian(m[0..]));
        int b = Math.Sign(BinaryPrimitives.ReadInt32BigEndian(m[4..]));
        int c = Math.Sign(BinaryPrimitives.ReadInt32BigEndian(m[12..]));
        int d = Math.Sign(BinaryPrimitives.ReadInt32BigEndian(m[16..]));
        return (a, b, c, d) switch
        {
            (1, 0, 0, 1) => 0,
            (0, 1, -1, 0) => 90,
            (-1, 0, 0, -1) => 180,
            (0, -1, 1, 0) => 270,
            _ => null,
        };
    }

    static void WriteMatrix(Span<byte> m, int angle)
    {
        const int One = 0x00010000;   // 1.0 in 16.16
        const int W = 0x40000000;     // 1.0 in 2.30
        var (a, b, c, d) = angle switch
        {
            0 => (One, 0, 0, One),
            90 => (0, One, -One, 0),
            180 => (-One, 0, 0, -One),
            270 => (0, -One, One, 0),
            _ => throw new ArgumentOutOfRangeException(nameof(angle)),
        };
        // Translation is zeroed, matching what Android's MediaMuxer and ffmpeg write.
        int[] values = { a, b, 0, c, d, 0, 0, 0, W };
        for (int i = 0; i < 9; i++)
            BinaryPrimitives.WriteInt32BigEndian(m[(i * 4)..], values[i]);
    }
}
