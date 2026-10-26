#include "stdafx.h"

// {7B2D8DFB-D190-344E-BF60-6EAC09922BBF}
DEFINE_PROPERTYKEY(PKEY_WINX_HASH, 0xFB8D2D7B, 0x90D1, 0x4E34, 0xBF, 0x60, 0x6E, 0xAC, 0x09, 0x92, 0x2B, 0xBF, 0x02);

#define CHECKHR(HR, MESSAGE) \
    if(FAILED(HR)) \
    { \
        if(MESSAGE) wprintf(L"%s (hr: %X)\r\n", MESSAGE, HR); \
        return HR; \
    }

#define GUID_MAX_LEN 40

using namespace std;
using Microsoft::WRL::ComPtr;

HRESULT GeneralizePath(const wchar_t*, wchar_t*, size_t);

int wmain(int argc, wchar_t* argv[])
{
    if(argc != 2)
    {
        wprintf(L"usage: hashlnk <.lnk file>\n\n");
        return ERROR_BAD_ARGUMENTS;
    }

    DWORD bufferSize = GetFullPathNameW(argv[1], 0, nullptr, nullptr);
    if(bufferSize == 0)
    {
        wprintf(L"Specified path is invalid.\n");
        return ERROR_INVALID_PARAMETER;
    }

    unique_ptr<wchar_t[]> resolvedTarget(new wchar_t[bufferSize]);
    GetFullPathNameW(argv[1], bufferSize, resolvedTarget.get(), nullptr);

    if(!PathFileExistsW(resolvedTarget.get()))
    {
        wprintf(L"Specified file does not exist.\n");
        return ERROR_FILE_NOT_FOUND;
    }

    HRESULT hr = CoInitialize(nullptr);
    CHECKHR(hr, L"Failed to initialize COM.");

    ComPtr<IShellItem2> lnk;
    hr = SHCreateItemFromParsingName(resolvedTarget.get(), nullptr, IID_PPV_ARGS(&lnk));
    CHECKHR(hr, L"Failed to create shell item.");

    PWSTR targetPath = nullptr;
    hr = lnk->GetString(PKEY_Link_TargetParsingPath, &targetPath);
    CHECKHR(hr, L"Failed to retrieve target path.");

    unique_ptr<wchar_t[]> generalizedPath(new wchar_t[MAX_PATH]);
    hr = GeneralizePath(targetPath, generalizedPath.get(), MAX_PATH);
    if(FAILED(hr))
    {
        CoTaskMemFree(targetPath);
        return hr;
    }

    PWSTR targetArgs = nullptr;
    hr = lnk->GetString(PKEY_Link_Arguments, &targetArgs);
    if(FAILED(hr) && hr != HRESULT_FROM_WIN32(ERROR_NOT_FOUND))
    {
        wprintf(L"Failed to retrieve target arguments.\n");
        CoTaskMemFree(targetPath);
        return hr;
    }

    const wchar_t salt[] = L"do not prehash links.  this should only be done by the user.";

    wstring blob = generalizedPath.get();
    if(targetArgs)
    {
        blob += targetArgs;
    }
    blob += salt;

    CoTaskMemFree(targetPath);
    if(targetArgs) CoTaskMemFree(targetArgs);

    int lowerCaseLength = LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE, blob.data(), (int)blob.size(), nullptr, 0, nullptr, nullptr, 0);
    if(!lowerCaseLength)
    {
        wprintf(L"Failed to lowercase blob string.\n");
        return GetLastError();
    }

    unique_ptr<wchar_t[]> hashableBlob(new wchar_t[lowerCaseLength]);
    LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE, blob.data(), (int)blob.size(), hashableBlob.get(), lowerCaseLength, nullptr, nullptr, 0);

    ULONG hash = 0;
    hr = HashData(reinterpret_cast<BYTE*>(hashableBlob.get()), lowerCaseLength * sizeof(wchar_t), reinterpret_cast<BYTE*>(&hash), sizeof(hash));
    CHECKHR(hr, L"Failed to hash data.");

    ComPtr<IPropertyStore> store;
    hr = lnk->GetPropertyStore(GPS_READWRITE, IID_PPV_ARGS(&store));
    CHECKHR(hr, L"Failed to get property store.");

    PROPVARIANT propValue = {0};
    propValue.ulVal = hash;
    propValue.vt = VT_UI4;

    hr = store->SetValue(PKEY_WINX_HASH, propValue);
    CHECKHR(hr, L"Failed to set property store value.");

    hr = store->Commit();
    CHECKHR(hr, L"Failed to write changes to .lnk.");

    wprintf(L"Hash generated and applied (0x%08X)\n", hash);

    CoUninitialize();

    return 0;
}

HRESULT GeneralizePath(const wchar_t* originalPath, wchar_t* generalizedPath, size_t capacity)
{
    wstring resultingPath;
    HRESULT hr = ERROR_SUCCESS;

    BOOL isRunningUnderEmulation = FALSE;
    IsWow64Process(GetCurrentProcess(), &isRunningUnderEmulation);

    KNOWNFOLDERID guids[3];
    const wchar_t* tokens[3];

    if(isRunningUnderEmulation)
    {
        tokens[0] = L"%ProgramW6432%";
        guids[0] = FOLDERID_ProgramFiles;
    }
    else
    {
        tokens[0] = L"%ProgramFiles%";
        guids[0] = FOLDERID_ProgramFiles;
    }

    tokens[1] = L"%SystemRoot%\\System32";
    guids[1] = FOLDERID_System;

    tokens[2] = L"%SystemRoot%";
    guids[2] = FOLDERID_Windows;

    for(int i = 0; i < sizeof(guids) / sizeof(KNOWNFOLDERID); ++i)
    {
        unique_ptr<wchar_t[]> folderPath(new wchar_t[MAX_PATH]);
        
        int numCharsInPath = ExpandEnvironmentStringsW(tokens[i], folderPath.get(), MAX_PATH);
        if(numCharsInPath == 0)
        {
            CHECKHR(hr, L"Failed to resolve known folder location.");
        }

        --numCharsInPath;

        int numCommonChars = PathCommonPrefixW(folderPath.get(), originalPath, NULL);
        if(numCommonChars < numCharsInPath)
        {
            continue;
        }

        unique_ptr<wchar_t[]> guid(new wchar_t[GUID_MAX_LEN]);
        if(!StringFromGUID2(guids[i], guid.get(), GUID_MAX_LEN))
        {
            hr = E_OUTOFMEMORY;
            CHECKHR(hr, L"Failed to derive string from known folder GUID.");
        }

        resultingPath += guid.get();
        resultingPath += originalPath + numCommonChars;
        break;
    }

    if(resultingPath.empty())
    {
        resultingPath = originalPath;
    }

    ZeroMemory(generalizedPath, capacity * sizeof(wchar_t));
    if(resultingPath.copy(generalizedPath, capacity, 0) != resultingPath.length())
    {
        hr = GetLastError();
        CHECKHR(hr, L"Failed to write resulting path to specified buffer.");
    }

    return hr;
}
