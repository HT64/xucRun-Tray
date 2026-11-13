# Changelog

**Language:** English | [Deutsch](CHANGELOG.de.md)

This changelog covers only changes relevant to users of xucRun Tray. Internal development and
publication processes are not listed.

## [Unreleased]

## [0.9.1.7] - 2026-11-13

### Changed

- Updated installer and documentation notices on licensing, security, and project status; aligned
  Tray's notices with xucRun's.
- The installer places the license and attribution notices in the `Licenses` subdirectory.
- The graphical installer displays the license text, attribution notices, and status and security
  notices offline on separate tabs and requires their acknowledgment for every installation or
  update.
- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.1.7.

### Fixed

- The Tray installer's initial language now follows the Windows language preferences of the
  interactively signed-in user.

## [0.9.1.6] - 2026-11-10

This version contains security-relevant fixes that affect all earlier versions. The corrected
weaknesses were found during an internal security review; no attacks are known. They can only
be exploited by malicious code that is already running on the same computer. Updating xucRun
and xucRun Tray to this version is recommended.

### Security

- The temporary working copies of the Tray package signing script are now accessible only to
  administrators and SYSTEM.
- Additionally hardened xucRun Tray and its installer against manipulated local environments.

### Changed

- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.1.6.

## [0.9.1.5] - 2026-11-09

### Added

- While at least one tracked process runs as `LocalSystem` or with the TrustedInstaller identity,
  every entry under **Elevated processes** begins with its broker-validated identity: `[ADM]` and
  the account name for an elevated administrator, `[SYS] SYSTEM` for `LocalSystem`, or
  `[TI] TrustedInstaller`. Otherwise entries stay compact and only processes running under a
  different account than the signed-in user are prefixed with that account name.
- While a tracked process with the TrustedInstaller identity has a visible main window, the red
  warning icon pulses once per second. Ordinary elevated and `LocalSystem` windows keep the icon
  steadily red.

### Changed

- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.1.5.
- The documentation now explains which processes the **Elevated processes** list contains, that
  it is not a system-wide overview of all elevated or SYSTEM processes, and that processes
  without a suitable visible window appear as grayed-out entries marked `no window`.

## [0.9.1.4] - 2026-11-07

### Changed

- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.1.4.

## [0.9.1.3] - 2026-11-04

### Changed

- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.1.3.
- The Tray runtime-information title now includes the computer name, and the documentation shows
  the current runtime-information view.
- The documentation now clarifies that xucRun works without the Tray and explains how to disable
  or re-enable Tray logon startup and how to exit or restart the Tray manually.

## [0.9.1.1] - 2026-11-01

### Changed

- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.1.1.

## [0.9.1.0] - 2026-11-01

### Added

- Added per-user controls for enabling, repairing, disabling, and inspecting the non-elevated
  Windows logon task. The same operations are available through `/enable-autostart`,
  `/disable-autostart`, and `/autostart-status`.
- Added Tray-specific `/info` and `/help` views. The Help and Information submenus now provide
  separate entries for xucRun and xucRun Tray.
- Added a Logs action that opens the Windows Application event log filtered temporarily to the
  `xucRunBroker` source without requiring elevation.

### Changed

- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.1.0.
- The Logs submenu now shows the number of deletable client log files. The Tray rereads the client
  logging configuration and enumerates log files whenever its context menu opens, so configuration
  changes and newly created files are available without restarting the Tray.
- Tray runtime information now uses the shared Core format for program identity, language,
  signature, account, configuration, and logging details and adds the state of the current user's
  Windows logon task.

## [0.9.0.3] - 2026-10-29

### Changed

- Updated the Tray package and installer compatibility requirement to xucRun Core 0.9.0.3.
- The Tray now rereads the client logging configuration whenever its context menu opens, so changed
  log directories and newly created log files become available without restarting the Tray.
- The Tray now validates externally changed language settings before restarting itself in the new
  language and remains active in its current language when the new setting or resource is invalid.
- The icon tooltip now identifies the Tray account and elevation state when multiple Tray instances
  are present, the Tray account differs from the interactively signed-in user, or the identity
  cannot be determined reliably.

## [0.9.0.2] - 2026-10-23

### Note

- This is the initial public release of xucRun Tray.

[Unreleased]: https://github.com/HT64/xucRun-Tray/compare/v0.9.1.7...HEAD
[0.9.1.7]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.7
[0.9.1.6]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.6
[0.9.1.5]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.5
[0.9.1.4]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.4
[0.9.1.3]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.3
[0.9.1.1]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.1
[0.9.1.0]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.0
[0.9.0.3]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.3
[0.9.0.2]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.2
