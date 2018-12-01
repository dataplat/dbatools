# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
    and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
