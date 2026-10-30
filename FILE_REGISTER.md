<!--
Purpose: Registers every tracked and unignored xucRun Tray repository file and its public purpose.
Approach: Uses one machine-validated table row per path, with a class and concise purpose.
-->
# File register

This register covers every Git-tracked file and every unignored file present in the repository
worktree. `Test-TrayArchitecture.ps1` compares Git's tracked-plus-unignored file list with this
table, rejects missing or duplicate entries, and requires every purpose to be nonempty. Files
created below ignored build, IDE, or artifact paths are generated outputs and are outside this
register.

Commentable text files carry structured `Purpose` and `Approach` metadata in their file heads.
PowerShell scripts use their existing comment-based help: `SYNOPSIS` states what the script does
and `DESCRIPTION` explains its approach. Tool-maintained MSBuild XML files retain XML comments.
Formats without a safe comment mechanism—JSON, Visual Studio solutions, images, legal texts, and
plain semantic data—are documented only here rather than being modified with invalid metadata.

| Path | Class | Purpose |
| --- | --- | --- |
| `.gitattributes` | Repository configuration | Defines Git text and line-ending handling. |
| `.githooks/pre-push` | Git hook | Verifies the public repository and push destination before a push. |
| `.github/FUNDING.yml` | GitHub configuration | Declares the optional Patreon funding link. |
| `.github/workflows/ci.yml` | CI workflow | Builds, tests, and packages Tray with its pinned xucRun dependency. |
| `.gitignore` | Repository configuration | Excludes local IDE state, build outputs, and generated artifacts. |
| `CHANGELOG.de.md` | User documentation | Records user-visible changes in German; its conventional title and version structure replace a metadata head. |
| `CHANGELOG.md` | User documentation | Records user-visible changes in English; its conventional title and version structure replace a metadata head. |
| `CONTRIBUTING.de.md` | Project policy | Explains contribution and security-reporting routes in German. |
| `CONTRIBUTING.md` | Project policy | Explains contribution and security-reporting routes in English. |
| `Dependencies.json` | Dependency data | Pins the public xucRun repository revision required by Tray. |
| `Directory.Build.props` | Build configuration | Defines shared repository, output, and signing properties. |
| `Directory.Build.targets` | Build configuration | Validates build prerequisites and refreshes shared resources. |
| `FILE_REGISTER.md` | Repository documentation | Catalogs every tracked and unignored repository file. |
| `Install-GitHooks.ps1` | Repository tool | Enables and verifies the version-controlled Git safety hooks. |
| `Install-xucRunTray.ps1` | Installer script | Validates, installs, updates, or removes the Tray add-on. |
| `LICENSE` | Legal text | Contains the Apache License 2.0 terms. |
| `New-xucRunTray-Package.ps1` | Packaging script | Creates a Tray payload or release package from built artifacts. |
| `NOTICE` | Legal text | Provides the product copyright notice. |
| `README.de.md` | User documentation | Describes xucRun Tray and its use in German. |
| `README.md` | User documentation | Describes xucRun Tray and its use in English. |
| `SECURITY.de.md` | Security policy | Defines supported versions and private reporting in German. |
| `SECURITY.md` | Security policy | Defines supported versions and private reporting in English. |
| `Sign-xucRunTrayPackage.ps1` | Signing script | Signs a Tray payload with the installed xucRun signing identity. |
| `Test-PublicRepository.ps1` | Policy test | Verifies the worktree, remotes, and public GitHub visibility. |
| `Test-TrayAddonPackage.ps1` | Package test | Validates built payload and release-package contracts. |
| `Test-TrayArchitecture.ps1` | Architecture test | Enforces repository boundaries, documentation, and architecture contracts. |
| `XUCRun-Tray.sln` | Visual Studio solution | Groups the Tray executable, installer, and language projects. |
| `docs/de/MANUAL_REMOVAL.md` | User documentation | Explains safe manual Tray removal in German. |
| `docs/de/images/elevated-processes.png` | Documentation image | Shows the German elevated-processes menu. |
| `docs/de/images/installation-success.png` | Documentation image | Shows the German successful-installation message. |
| `docs/de/images/installer.png` | Documentation image | Shows the German graphical installer. |
| `docs/de/images/tray-menu.png` | Documentation image | Shows the German Tray context menu. |
| `docs/de/images/uninstallation-success.png` | Documentation image | Shows the German successful-uninstallation message. |
| `docs/de/images/unsupported-core-installation.png` | Documentation image | Shows the German unsupported-xucRun warning. |
| `docs/en/MANUAL_REMOVAL.md` | User documentation | Explains safe manual Tray removal in English. |
| `docs/en/images/elevated-processes.png` | Documentation image | Shows the English elevated-processes menu. |
| `docs/en/images/installation-success.png` | Documentation image | Shows the English successful-installation message. |
| `docs/en/images/installer.png` | Documentation image | Shows the English graphical installer. |
| `docs/en/images/tray-menu.png` | Documentation image | Shows the English Tray context menu. |
| `docs/en/images/uninstallation-success.png` | Documentation image | Shows the English successful-uninstallation message. |
| `docs/en/images/unsupported-core-installation.png` | Documentation image | Shows the English unsupported-xucRun warning. |
| `xucRunTray/ClientStatusActionRouting.h` | C++ header | Maps typed Tray actions to xucRun client arguments. |
| `xucRunTray/ClientStatusActions.cpp` | C++ source | Executes menu actions and guarded log operations. |
| `xucRunTray/ClientStatusActions.h` | C++ header | Defines typed Tray action selections and dispatch operations. |
| `xucRunTray/ClientStatusIcon.cpp` | C++ source | Derives the visible Tray icon and tooltip data. |
| `xucRunTray/ClientStatusIcon.h` | C++ header | Defines Tray icon state and representation helpers. |
| `xucRunTray/ClientStatusMenu.cpp` | C++ source | Builds the status menu and converts commands to typed actions. |
| `xucRunTray/ClientStatusMenu.h` | C++ header | Defines status-menu inputs and selection results. |
| `xucRunTray/TrayBrokerStatus.cpp` | C++ source | Runs the event-driven broker status and Tray icon loop. |
| `xucRunTray/TrayBrokerStatus.h` | C++ header | Declares the Tray status-loop entry point. |
| `xucRunTray/TrayMain.cpp` | C++ source | Initializes and runs the Tray process. |
| `xucRunTray/xucRunTray.vcxproj` | MSBuild project | Builds and optionally signs the Tray executable. |
| `xucRunTrayInstaller/Installer-Gui.ps1` | Installer script | Runs the localized graphical installation workflow. |
| `xucRunTrayInstaller/Installer.rc` | Windows resource | Embeds the installer payload and metadata. |
| `xucRunTrayInstaller/main.cpp` | C++ source | Extracts the embedded payload and starts its graphical installer. |
| `xucRunTrayInstaller/resource.h` | C/C++ header | Defines stable bootstrap-installer resource identifiers. |
| `xucRunTrayInstaller/xucRunTrayInstaller.vcxproj` | MSBuild project | Builds, packages, and optionally signs the bootstrap installer. |
| `xucRunTrayLanguageDeDe/xucRunTrayLanguageDeDe.vcxproj` | MSBuild project | Builds the German Tray language resource DLL. |
| `xucRunTrayLanguageEnUs/xucRunTrayLanguageEnUs.vcxproj` | MSBuild project | Builds the English Tray language resource DLL. |
| `xucRunTrayResources/TrayLocalization.h` | C++ header | Maps Tray strings into the shared localization type system. |
| `xucRunTrayResources/TrayResourceIds.h` | C/C++ header | Defines stable Tray string resource identifiers. |
| `xucRunTrayResources/TrayStringsDeDe.rcinc` | Resource data | Provides German Tray strings. |
| `xucRunTrayResources/TrayStringsEnUs.rcinc` | Resource data | Provides English Tray strings. |
