// Purpose: Implements Tray-specific command-line help and installation information.
// Approach: Collects local process and autostart details and formats them into localized scrollable dialogs.
#include "TrayCommandViews.h"

#include <Windows.h>

#include <string>

#include "AutostartControl.h"
#include "ClientRuntimeInfo.h"
#include "ClientTextDialog.h"
#include "Localization.h"
#include "TrayLocalization.h"

namespace xucrun::tray_commands
{
	int ShowHelp(HWND owner)
	{
		text_dialog::Show(
			localization::GetText(localization::TrayTextId::CommandHelpTitle),
			localization::GetText(localization::TrayTextId::CommandHelpHeading),
			localization::GetText(localization::TrayTextId::CommandHelpContent),
			owner);
		return ERROR_SUCCESS;
	}

	int ShowInfo(HWND owner)
	{
		const std::wstring unavailable = localization::GetText(
			localization::TextId::ValueNotAvailable);

		std::wstring maintenanceScript;
		autostart::GetMaintenanceScriptPath(maintenanceScript);
		const autostart::Status status = autostart::QueryStatus();
		const localization::TrayTextId statusText =
			status == autostart::Status::Enabled
				? localization::TrayTextId::InfoAutostartEnabled
				: status == autostart::Status::Disabled
					? localization::TrayTextId::InfoAutostartDisabled
					: localization::TrayTextId::InfoValueUnavailable;
		if (maintenanceScript.empty())
			maintenanceScript = unavailable;
		const runtime_info::RuntimeInfo commonInfo =
			runtime_info::Collect(maintenanceScript);

		text_dialog::Show(
			localization::GetText(localization::TrayTextId::CommandInfoTitle),
			localization::GetText(localization::TrayTextId::CommandInfoHeading),
			runtime_info::Format(commonInfo) +
				localization::Format(localization::TrayTextId::CommandInfoContent,
				{
					localization::GetText(
						localization::TrayTextId::InfoNonElevatedLogonTask),
					localization::GetText(statusText)
				}),
			owner);
		return ERROR_SUCCESS;
	}
}
