// Purpose: Declares Tray-specific command-line help and information views.
// Approach: Presents localized read-only text through the shared client text dialog.
#pragma once

#include <Windows.h>

namespace xucrun::tray_commands
{
	int ShowHelp(HWND owner = nullptr);
	int ShowInfo(HWND owner = nullptr);
}
