<!--
Purpose: Defines supported versions and the confidential vulnerability-reporting route.
Approach: Separates public version support from private reporting steps and response expectations.
-->
# Security Policy

**Language:** [Deutsch](SECURITY.de.md) | English

## Supported versions

After the first public xucRun Tray release, only the latest released version is supported.

No public version is supported before the first release.

## Reporting a vulnerability

Do not report an unpatched or suspected vulnerability in a public issue, discussion, pull request,
or other public channel.

Use GitHub Private Vulnerability Reporting for the `HT64/xucRun-Tray` repository:

1. Open the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Provide a clear description, affected version or commit, reproduction steps, expected impact,
   and any known mitigations.

If the issue concerns the boundary between xucRun Tray and the main xucRun application or broker
and the responsible component is not yet known, it may be reported confidentially through
`HT64/xucRun-Tray`. Security issues known to affect only the main xucRun application or broker
should be reported through Private Vulnerability Reporting for `HT64/xucRun`.

Include only the sensitive data required to understand the problem. Do not submit real passwords,
private keys, access tokens, or unrelated personal data.

Response and remediation times depend on reproducibility, severity, and implementation risk. This
policy does not promise a fixed service level or a vulnerability bounty.

## Scope

This policy applies to source and published packages from `HT64/xucRun-Tray`. The main xucRun
application, third-party software, and modified builds are outside this repository's support
scope. The restricted broker interface used by Tray is in scope when the reported behavior is
caused by Tray or by its use of that interface.
