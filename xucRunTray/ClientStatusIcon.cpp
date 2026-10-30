// Purpose: Builds visible data for the tray status icon.
// Behavior: Combines service state, localized text, resource icons, and broker information.
#include "ClientStatusIcon.h"

#include <algorithm>
#include <cstdint>
#include <vector>

#include "BrokerPipeClient.h"
#include "ClientUiCommon.h"
#include "TrayLocalization.h"
#include "ClientResourceIds.h"

namespace
{
	HICON CreateElevatedOverlayIcon(HICON sourceIcon)
	{
		if (!sourceIcon)
			return nullptr;
		const int width = GetSystemMetrics(SM_CXSMICON);
		const int height = GetSystemMetrics(SM_CYSMICON);
		BITMAPINFO bitmapInfo = {};
		bitmapInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
		bitmapInfo.bmiHeader.biWidth = width;
		bitmapInfo.bmiHeader.biHeight = -height;
		bitmapInfo.bmiHeader.biPlanes = 1;
		bitmapInfo.bmiHeader.biBitCount = 32;
		bitmapInfo.bmiHeader.biCompression = BI_RGB;

		HDC screen = GetDC(nullptr);
		void* pixels = nullptr;
		HBITMAP colorBitmap = screen ? CreateDIBSection(
			screen, &bitmapInfo, DIB_RGB_COLORS, &pixels, nullptr, 0) : nullptr;
		HDC memory = screen && colorBitmap ? CreateCompatibleDC(screen) : nullptr;
		HICON shieldIcon = nullptr;
		if (memory)
		{
			SecureZeroMemory(pixels,
				static_cast<std::size_t>(width) * height * sizeof(std::uint32_t));
			HGDIOBJ previousBitmap = SelectObject(memory, colorBitmap);
			DrawIconEx(memory, 0, 0, sourceIcon, width, height, 0, nullptr, DI_NORMAL);
			SHSTOCKICONINFO shieldInfo = { sizeof(shieldInfo) };
			if (SUCCEEDED(SHGetStockIconInfo(
				SIID_SHIELD, SHGSI_ICON | SHGSI_SMALLICON, &shieldInfo)))
			{
				shieldIcon = shieldInfo.hIcon;
				const int overlayWidth = (std::max)(8, width * 9 / 16);
				const int overlayHeight = (std::max)(8, height * 9 / 16);
				DrawIconEx(memory, width - overlayWidth, height - overlayHeight,
					shieldIcon, overlayWidth, overlayHeight, 0, nullptr, DI_NORMAL);
			}
			SelectObject(memory, previousBitmap);
		}
		const std::size_t maskStride = ((static_cast<std::size_t>(width) + 15) / 16) * 2;
		const std::vector<std::uint8_t> maskBits(maskStride * height, 0);
		HBITMAP maskBitmap = colorBitmap
			? CreateBitmap(width, height, 1, 1, maskBits.data())
			: nullptr;
		ICONINFO iconInfo = {};
		iconInfo.fIcon = TRUE;
		iconInfo.hbmColor = colorBitmap;
		iconInfo.hbmMask = maskBitmap;
		HICON result = colorBitmap && maskBitmap && shieldIcon
			? CreateIconIndirect(&iconInfo)
			: nullptr;
		if (shieldIcon)
			DestroyIcon(shieldIcon);
		if (memory)
			DeleteDC(memory);
		if (colorBitmap)
			DeleteObject(colorBitmap);
		if (maskBitmap)
			DeleteObject(maskBitmap);
		if (screen)
			ReleaseDC(nullptr, screen);
		return result;
	}

	std::wstring GetServiceStatusLabel(
		const xucrun::status_icon::BrokerServiceState& serviceState)
	{
		using xucrun::localization::GetText;
		using xucrun::localization::TextId;
		using xucrun::status_icon::BrokerServiceStatus;
		switch (serviceState.status)
		{
		case BrokerServiceStatus::NotInstalled:
			return GetText(TextId::StatusNotInstalled);
		case BrokerServiceStatus::Stopped:
			return GetText(TextId::StatusStopped);
		case BrokerServiceStatus::Disabled:
			return GetText(TextId::StatusDisabled);
		case BrokerServiceStatus::Starting:
			return GetText(TextId::StatusStarting);
		case BrokerServiceStatus::Stopping:
			return GetText(TextId::StatusStopping);
		case BrokerServiceStatus::Running:
			return GetText(TextId::StatusRunning);
		default:
			return serviceState.error == NO_ERROR
				? GetText(TextId::StatusUnavailable)
				: xucrun::localization::Format(TextId::StatusUnavailableWithError,
					{ std::to_wstring(serviceState.error) });
		}
	}

	std::wstring BuildTooltip(
		const xucrun::status_icon::BrokerServiceState& serviceState,
		bool brokerCommunicationAvailable, std::uint32_t elevatedProcessCount,
		const xucrun::broker::ProductVersion& brokerVersion,
		const std::wstring& currentAccount, bool currentProcessElevated,
		bool showStatusIdentity)
	{
		std::wstring tooltip = xucrun::broker::ProductName;
		if (brokerCommunicationAvailable)
		{
			tooltip += L" V" + std::to_wstring(brokerVersion.major) + L"." +
				std::to_wstring(brokerVersion.minor) + L"." +
				std::to_wstring(brokerVersion.patch) + L"." +
				std::to_wstring(brokerVersion.build);
		}
		if (showStatusIdentity)
		{
			tooltip += L"\r\n" + xucrun::localization::Format(
				xucrun::localization::TrayTextId::TooltipStatusFor,
				{ currentAccount,
					xucrun::localization::GetText(currentProcessElevated
						? xucrun::localization::TextId::InfoElevated
						: xucrun::localization::TextId::InfoNotElevated) });
		}
		tooltip += L"\r\n" + xucrun::localization::Format(
			xucrun::localization::TrayTextId::TooltipService,
			{ GetServiceStatusLabel(serviceState) });
		if (serviceState.status ==
			xucrun::status_icon::BrokerServiceStatus::Running)
		{
			tooltip += L"\r\n" + xucrun::localization::Format(
				xucrun::localization::TrayTextId::TooltipConnection,
				{ brokerCommunicationAvailable
					? xucrun::localization::GetText(
						xucrun::localization::TextId::ConnectionActive)
					: xucrun::localization::GetText(
						xucrun::localization::TrayTextId::ConnectionDegraded) });
		}
		if (brokerCommunicationAvailable)
		{
			tooltip += L"\r\n" + xucrun::localization::Format(
				xucrun::localization::TrayTextId::TooltipElevated,
				{ std::to_wstring(elevatedProcessCount) });
		}
		constexpr size_t MaximumTrayTooltipLength = 127;
		if (tooltip.size() > MaximumTrayTooltipLength)
			tooltip = tooltip.substr(0, MaximumTrayTooltipLength - 3) + L"...";
		return tooltip;
	}
}

namespace xucrun::status_icon
{
	NOTIFYICONDATAW Build(HWND window, UINT callbackMessage,
		const BrokerServiceState& serviceState,
		bool brokerCommunicationAvailable,
		std::uint32_t elevatedProcessCount,
		bool elevatedProcessWindowActive,
		const broker::ProductVersion& brokerVersion,
		const std::wstring& currentAccount,
		bool currentProcessElevated,
		bool showStatusIdentity)
	{
		static HICON statusIcon = static_cast<HICON>(LoadImageW(
			GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_XUCRUN), IMAGE_ICON,
			GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
			LR_DEFAULTCOLOR));
		static HICON stoppedIcon = ui::CreateColorizedApplicationIcon(
			statusIcon, ui::ApplicationIconColor::Grayscale);
		static HICON redStatusIcon = ui::CreateColorizedApplicationIcon(
			statusIcon, ui::ApplicationIconColor::Red);
		static HICON elevatedStatusIcon = CreateElevatedOverlayIcon(statusIcon);
		static HICON elevatedStoppedIcon = CreateElevatedOverlayIcon(
			stoppedIcon ? stoppedIcon : statusIcon);
		static HICON elevatedRedStatusIcon = CreateElevatedOverlayIcon(
			redStatusIcon ? redStatusIcon : statusIcon);
		NOTIFYICONDATAW icon = {};
		icon.cbSize = sizeof(icon);
		icon.hWnd = window;
		icon.uID = 1;
		icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
		icon.uCallbackMessage = callbackMessage;
		if (serviceState.status != BrokerServiceStatus::Running)
			icon.hIcon = currentProcessElevated && elevatedStoppedIcon
				? elevatedStoppedIcon
				: stoppedIcon ? stoppedIcon : statusIcon;
		else if (!brokerCommunicationAvailable || elevatedProcessWindowActive)
			icon.hIcon = currentProcessElevated && elevatedRedStatusIcon
				? elevatedRedStatusIcon
				: redStatusIcon ? redStatusIcon : statusIcon;
		else
			icon.hIcon = currentProcessElevated && elevatedStatusIcon
				? elevatedStatusIcon
				: statusIcon;
		const std::wstring tooltip = BuildTooltip(serviceState,
			brokerCommunicationAvailable, elevatedProcessCount, brokerVersion,
			currentAccount, currentProcessElevated, showStatusIdentity);
		wcsncpy_s(icon.szTip, tooltip.c_str(), _TRUNCATE);
		return icon;
	}
}