// Purpose: Declares Tray status retrieval and presentation operations.
// Approach: Exposes one process-level entry point while keeping Win32 status-loop details private.
#pragma once

#include <Windows.h>

namespace xucrun::broker_status
{
	int RunBrokerStatusIcon(HINSTANCE instance);
}
