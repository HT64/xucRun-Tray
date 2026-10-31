// Purpose: Defines typed tray actions selected from the broker status menu.
// Approach: Models action kinds and selections, and exposes the command-launch and dispatch boundary.
#pragma once

#include <Windows.h>

#include "BrokerContracts.h"

namespace xucrun::status_actions
{
	enum class Action
	{
		None,
		CreateCredential,
		ShowCredentials,
		DeleteCredential,
		ShowApprovals,
		ResetApprovals,
		AdministrativeStatus,
		RunAudit,
		ShowCoreHelp,
		ShowTrayHelp,
		ShowCoreInfo,
		ShowTrayInfo,
		ShowLogFile,
		DeleteLogFile,
		DeleteAllLogFiles,
		ShowBrokerEvents,
		SetLanguageGerman,
		SetLanguageEnglish,
		SetLanguageAutomatic,
		EnableAutostart,
		DisableAutostart,
		Service,
		Exit,
		ActivateStatusIcon,
		ActivateProcessWindow
	};

	struct Selection
	{
		Action action = Action::None;
		broker::TrackedProcessListEntry process;
		HWND processWindow = nullptr;
		std::uint32_t statusIconProcessId = 0;
	};

	bool LaunchClientCommand(HWND owner, const wchar_t* argument, bool elevated = false);
	bool Execute(HWND owner, const Selection& selection);
}
