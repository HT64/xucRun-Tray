// Purpose: Defines the model and typed result of the tray context menu.
#pragma once

#include <Windows.h>

#include <cstdint>
#include <string>
#include <vector>

#include "BrokerContracts.h"
#include "ClientStatusActions.h"
#include "ClientStatusIcon.h"

namespace xucrun::status_menu
{
	struct Model
	{
		status_icon::BrokerServiceState serviceState;
		bool brokerCommunicationAvailable = false;
		std::uint32_t elevatedProcessCount = 0;
		const std::vector<broker::TrackedProcessListEntry>* trackedProcesses = nullptr;
		const std::vector<broker::StatusIconListEntry>* statusIcons = nullptr;
		std::wstring currentAccount;
		bool currentProcessElevated = false;
	};

	bool HasTrackedProcessWindow(
		const std::vector<broker::TrackedProcessListEntry>& trackedProcesses);
	status_actions::Selection Show(HWND owner, int x, int y, const Model& model);
}
