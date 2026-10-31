// Purpose: Defines typed localization IDs used by xucRun Tray.
// Approach: Maps Tray-specific string resource constants into the shared localization type system.
#pragma once

#include "Localization.h"
#include "TrayResourceIds.h"

namespace xucrun::localization
{
	enum class TrayTextId : unsigned int
	{
		TooltipService = IDS_TOOLTIP_SERVICE,
		TooltipConnection = IDS_TOOLTIP_CONNECTION,
		TooltipElevated = IDS_TOOLTIP_ELEVATED,
		TooltipStatusFor = IDS_TOOLTIP_STATUS_FOR,
		ConnectionDegraded = IDS_CONNECTION_DEGRADED,
		CandidateSelectionLimited = IDS_CANDIDATE_SELECTION_LIMITED,
		ProcessListTruncated = IDS_PROCESS_LIST_TRUNCATED,
		IconProcessRole = IDS_ICON_PROCESS_ROLE,
		NoWindow = IDS_NO_WINDOW,
		WindowFallback = IDS_WINDOW_FALLBACK,
		ElevatedProcesses = IDS_ELEVATED_PROCESSES,
		MenuCreateCredential = IDS_MENU_CREATE_CREDENTIAL,
		MenuShowCredentials = IDS_MENU_SHOW_CREDENTIALS,
		MenuDeleteCredential = IDS_MENU_DELETE_CREDENTIAL,
		MenuShowApprovals = IDS_MENU_SHOW_APPROVALS,
		MenuResetApprovals = IDS_MENU_RESET_APPROVALS,
		MenuRunSecurityAudit = IDS_MENU_RUN_SECURITY_AUDIT,
		MenuShowHelp = IDS_MENU_SHOW_HELP,
		MenuShowInfo = IDS_MENU_SHOW_INFO,
		MenuShowLogFile = IDS_MENU_SHOW_LOG_FILE,
		MenuDeleteLogFile = IDS_MENU_DELETE_LOG_FILE,
		MenuLogFiles = IDS_MENU_LOG_FILES,
		MenuDeleteAllLogFiles = IDS_MENU_DELETE_ALL_LOG_FILES,
		LogFileUnavailable = IDS_LOG_FILE_UNAVAILABLE,
		LogFileOpenFailed = IDS_LOG_FILE_OPEN_FAILED,
		LogFileDeleteConfirmation = IDS_LOG_FILE_DELETE_CONFIRMATION,
		LogFileDeleteFailed = IDS_LOG_FILE_DELETE_FAILED,
		LogFileDeleteSucceeded = IDS_LOG_FILE_DELETE_SUCCEEDED,
		LogFilesQueryFailed = IDS_LOG_FILES_QUERY_FAILED,
		LogFilesDeleteAllConfirmation = IDS_LOG_FILES_DELETE_ALL_CONFIRMATION,
		LogFilesDeleteAllSucceeded = IDS_LOG_FILES_DELETE_ALL_SUCCEEDED,
		LogFilesDeleteAllIncomplete = IDS_LOG_FILES_DELETE_ALL_INCOMPLETE,
		StatusIconIdentityFailed = IDS_STATUS_ICON_IDENTITY_FAILED,
		StatusIconSingletonFailed = IDS_STATUS_ICON_SINGLETON_FAILED,
		MenuLanguage = IDS_MENU_LANGUAGE,
		MenuLanguageGerman = IDS_MENU_LANGUAGE_GERMAN,
		MenuLanguageEnglish = IDS_MENU_LANGUAGE_ENGLISH,
		MenuLanguageAutomatic = IDS_MENU_LANGUAGE_AUTOMATIC,
		MenuEnableAutostart = IDS_MENU_ENABLE_AUTOSTART,
		MenuDisableAutostart = IDS_MENU_DISABLE_AUTOSTART,
		MenuAutostartUnavailable = IDS_MENU_AUTOSTART_UNAVAILABLE,
		AutostartEnabled = IDS_AUTOSTART_ENABLED,
		AutostartDisabled = IDS_AUTOSTART_DISABLED,
		AutostartChangeFailed = IDS_AUTOSTART_CHANGE_FAILED,
		AutostartStatusEnabled = IDS_AUTOSTART_STATUS_ENABLED,
		AutostartStatusDisabled = IDS_AUTOSTART_STATUS_DISABLED,
		AutostartStatusUnavailable = IDS_AUTOSTART_STATUS_UNAVAILABLE,
		InvalidCommandLine = IDS_INVALID_COMMAND_LINE,
		CommandHelpTitle = IDS_COMMAND_HELP_TITLE,
		CommandHelpHeading = IDS_COMMAND_HELP_HEADING,
		CommandHelpContent = IDS_COMMAND_HELP_CONTENT,
		CommandInfoTitle = IDS_COMMAND_INFO_TITLE,
		CommandInfoHeading = IDS_COMMAND_INFO_HEADING,
		CommandInfoContent = IDS_COMMAND_INFO_CONTENT,
		InfoNonElevatedLogonTask = IDS_INFO_NON_ELEVATED_LOGON_TASK,
		InfoAutostartEnabled = IDS_INFO_AUTOSTART_ENABLED,
		InfoAutostartDisabled = IDS_INFO_AUTOSTART_DISABLED,
		InfoValueUnavailable = IDS_INFO_VALUE_UNAVAILABLE,
		MenuShowCoreInfo = IDS_MENU_SHOW_CORE_INFO,
		MenuShowTrayInfo = IDS_MENU_SHOW_TRAY_INFO,
		MenuShowCoreHelp = IDS_MENU_SHOW_CORE_HELP,
		MenuShowTrayHelp = IDS_MENU_SHOW_TRAY_HELP,
		MenuShowBrokerEvents = IDS_MENU_SHOW_BROKER_EVENTS,
		BrokerEventsOpenFailed = IDS_BROKER_EVENTS_OPEN_FAILED,
		MenuDisableService = IDS_MENU_STOP_SERVICE,
		MenuEnableService = IDS_MENU_ENABLE_SERVICE,
		MenuStartService = IDS_MENU_START_SERVICE,
		MenuServiceStarting = IDS_MENU_SERVICE_STARTING,
		MenuServiceStopping = IDS_MENU_SERVICE_STOPPING,
		MenuServiceUnavailable = IDS_MENU_SERVICE_UNAVAILABLE,
		MenuExitStatus = IDS_MENU_EXIT_STATUS,
		MenuAdministrativeStatus = IDS_MENU_ADMINISTRATIVE_STATUS,
		BrokerStopIncomplete = IDS_BROKER_STOP_INCOMPLETE,
		BrokerStopUnavailable = IDS_BROKER_STOP_UNAVAILABLE,
		BrokerStopIoFailed = IDS_BROKER_STOP_IO_FAILED,
		BrokerStopInvalidResponse = IDS_BROKER_STOP_INVALID_RESPONSE,
		BrokerStopUnauthorized = IDS_BROKER_STOP_UNAUTHORIZED,
		BrokerStopFailed = IDS_BROKER_STOP_FAILED,
	};

	inline std::wstring GetText(TrayTextId id)
	{
		return GetTextByResourceId(static_cast<unsigned int>(id));
	}

	inline std::wstring Format(TrayTextId id,
		std::initializer_list<std::wstring> arguments)
	{
		return FormatResource(static_cast<unsigned int>(id), arguments);
	}
}
