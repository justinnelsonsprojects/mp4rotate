// mp4rotate_shell.dll - Windows 11 File Explorer context menu handler.
//
// Registers ONE top-level IExplorerCommand, "MP4 Rotate", whose submenu we build
// ourselves: Rotate left, Rotate right, separator, Rotate 180. (If a package declares
// several commands instead, Windows groups them itself and sorts them alphabetically.)
// The DLL is declared in the sparse MSIX package (package\AppxManifest.xml), which is
// what lets the menu appear in the main Windows 11 context menu rather than only under
// "Show more options". Invoking a command runs mp4rotate.exe (next to this DLL) with
// every selected file on one command line.

#include <windows.h>
#include <shobjidl_core.h>
#include <shlwapi.h>
#include <wrl/module.h>
#include <wrl/implements.h>
#include <wrl/client.h>
#include <string>
#include <vector>
#include "resource.h"

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "runtimeobject.lib")

using namespace Microsoft::WRL;

extern "C" IMAGE_DOS_HEADER __ImageBase;

static std::wstring ModulePath()
{
    wchar_t path[MAX_PATH * 4];
    DWORD len = GetModuleFileNameW(reinterpret_cast<HMODULE>(&__ImageBase), path, ARRAYSIZE(path));
    return std::wstring(path, len);
}

static std::wstring ModuleDir()
{
    std::wstring path = ModulePath();
    return path.substr(0, path.find_last_of(L'\\'));
}

// Explorer follows the "app mode" theme setting.
static bool IsLightTheme()
{
    DWORD value = 1, size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                     L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &value, &size) != ERROR_SUCCESS)
        return true;
    return value != 0;
}

static void Launch(std::wstring commandLine)
{
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = {};
    std::wstring dir = ModuleDir();
    if (CreateProcessW(nullptr, commandLine.data(), nullptr, nullptr, FALSE, 0, nullptr, dir.c_str(), &si, &pi))
    {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
    else
    {
        MessageBoxW(nullptr, L"Could not start mp4rotate.exe. Try reinstalling MP4 Rotate.", L"MP4 Rotate", MB_ICONERROR);
    }
}

class RotateCommand : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IExplorerCommand, IObjectWithSite>
{
protected:
    virtual const wchar_t* Title() const = 0;
    virtual const wchar_t* Argument() const = 0;
    virtual int IconId(bool lightTheme) const = 0;

public:
    // IExplorerCommand
    IFACEMETHODIMP GetTitle(IShellItemArray*, PWSTR* name) override
    {
        return SHStrDupW(Title(), name);
    }

    IFACEMETHODIMP GetIcon(IShellItemArray*, PWSTR* icon) override
    {
        std::wstring location = ModulePath() + L",-" + std::to_wstring(IconId(IsLightTheme()));
        return SHStrDupW(location.c_str(), icon);
    }

    IFACEMETHODIMP GetToolTip(IShellItemArray*, PWSTR* infoTip) override
    {
        *infoTip = nullptr;
        return E_NOTIMPL;
    }

    IFACEMETHODIMP GetCanonicalName(GUID* guid) override
    {
        *guid = GUID_NULL;
        return S_OK;
    }

    IFACEMETHODIMP GetState(IShellItemArray*, BOOL, EXPCMDSTATE* state) override
    {
        *state = ECS_ENABLED;
        return S_OK;
    }

    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override
    {
        *flags = ECF_DEFAULT;
        return S_OK;
    }

    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** enumCommands) override
    {
        *enumCommands = nullptr;
        return E_NOTIMPL;
    }

    IFACEMETHODIMP Invoke(IShellItemArray* items, IBindCtx*) override
    {
        if (!items)
            return E_INVALIDARG;
        DWORD count = 0;
        HRESULT hr = items->GetCount(&count);
        if (FAILED(hr))
            return hr;

        // One process for the whole selection, split only if the command line would
        // exceed the 32K CreateProcess limit.
        const std::wstring base = L"\"" + ModuleDir() + L"\\mp4rotate.exe\" " + Argument();
        std::wstring commandLine = base;
        for (DWORD i = 0; i < count; i++)
        {
            ComPtr<IShellItem> item;
            PWSTR path = nullptr;
            if (FAILED(items->GetItemAt(i, &item)) || FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)))
                continue;
            std::wstring arg = L" \"" + std::wstring(path) + L"\"";
            CoTaskMemFree(path);

            if (commandLine.size() + arg.size() > 30000 && commandLine.size() > base.size())
            {
                Launch(commandLine);
                commandLine = base;
            }
            commandLine += arg;
        }
        if (commandLine.size() > base.size())
            Launch(commandLine);
        return S_OK;
    }

    // IObjectWithSite
    IFACEMETHODIMP SetSite(IUnknown* site) override
    {
        m_site = site;
        return S_OK;
    }

    IFACEMETHODIMP GetSite(REFIID riid, void** site) override
    {
        if (!site)
            return E_POINTER;
        *site = nullptr;
        return m_site ? m_site.CopyTo(riid, site) : E_FAIL;
    }

private:
    ComPtr<IUnknown> m_site;
};

class RotateRightCommand final : public RotateCommand
{
    const wchar_t* Title() const override { return L"Rotate right"; }
    const wchar_t* Argument() const override { return L"right"; }
    int IconId(bool lightTheme) const override { return lightTheme ? IDI_RIGHT_DARK : IDI_RIGHT_LIGHT; }
};

class RotateLeftCommand final : public RotateCommand
{
    const wchar_t* Title() const override { return L"Rotate left"; }
    const wchar_t* Argument() const override { return L"left"; }
    int IconId(bool lightTheme) const override { return lightTheme ? IDI_LEFT_DARK : IDI_LEFT_LIGHT; }
};

class Rotate180Command final : public RotateCommand
{
    const wchar_t* Title() const override { return L"Rotate 180"; }
    const wchar_t* Argument() const override { return L"180"; }
    int IconId(bool lightTheme) const override { return lightTheme ? IDI_180_DARK : IDI_180_LIGHT; }
};

class SeparatorCommand final : public RotateCommand
{
    const wchar_t* Title() const override { return L""; }
    const wchar_t* Argument() const override { return L""; }
    int IconId(bool lightTheme) const override { return lightTheme ? IDI_RIGHT_DARK : IDI_RIGHT_LIGHT; }

public:
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override
    {
        *flags = ECF_ISSEPARATOR;
        return S_OK;
    }

    IFACEMETHODIMP Invoke(IShellItemArray*, IBindCtx*) override { return S_OK; }
};

class SubCommandEnumerator final : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IEnumExplorerCommand>
{
public:
    explicit SubCommandEnumerator(std::vector<ComPtr<IExplorerCommand>> commands) : m_commands(std::move(commands)) {}

    IFACEMETHODIMP Next(ULONG count, IExplorerCommand** commands, ULONG* fetched) override
    {
        ULONG n = 0;
        for (; n < count && m_index < m_commands.size(); n++, m_index++)
            m_commands[m_index].CopyTo(&commands[n]);
        if (fetched)
            *fetched = n;
        return n == count ? S_OK : S_FALSE;
    }

    IFACEMETHODIMP Skip(ULONG count) override
    {
        m_index = (std::min)(m_index + count, m_commands.size());
        return S_OK;
    }

    IFACEMETHODIMP Reset() override
    {
        m_index = 0;
        return S_OK;
    }

    IFACEMETHODIMP Clone(IEnumExplorerCommand** enumCommands) override
    {
        *enumCommands = nullptr;
        return E_NOTIMPL;
    }

private:
    std::vector<ComPtr<IExplorerCommand>> m_commands;
    size_t m_index = 0;
};

// The one registered command. This CLSID must match package\AppxManifest.xml.
class __declspec(uuid("63250DD9-966C-4225-8719-C7FC5F4FED90")) MenuCommand final : public RotateCommand
{
    const wchar_t* Title() const override { return L"MP4 Rotate"; }
    const wchar_t* Argument() const override { return L""; }
    int IconId(bool lightTheme) const override { return lightTheme ? IDI_RIGHT_DARK : IDI_RIGHT_LIGHT; }

public:
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override
    {
        *flags = ECF_HASSUBCOMMANDS;
        return S_OK;
    }

    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** enumCommands) override
    {
        std::vector<ComPtr<IExplorerCommand>> commands;
        commands.push_back(Make<RotateLeftCommand>());
        commands.push_back(Make<RotateRightCommand>());
        commands.push_back(Make<SeparatorCommand>());
        commands.push_back(Make<Rotate180Command>());
        return Make<SubCommandEnumerator>(std::move(commands)).CopyTo(enumCommands);
    }

    IFACEMETHODIMP Invoke(IShellItemArray*, IBindCtx*) override { return E_NOTIMPL; }
};

CoCreatableClass(MenuCommand)

STDAPI DllCanUnloadNow()
{
    return Module<InProc>::GetModule().GetObjectCount() == 0 ? S_OK : S_FALSE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void** instance)
{
    return Module<InProc>::GetModule().GetClassObject(clsid, riid, instance);
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
        DisableThreadLibraryCalls(module);
    return TRUE;
}
