# Changelog

**Language:** English | [Deutsch](CHANGELOG.de.md)

This changelog covers only changes relevant to users of xucRun Tray. Internal development and
publication processes are not listed.

## [Unreleased]

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

[Unreleased]: https://github.com/HT64/xucRun-Tray/compare/v0.9.0.3...HEAD
[0.9.0.3]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.3
[0.9.0.2]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.2
