// Purpose: Defines state and representation of the xucRun tray icon.
// Approach: Models broker and process state, then exposes helpers that derive icon, tooltip, and menu data.
#pragma once

#include <Windows.h>
#include <shellapi.h>

#include <cstdint>
#include <string>

#include "BrokerContracts.h"
#include "ClientBrokerStatus.h"

namespace xucrun::status_icon
{
	using BrokerServiceStatus = broker_status::BrokerServiceStatus;
	using BrokerServiceState = broker_status::BrokerServiceState;

	NOTIFYICONDATAW Build(HWND window, UINT callbackMessage,
		const BrokerServiceState& serviceState,
		bool brokerCommunicationAvailable,
		std::uint32_t elevatedProcessCount,
		bool elevatedProcessWindowActive,
		const broker::ProductVersion& brokerVersion,
		const std::wstring& currentAccount,
		bool currentProcessElevated,
		bool showStatusIdentity);
}