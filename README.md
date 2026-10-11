# MP4 Rotate

Rotate MP4 videos from the Windows Explorer right-click menu, the same way Windows lets you rotate photos.

Right-click one or more `.mp4` files and choose **MP4 Rotate -&gt; Rotate left / Rotate right / Rotate 180**.

Written by Justin Nelson with help from [Claude Code](https://claude.com/claude-code) for the
[**JustinNelsonsProjects** YouTube channel](https://www.youtube.com/@JustinNelsonsProjects). More projects at [JustinNelsonsProjects.com](https://justinnelsonsprojects.com).

## Features

- **Lossless and instant.** Nothing is re-encoded. The video's rotation is stored as a small
  transformation matrix in the MP4 container, and MP4 Rotate rewrites only those 36 bytes per
  video track, in place. A 5 GB 4K video rotates as fast as a 5 MB one.
- **Works with H.264 and HEVC (H.265)** alike, since the rotation lives in the container, not the video stream.
  Built and tested with videos from a Samsung Galaxy S24.
- **Windows 11 main context menu** (not just "Show more options"), with light/dark-mode icons.
  On Windows 10 the commands appear in the classic context menu.
- **Multiple files at once.** Select several videos and rotate them in one go.
- **Explorer thumbnails update** right after rotating.
- **No .NET runtime or Visual C++ redistributable required.** The tool is a single native exe.

## Install

Download the installer from the [Releases](../../releases) page and run it. Setup installs for all users
and offers to restart Windows Explorer at the end; Windows 11 only loads new context menu commands when
Explorer starts. (Your taskbar and desktop disappear for a moment while it restarts. That's normal.)

## Command line

`mp4rotate.exe` can also be used directly:

```
mp4rotate left  <file> [file...]    rotate 90 degrees counter-clockwise
mp4rotate right <file> [file...]    rotate 90 degrees clockwise
mp4rotate 180   <file> [file...]    rotate 180 degrees
mp4rotate info  <file> [file...]    show the current rotation, change nothing
```

It's a windowless program (so Explorer never flashes a console window). In PowerShell, pipe it to
`Out-String` to wait for its output, e.g. `mp4rotate info video.mp4 | Out-String`.

## How it works

Every MP4 track has a track header box (`moov/trak/tkhd`) containing a 3x3 matrix that tells players how
to transform the video when displaying it. Phones don't actually record portrait video sideways; they
record in the sensor's orientation and set this matrix. MP4 Rotate:

1. Walks the top-level boxes to find `moov`, skipping the (huge) `mdat` media data without reading it.
2. Finds every video track (`hdlr` type `vide`) and reads its current rotation from the matrix.
3. Writes the new rotation matrix back over the old one. File size and everything else stay unchanged.

The Windows 11 menu is an `IExplorerCommand` shell extension (`shell/`) registered through a
*sparse MSIX package* (`package/`), which is what gives third-party commands a place in the new menu.

## Building from source

Requirements:

- Visual Studio 2022 with the **Desktop development with C++** workload
- .NET 9 SDK
- Windows 10/11 SDK (for `makeappx.exe`)
- Inno Setup 5.5.9

Then run:

```
build.cmd           (signed build; needs a SignTool named "AzureSign" configured in Inno Setup)
build.cmd NOSIGN    (unsigned build)
```

The installer is written to `installer\Output`.

**If you fork this:** Windows only registers the context-menu package if `mp4rotate.msix` is signed by a
certificate the PC trusts, and the `Publisher` in `package\AppxManifest.xml` must exactly match that
certificate's subject. Change the `Publisher` to your own certificate's subject and set up your own SignTool.
An unsigned build installs fine, but the Windows 11 menu won't appear.

### Project layout

| Path | What it is |
| --- | --- |
| `Program.cs` | `mp4rotate.exe`: the MP4 rotation itself, plus package registration and Explorer restart helpers |
| `shell/` | `mp4rotate_shell.dll`: the Explorer context menu (C++ `IExplorerCommand`) |
| `package/` | Sparse MSIX package manifest and logos |
| `installer/` | Inno Setup script and artwork |
| `tools/` | Scripts that generate the icons |

## Contributing

This project is published as-is for viewers and anyone curious how it works. **Pull requests are not
accepted**, but you're welcome to fork it and make it your own under the terms of the GPL-3.0 license.

## License

[GPL-3.0](LICENSE). Copyright (c) 2026 Justin Nelson / JRN Enterprise Inc.
