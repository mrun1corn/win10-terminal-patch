#pragma once
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <initguid.h>
#include <knownfolders.h>
#include <shlobj.h>
#include <propkey.h>
#include <propsys.h>
#include <shlwapi.h>
#include <wrl/client.h>
#include <memory>
#include <string>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "propsys.lib")
#pragma comment(lib, "ole32.lib")
