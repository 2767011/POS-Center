# Sanitized Project Context For Pro Review

## Reviewed Workflow

The project is a Windows-based toolkit for POS Center / Shtrih-M KKT devices. It uses Python plus `pywin32` to drive the vendor COM object `AddIn.DrvFR`. The high-risk path is remote firmware update via PsExec.

## Files Reviewed Locally

- `auto_update.bat`
- `run_update.bat`
- `config.bat`
- `download.ps1`
- `install_python.ps1`
- `kkt_driver.py`
- `kkt_firmware_update.py`
- `kkt_dump_tables.py`
- `ONBOARDING.md`

Raw file contents are intentionally not included in this clean bundle because they contain internal LAN addresses, operational URLs, and driver credential field names that trigger the secret/PII scanner. The summary below is based on local inspection of those files.

## auto_update.bat Summary

- Requires administrator privileges because it may register the COM driver.
- Chooses a temp working directory for remote execution.
- Downloads `download.ps1` from an internal updater URL, then uses it to download the rest of the updater scripts and firmware files.
- Verifies critical updater files exist after download.
- Loads `config.bat` when present, otherwise uses built-in defaults.
- Installs or reuses portable Python.
- Verifies `pywin32` by importing the COM client module.
- Checks whether `AddIn.DrvFR` can be created.
- If COM creation fails, searches known vendor install paths for `DrvFR.dll` and runs silent registration.
- Verifies at least one firmware binary exists.
- Runs the Python firmware updater with force mode and JSON report output.
- Creates a success flag on completion.

## run_update.bat Summary

- Runs from the script directory.
- Uses a local portable Python executable.
- Calls the firmware updater with local firmware directory and JSON report output.
- Treats normal success and dry-run success return codes as successful.

## download.ps1 Summary

- Downloads a fixed list of updater scripts from an internal updater URL.
- Reads an internal firmware directory listing and downloads firmware binaries.
- Attempts to download a post-update table CSV if available.
- Counts failed downloads and exits nonzero if any required download fails.

## install_python.ps1 Summary

- Prefers a prebuilt portable Python package from the internal updater server.
- Falls back to downloading an official embedded Python archive from the internet.
- Enables pip support for embedded Python when needed.
- Installs `pywin32`.
- Removes temporary installer files after setup.

## kkt_driver.py Summary

- Provides shared COM-driver helpers.
- Creates the `AddIn.DrvFR` COM object.
- Connects over TCP using RNDIS-style device networking.
- Sets driver connection fields and default administrative credential fields.
- Provides safe property access and table-reading helpers.

## kkt_firmware_update.py Summary

- Sets up dual console/file logging for PsExec and Windows code page compatibility.
- Imports shared driver helpers, with a local fallback if the shared module is missing.
- Imports table-dump functionality for backup.
- Defines explicit exit codes for normal success, general failure, precheck failure, and dry-run success.
- Checks current device version and device mode.
- Can close an open fiscal shift before update.
- Determines device type from a KKT table field to choose standard or old firmware family.
- Backs up device tables before update.
- Starts DFU firmware update through the COM driver.
- Polls update status with a timeout.
- Reconnects and checks final device version.
- Writes a JSON report.

## kkt_dump_tables.py Summary

- Reads KKT configuration tables through the COM driver.
- Produces table backups for diagnostics and recovery evidence.
- Is used by the firmware updater before flashing.

## ONBOARDING.md Summary

- Describes project structure, quick start, remote execution, firmware update flow, internal web server paths, dependencies, encodings, and known issues.
- Contains operational server/admin details that should be split or redacted before broader sharing.

## Known Local Repository State

- Worktree already had modified files before this bundle was created.
- The repository contains generated caches, archives, PDFs, firmware/vendor packages, and a server snapshot; these are excluded from review context.

## Evidence Gaps To Ask Pro About

- No live device test results are included.
- No recent logs are included.
- No firmware hashes or signing/verification evidence are included.
- No rollback drill evidence is included.
- No inventory of target KKT models is included.
- No explicit operator approval workflow is included.
