# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
    and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.720] - 2018-12-16
### Fixed
* Enhanced outputs of Invoke-DbaDbDataMasking
* Save-DbaDiagnosticQuery to work with lightly malformed links

## [0.9.719] - 2018-12-15
### Added
* Piping to Get-DbaDbSpace

### Changed
* Logic to make UseLastBackup in Start-DbaMigration to be easier

## [0.9.718] - 2018-12-14
### Added
* Added a progress bar and made the output more reasonable

## [0.9.717] - 2018-12-14
### Fixed
* Added more flexibility to masking commands
* Updated SQL Build info

## [0.9.715] - 2018-12-12
### Fixed
* LogShipping in v2012

### Added
* Added check for ps v2 for those that bypass psd1
* Pipeline support for Get-DbaDbSpace
* xplat support notification to find-dbacommand / docs.dbatools.io
* More integration tests
* New commands: Invoke-DbaDbDataMasking and New-DbaDbMaskingConfig

## [0.9.714] - 2018-12-10
### Fixed
* Get-DbaBackupHistory - fully honors need to exclude system dbs
* Fixed docs/typos in various commands

## [0.9.712] - 2018-12-9
### Changed
* Renamed DbaOrphanUwer series

### Added
* More integration tests!
* Docs update
* Schema output to Copy-DbaDbTableData

### Fixed
* Variable bug fix in Invoke-DbaLogShipping

## [0.9.711] - 2018-12-7
### Added
* Multi-threading to Update-DbaInstance
* System db export capabilities to Export-DbaDacPackage

### Fixed
* Ag replica now works when run outside of New-DbaAvailabilityGroup

## [0.9.710] - 2018-12-5
### Fixed
* Start-DbaMigration xplat support

## [0.9.709] - 2018-12-4
### Fixed
* Invoke-DbaAgFailover try/catch wrap to make errors pretty.
* Renamed Set-DbaJobOwner to Set-DbaAgentJobOwner
* Failed logic in Remove-DbaOrphanUser
* Removed ability to specify both KeepDays and Database from Remove-DbaDbBackupRestoreHistory

# Added
* VSCode default settings
* Pipe support in Test-DbaDbOwner

## [0.9.708] - 2018-12-4
### Fixed
* Sync AG bug having to do with read-only dbs

# Added
* Update-DbaInstance final touches

## [0.9.707] - 2018-12-3
### Fixed
* Explicit export of cmdlet module members (fixes older OS/PS issues)

## [0.9.705] - 2018-12-3
### Fixed
* Docker support for AGs

## [0.9.704] - 2018-12-3
### Fixed
* Issue where the dll was repeatedly copied in Windows
* Command exports

## [0.9.703] - 2018-12-3
### Added
* Faster import by uisng zip instead of big ol' ps1

## [0.9.702] - 2018-12-2
### Fixed
* Core support for Copy-DbaDbDatatable, Write-DbaDataTable,
* Parameter names for Copy-DbaDbQueryStoreOption

### Added
* Core support for Import-DbaCsv

## [0.9.700] - 2018-12-1
### Added
* For real true xplat including library and configs 🎉🎉🎉🎉🎉
* Added Update-DbaInstance 🎉🎉🎉🎉🎉

## [0.9.538] - 2018-11-30

### Fixed
* ComputerName resolution for fqdn in Connect-*Instance
* Stop-Function -Continue bug in Set-DbaPrivilege

## [0.9.537] - 2018-11-29
### Added
* Invoke-DbaDbccFreeCache
* Get-DbaDbccUserOption
* Added PolyBase support to Get-DbaService

## [0.9.535] - 2018-11-29
### Fixed
- Backup recoveryfork bug
- Standardized output for Copy command notes
- New-DbaAgentJobStep issue with server / SubSystemServer

### Added
* Get-DbaDbccHelp
* Get-DbaDbccMemoryStatus
* Get-DbaDbccProcCache

## [0.9.534] - 2018-11-29
### Fixed
- Removed mandatory=$false on parameters because it's implied

### Added
* Get-DbaAgentServer
* Set-DbaAgentServer
* Path parameter to audit copies


## [0.9.533] - 2018-11-27
### Fixed
- Removed mandatory=$false on parameters because it's implied

### Added
- Extra include and exclude options to `Sync-DbaAvailabilityGroup`
- Extra column parameters to `Import-DbaCsv`

## [0.9.532] - 2018-11-26
### Fixed
- Publish-DbaDacpackage param issues introduced by core fixes
- Resolve-DbaNetworkName resolution issue introduced by core fixes
- Some long-standing `Get-DbaBackupHistory -Force` problems were resolved

### Added
- Added VS Code recommendations

## [0.9.531] - 2018-11-24
### Added
- Support for Core and Certs
- Solution file upgraded to Core combination and VS 2017

## [0.9.531] - 2018-11-24
### Added
- Support for Core and Certs
- Solution file upgraded to Core combination and VS 2017

## [0.9.530] - 2018-11-24
### Fixed
- Fixed non-Windows imports. "Fixed" used loosely - disabled configuration to speed up import. Xplat still not fully delivered.

### Added
- Seeding support to Add-DbaAgDatabase
- More integration tests!
- Category and Database filters to Get-DbaAgentJob

## [0.9.525] - 2018-11-23
### Added
- CROSS PLATFORM SUPPORT INCLUDING MACOS AND LINUX 🎉

![image](https://user-images.githubusercontent.com/8278033/48960127-ac3c3980-ef6a-11e8-90ca-1e8e56df8ee0.png)

## [0.9.524] - 2018-11-23
### Added
- $script:core for easy core detection in functions

### Fixed
- Resolve-Path added to core import routine

## [0.9.523] - 2018-11-23
### Added
- Support for Dacfx for core 🎉

### Fixed
- Weird thing in Core where a string comparison didn't work so it tried to copy dbatools.dll onto itself
- Get-DbaDbFile now works for CS collation

## [0.9.522] - 2018-11-23
### Added
- Support for PS Core on Windows 🎉
- SMO core DLLs from the SqlServer module

### Fixed
- AG versioning bugs

## [0.9.521] - 2018-11-22
### Added
- This changelog.md! 🎉

### Removed
- Extra DLLs that did not seem necessary

### Changed
- Updated Glen Berry's scripts


## changelog background and additional info

### Types of changes
* Added for new features.
* Changed for changes in existing functionality.
* Deprecated for soon-to-be removed features.
* Removed for now removed features.
* Fixed for any bug fixes.
* Security in case of vulnerabilities.

### Guiding Principles
* Changelogs are for humans, not machines.
* There should be an entry for every single version.
* The same types of changes should be grouped.
* Versions and sections should be linkable.
* The latest version comes first.
* The release date of each version is displayed.
* Mention whether you follow Semantic Versioning.
