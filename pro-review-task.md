# GPT Pro Review Request

## Goal

Review the POS Center KKT firmware update/onboarding workflow before further implementation or operational use. The project automates setup and firmware update for POS Center / Shtrih-M fiscal registers via the Windows COM driver `AddIn.DrvFR`, including remote execution through PsExec.

## Current State

- Main operator-facing documentation is `ONBOARDING.md`.
- `auto_update.bat` is intended to run on a remote cash-register workstation, download updater files from an internal Apache server, install/check portable Python, check `pywin32`, register `DrvFR.dll`, verify firmware files, and run `kkt_firmware_update.py --force`.
- `run_update.bat` is a direct local firmware update wrapper.
- `download.ps1` downloads scripts and firmware from internal HTTP endpoints.
- `install_python.ps1` prefers a prebuilt portable Python package from the internal server, with an internet fallback.
- `kkt_firmware_update.py` performs precheck, optional shift closing, table backup, firmware selection, DFU update, status polling, reconnect, and JSON reporting.

## Proposed Plan

Before making more changes, identify hidden operational, security, reliability, and rollback risks in the update workflow and documentation. Focus on whether the current scripts are safe enough for repeated remote use and what guardrails should be added first.

## Stop-Lines / No-Touch Zones

- Do not execute firmware updates.
- Do not mutate production/server state.
- Do not contact the internal HTTP server or cash-register devices.
- Do not include raw server snapshots, password hashes, private archives, firmware binaries, logs, or credentials.
- Treat all production network addresses as internal operational context.

## Risks And Assumptions

- Firmware update is high impact because a failure can leave a KKT unusable or require manual recovery.
- `auto_update.bat` can close an open shift automatically through the Python updater.
- Remote execution may run under `SYSTEM` and may have a different working directory, profile, network access, code page, and COM registration state than an interactive admin session.
- The workflow depends on an internal Apache server and hardcoded LAN URLs/IPs.
- The onboarding document currently contains operational details that should be reviewed for redaction before broader sharing.
- The repository also contains `server_snapshot/` and archives; those are excluded from this bundle.

## Privacy Classification

PRODUCTION-SENSITIVE.

Redactions/exclusions:

- Raw admin password from `ONBOARDING.md` is not included.
- `server_snapshot/` is excluded because it contains server configuration and password-hash material.
- Zip archives, firmware binaries, PDFs, logs, and generated caches are excluded.
- Internal IP addresses and LAN URLs are included only where they are part of the reviewed scripts.

## Questions For GPT Pro

1. What hidden failure mode could make this firmware update workflow unsafe for remote repeated use?
2. Which assumption in the current scripts is weakest?
3. What preflight checks should be mandatory before `kkt_firmware_update.py --force` is allowed?
4. What rollback or recovery evidence should be produced before and after firmware update?
5. Which parts of the onboarding/documentation should be redacted or split into private operator notes?
6. What should remain explicitly out of scope for the next implementation step?
7. What is the smallest safe next change set?

## Desired Output

Return a concise review with: verdict, top failure modes, weakest assumption, missing evidence, recommended changes, out-of-scope items, safer alternative, and pre-flight checklist.
