// Purpose: Queries and changes xucRun Tray autostart for the current account.
// Approach: Validates the active startup mechanism and applies changes through its public maintenance boundary.
#pragma once

#include <Windows.h>

#include <string>

namespace xucrun::autostart
{
	enum class Status
	{
		Enabled,
		Disabled,
		Unavailable
	};

	bool GetMaintenanceScriptPath(std::wstring& path);
	Status QueryStatus();
	bool SetEnabled(HWND owner, bool enabled);
	int ShowStatus(HWND owner);
}
