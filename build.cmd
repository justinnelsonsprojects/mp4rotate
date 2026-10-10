@echo off
rem Builds everything and the signed installer (installer\Output):
rem   1. mp4rotate.exe          (native, dotnet publish)
rem   2. mp4rotate_shell.dll    (Windows 11 context menu handler, C++)
rem   3. mp4rotate.msix         (sparse package that registers the handler)
rem   4. the Inno Setup installer, which signs the exe, dll, msix, setup and uninstaller
rem Pass NOSIGN for an unsigned test build:  build.cmd NOSIGN
setlocal
cd /d "%~dp0"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
rem Native AOT's linker step needs vswhere.exe on PATH.
set "PATH=%PATH%;%ProgramFiles(x86)%\Microsoft Visual Studio\Installer"

echo === mp4rotate.exe
dotnet publish -c Release -nologo || exit /b 1

echo === mp4rotate_shell.dll
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe`) do set "MSBUILD=%%i"
"%MSBUILD%" shell\mp4rotate_shell.vcxproj -p:Configuration=Release -p:Platform=x64 -nologo -v:minimal || exit /b 1

echo === mp4rotate.msix
set "MAKEAPPX="
for /d %%d in ("%ProgramFiles(x86)%\Windows Kits\10\bin\10.*") do if exist "%%d\x64\makeappx.exe" set "MAKEAPPX=%%d\x64\makeappx.exe"
if not defined MAKEAPPX (echo makeappx.exe not found - install the Windows SDK & exit /b 1)
if not exist package\out mkdir package\out
rem /nv: the manifest's exe and dll live in the external location, not in the package.
"%MAKEAPPX%" pack /f package\mapping.txt /p package\out\mp4rotate.msix /nv /o >nul || exit /b 1

echo === Installer
set "ISCC=%ProgramFiles(x86)%\Inno Setup 5\ISCC.exe"
if /i "%~1"=="NOSIGN" (
    "%ISCC%" /Q /DNOSIGN installer\mp4rotate.iss || exit /b 1
) else (
    "%ISCC%" /Q installer\mp4rotate.iss || exit /b 1
)
echo Done: installer\Output
