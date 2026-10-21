// Purpose: Classifies tray actions that must be delegated to the Core client.
#pragma once

#include <string_view>

#include "ClientStatusActions.h"

namespace xucrun::status_actions
{
	constexpr std::wstring_view GetCoreClientArgument(Action action) noexcept
	{
		switch (action)
		{
		case Action::CreateCredential: return L"/addcred";
		case Action::ShowCredentials: return L"/showcred";
		case Action::DeleteCredential: return L"/deletecred";
		case Action::ShowApprovals: return L"/showapprovals";
		case Action::ResetApprovals: return L"/resetapprovals";
		case Action::AdministrativeStatus: return L"/admin-status";
		case Action::RunAudit: return L"/audit";
		case Action::ShowHelp: return L"/help";
		case Action::ShowInfo: return L"/info";
		case Action::SetLanguageGerman: return L"/set-language:de";
		case Action::SetLanguageEnglish: return L"/set-language:en";
		default: return {};
		}
	}

	static_assert(GetCoreClientArgument(Action::CreateCredential) == L"/addcred");
	static_assert(GetCoreClientArgument(Action::ShowCredentials) == L"/showcred");
	static_assert(GetCoreClientArgument(Action::DeleteCredential) == L"/deletecred");
	static_assert(GetCoreClientArgument(Action::ShowApprovals) == L"/showapprovals");
	static_assert(GetCoreClientArgument(Action::ResetApprovals) == L"/resetapprovals");
	static_assert(GetCoreClientArgument(Action::AdministrativeStatus) == L"/admin-status");
	static_assert(GetCoreClientArgument(Action::RunAudit) == L"/audit");
	static_assert(GetCoreClientArgument(Action::ShowHelp) == L"/help");
	static_assert(GetCoreClientArgument(Action::ShowInfo) == L"/info");
	static_assert(GetCoreClientArgument(Action::SetLanguageGerman) ==
		L"/set-language:de");
	static_assert(GetCoreClientArgument(Action::SetLanguageEnglish) ==
		L"/set-language:en");
	static_assert(GetCoreClientArgument(Action::ActivateProcessWindow).empty());
}
