# Changelog

**Language:** English | [Deutsch](CHANGELOG.de.md)

This changelog covers only changes relevant to users of xucRun Tray. Internal development and
publication processes are not listed.

## [Unreleased]

## [0.9.0.2] - 2026-10-21

### Note

- This is the initial public release of xucRun Tray.

### Changed

- The installer now sizes and positions its version, certificate, user selection, details, status,
  and action areas according to their actual content for a more compact layout.
- Uninstall from Installed apps now hides the PowerShell host. Failures remain visible in a
  localized dialog that identifies the persistent diagnostic log and can open its folder.
- New English and German manual-removal documentation inventories all Tray-owned files, processes,
  scheduled tasks, registry entries, and interrupted-installation remnants while explicitly
  preserving the xucRun Core.
- For an existing Tray installation, the installer now shows its registered version and the time
  it was installed or last updated.
- The installer now validates the installed xucRun version, signature, and broker binding before
  opening the interface and displays the successfully validated xucRun version.
- Both Tray language DLLs now include complete Windows file details with descriptions, product
  versions, and original file names.
- The installer interface and success confirmation now show the name, validity period, and
  thumbprint of the Core certificate used to sign the xucRun Tray files.

### Fixed

- Installation now locally signs the unsigned files from a public Tray package with the installed
  xucRun certificate instead of rejecting them before signing.
- Package validation now rejects inconsistent installer and payload signatures.
- xucRun Tray now refreshes its broker status automatically after a Core installation or recreation
  of the broker service.
- When another user is configured, previously running Tray instances are now restarted after the
  required file replacement.
- Tray uninstallation now shows a localized success confirmation listing removed components and
  the Core, certificate, and user data that explicitly remain unchanged.

[Unreleased]: https://github.com/HT64/xucRun-Tray/compare/v0.9.0.2...HEAD
[0.9.0.2]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.2
