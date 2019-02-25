# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
    and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.773] - 2019-02-24
### Fixed
* `Install-DbaMaintenanceSolution` now removes jobs when `-SqlCredential` is used [#5096](https://github.com/sqlcollaborative/dbatools/issues/5096)
* `Copy-DbaSsisCatalog` now properly resolves type names [#4821](https://github.com/sqlcollaborative/dbatools/issues/4821)
* Can now set schedule start & end dates with `Set-DbaAgentSchedule` [#4908](https://github.com/sqlcollaborative/dbatools/issues/4908)

## [0.9.772] - 2019-02-24
### Fixed
* `Invoke-DbaDbShrink` now properly excludes system databases when `-AllUserDatabase` is specified [#5108](https://github.com/sqlcollaborative/dbatools/issues/5108)

## [0.9.771] - 2019-02-19
### Fixed
* Azure SQL DB support for creating SQL Logins in `New-DbaLogin` [#5100](https://github.com/sqlcollaborative/dbatools/issues/5100)
### Added
* `New-DbaDbMailProfile` function to create new profile for database mail

## [0.9.770] - 2019-02-16
### Fixed
* `Get-DbaAgentSchedule` returns `NULL` description [#5090](https://github.com/sqlcollaborative/dbatools/issues/5090)
### Added
* Multithreading for `Update-DbaInstance`

## [0.9.757] - 2019-02-09
### Fixed
* Handling of multiple databases in `Invoke-DbaDbUpgrade` [#5047](https://github.com/sqlcollaborative/dbatools/issues/5047)
* Visual Studio solution file reference error on import [#5056](https://github.com/sqlcollaborative/dbatools/issues/5056)
* `Copy-DbaLinkedServer` doesn't copy network name [#4087](https://github.com/sqlcollaborative/dbatools/issues/4087)

## [0.9.755] - 2019-02-09
### Fixed
* `Restore-DbaBackup` quits prematurely when target database exists [#4949](https://github.com/sqlcollaborative/dbatools/issues/4949)
### Added
* Support for `markdownlint` VS Code extension

## [0.9.754] - 2019-02-07
### Fixed
* EOL date for SQL Server 2014 SP2

## [0.9.753] - 2019-02-06
### Fixed
* Authentication issue in New-DbaAgentJobCategory [#5034](https://github.com/sqlcollaborative/dbatools/issues/5034)
* Piping issue in Backup-DbaDatabase [#5041](https://github.com/sqlcollaborative/dbatools/pull/5041)
* ConvertTo-DbaDataTable no longer ignores -EnableException [#5050](https://github.com/sqlcollaborative/dbatools/issues/5050)
* Copy-DbaDatabase now passes -Force to Set-DbaDbState [#5055](https://github.com/sqlcollaborative/dbatools/issues/5055)
* Parallelism and exception handling fixes in Get-SqlInstanceComponent [#4988](https://github.com/sqlcollaborative/dbatools/issues/4988)
### Added
* Check that databases are accessible in Get-DbaDbRoleMember [#5046](https://github.com/sqlcollaborative/dbatools/pull/5046)

## [0.9.752] - 2019-02-03
### Fixed
* Corrected math in Invoke-DbaDbShrink [#5039](https://github.com/sqlcollaborative/dbatools/issues/5039)
### Changed
* Remove dependency on System.Data objects in Get-DbaDbccMemoryStatus [#5031](https://github.com/sqlcollaborative/dbatools/pull/5031)
### Added
* Support for pipeline input on Set-DbaAgentJobStep [#4350](https://github.com/sqlcollaborative/dbatools/issues/4350)
* Add missing server parameter in Set-DbaAgentJobStep [#4715](https://github.com/sqlcollaborative/dbatools/issues/4715)

## [0.9.751] - 2019-01-31
### Fixed
* Properly support individual databases in Invoke-DbaDbClone [#5015](https://github.com/sqlcollaborative/dbatools/issues/5015)
* Properly support pipeline data for Remove-DbaAgReplica [#5013](https://github.com/sqlcollaborative/dbatools/issues/5013)
* Add-DbaAgReplica now adds replicas [#4847](https://github.com/sqlcollaborative/dbatools/issues/4847)

## [0.9.750] - 2019-01-25
### Added
* Type switch for Backup-DbaDatabase to get the correct backup from backup history
* Reuse server connection for Get-DbaDefaultPath within Backup-DbaDatabase

## [0.9.749] - 2019-01-24
### Changed
* Remove LSN check from Backup-DbaDatabase

## [0.9.748] - 2019-01-24
### Fixed
* Import-DbaCsv does not accept multiple flags like -KeepNulls and -TableLock [#4998](https://github.com/sqlcollaborative/dbatools/issues/4998)

### Added
* Build reference for SQL Server 2016 SP2 CU5

## [0.9.747] - 2019-01-23
### Changed
* Pass credentials through to Get-DbaRegistryRoot from Get-DbaProductKey

## [0.9.745] - 2019-01-23
### Fixed
* Output mismatch in Format-DbaBackupInformation

## [0.9.744] - 2019-01-23
### Changed
* Figure out new name before performing checks in Copy-DbaDbMail

## [0.9.743] - 2019-01-20
### Fixed
* Correct names of jobs and schedules in Invoke-DbaDbLogShipping [#4972](https://github.com/sqlcollaborative/dbatools/issues/4972)
* Correct path for output files for Install-DbaMaintenanceSolution [#4950](https://github.com/sqlcollaborative/dbatools/issues/4950)
### Changed
* Message formatting in Copy-DbaDbMail

### Added
* Support hostnames ending with hyphen [#4090](https://github.com/sqlcollaborative/dbatools/issues/4090)

## [0.9.742] - 2019-01-15
### Fixed
* Additional LSN comparison fix in Select-DbaBackupInformation [#4940](https://github.com/sqlcollaborative/dbatools/issues/4940)

## [0.9.741] - 2019-01-11
### Fixed
* ApplicationIntent handling in Connect-DbaInstance and Invoke-DbaQuery

## [0.9.740] - 2019-01-11
### Fixed
* [Import-DbaXESessionTemplate] Name cannot be specified with multiple files or templates because the Session will already exist. [#4923](https://github.com/sqlcollaborative/dbatools/issues/4923)
* Correct type conversions for LSN comparison in Select-DbaBackupInformation

### Added
* Add money & text types to data masking

## [0.9.739] - 2019-01-11
### Fixed
* Typo in DefaultDB parameter for Set-DbaLogin & New-DbaLogin

### Changed
* Verify that cumulative updates passed to Test-DbaBuild are a list

## [0.9.738] - 2019-01-10
### Fixed
* Set-DbaAgentJob: Changing EventLogLevel to 0/Never will not be applied [#4927](https://github.com/sqlcollaborative/dbatools/issues/4927)

### Added
* Set default database with Set-DbaLogin

## [0.9.737] - 2019-01-08
### Changed
* Latest versions of Glenn Berry's diagnostic queries
* Only update fullname in Resolve-DbaNetworkName when running from a remote PC
* Implement -whatif for Install-DbaMaintenanceSolution [#4901](https://github.com/sqlcollaborative/dbatools/issues/4901)

## [0.9.735] - 2019-01-07
### Fixed
* Proper messaging when running Get-DbaPowerPlan on a local instance without an elevated session [#4777](https://github.com/sqlcollaborative/dbatools/issues/4777)

### Added
* ReadOnly option for Invoke-DbaQuery [#3451](https://github.com/sqlcollaborative/dbatools/issues/3451)

### Removed
* Officially remove Invoke-SqlCmd2 (use Invoke-DbaQuery instead)
* Various unit tests [#4695]

## [0.9.734] - 2019-01-02
### Changed
* Documentation update for Get-DbaDbIdentity
* Latest versions of Glenn Berry's diagnostic queries

## [0.9.734] - 2019-01-02
### Changed
* Documentation update for Get-DbaDbIdentity
* Latest versions of Glenn Berry's diagnostic queries

## [0.9.733] - 2018-12-31
### Added
* Support for additional DBCC commands [#4493](https://github.com/sqlcollaborative/dbatools/issues/4493)
* Support for PSCore related to Test-Connection [#4840](https://github.com/sqlcollaborative/dbatools/issues/4840)

## [0.9.732] - 2018-12-26
### Changed
* Logic in Resolve-DbaNetworkName
* Revised output object construction in Resolve-DbaNetworkName
* Revised exception handling in Get-DbaDependency

### Added
* New options for Import-DbaCsv
* Support for -whatif and -confirm to Publish-DbaDacPackage [#4824](https://github.com/sqlcollaborative/dbatools/issues/4824)

## [0.9.731] - 2018-12-23
### Fixed
* Excessive error messages & conflicting parameters in Restore-DbaDatabase
* Warning with no output in Get-DbaBuildReference [#4794](https://github.com/sqlcollaborative/dbatools/issues/4794)
* Invalid type conversion in Get-DbaDependency [#4768](https://github.com/sqlcollaborative/dbatools/issues/4768)

### Changed
* Logic in Resolve-DbaNetworkName

### Added
* PSCore enhancements in Test-DbaConnection
* Verify backup for log & diff backups in Restore-DbaDatabase [#4861](https://github.com/sqlcollaborative/dbatools/issues/4861)
* Support packages to CI build process

### Removed
* Test-Connection in Reset-DbaAdmin, Resolve-DbaNetworkName, internal functions

## [0.9.730] - 2018-12-21
### Fixed
* Elapsed transaction control in Invoke-DbaDbDataMasking

## [0.9.729] - 2018-12-21
### Fixed
* Elapsed time tracking in Invoke-DbaDbDataMasking

## [0.9.728] - 2018-12-21
### Fixed
* SQL output for striped restores in Get-DbaBackupInformation

## [0.9.727] - 2018-12-20
### Added
* Enhancements to data masking
* Enhancements to Update-DbaInstance

## [0.9.725] - 2018-12-20
### Added
* Failsafe value in Invoke-DbaDbDataMasking

## [0.9.724] - 2018-12-19
### Added
* Deterministic data masking in Invoke-DbaDbDataMasking & New-DbaDbMaskingConfig

## [0.9.722] - 2018-12-19
### Fixed
* Random creation of values in Invoke-DbaDbDataMasking

## [0.9.721] - 2018-12-18
### Added
* Dynamic database list to Invoke-DbaDbDataMasking
* Add Geometry to check of unsupported data types for Invoke-DbaDbDataMasking

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
* xplat support notification to Find-DbaCommand / docs.dbatools.io
* More integration tests
* New commands: Invoke-DbaDbDataMasking and New-DbaDbMaskingConfig

## [0.9.714] - 2018-12-10
### Fixed
* Get-DbaBackupHistory - fully honors need to exclude system dbs
* Fixed docs/typos in various commands

## [0.9.712] - 2018-12-09
### Changed
* Renamed DbaOrphanUser series

### Added
* More integration tests!
* Docs update
* Schema output to Copy-DbaDbTableData

### Fixed
* Variable bug fix in Invoke-DbaLogShipping

## [0.9.711] - 2018-12-07
### Added
* Multi-threading to Update-DbaInstance
* System db export capabilities to Export-DbaDacPackage

### Fixed
* Ag replica now works when run outside of New-DbaAvailabilityGroup

## [0.9.710] - 2018-12-05
### Fixed
* Start-DbaMigration xplat support

## [0.9.709] - 2018-12-04
### Fixed
* Invoke-DbaAgFailover try/catch wrap to make errors pretty.
* Renamed Set-DbaJobOwner to Set-DbaAgentJobOwner
* Failed logic in Remove-DbaOrphanUser
* Removed ability to specify both KeepDays and Database from Remove-DbaDbBackupRestoreHistory

### Added
* VSCode default settings
* Pipe support in Test-DbaDbOwner

## [0.9.708] - 2018-12-04
### Fixed
* Sync AG bug having to do with read-only dbs

### Added
* Update-DbaInstance final touches

## [0.9.707] - 2018-12-03
### Fixed
* Explicit export of cmdlet module members (fixes older OS/PS issues)

## [0.9.705] - 2018-12-03
### Fixed
* Docker support for AGs

## [0.9.704] - 2018-12-03
### Fixed
* Issue where the dll was repeatedly copied in Windows
* Command exports

## [0.9.703] - 2018-12-03
### Added
* Faster import by using zip instead of big ol' ps1

## [0.9.702] - 2018-12-02
### Fixed
* Core support for Copy-DbaDbDatatable, Write-DbaDataTable,
* Parameter names for Copy-DbaDbQueryStoreOption

### Added
* Core support for Import-DbaCsv

## [0.9.700] - 2018-12-01
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
* Backup recoveryfork bug
* Standardized output for Copy command notes
* New-DbaAgentJobStep issue with server / SubSystemServer

### Added
* Get-DbaDbccHelp
* Get-DbaDbccMemoryStatus
* Get-DbaDbccProcCache

## [0.9.534] - 2018-11-29
### Fixed
* Removed mandatory=$false on parameters because it's implied

### Added
* Get-DbaAgentServer
* Set-DbaAgentServer
* Path parameter to audit copies

## [0.9.533] - 2018-11-27
### Fixed
* Removed mandatory=$false on parameters because it's implied

### Added
* Extra include and exclude options to `Sync-DbaAvailabilityGroup`
* Extra column parameters to `Import-DbaCsv`

## [0.9.532] - 2018-11-26
### Fixed
* Publish-DbaDacPackage param issues introduced by core fixes
* Resolve-DbaNetworkName resolution issue introduced by core fixes
* Some long-standing `Get-DbaBackupHistory -Force` problems were resolved

### Added
* Added VS Code recommendations

## [0.9.531] - 2018-11-24
### Added
* Support for Core and Certs
* Solution file upgraded to Core combination and VS 2017

## [0.9.531] - 2018-11-24
### Added
* Support for Core and Certs
* Solution file upgraded to Core combination and VS 2017

## [0.9.530] - 2018-11-24
### Fixed
* Fixed non-Windows imports. "Fixed" used loosely - disabled configuration to speed up import. Xplat still not fully delivered.

### Added
* Seeding support to Add-DbaAgDatabase
* More integration tests!
* Category and Database filters to Get-DbaAgentJob

## [0.9.525] - 2018-11-23
### Added
* CROSS PLATFORM SUPPORT INCLUDING MACOS AND LINUX 🎉

![image](https://user-images.githubusercontent.com/8278033/48960127-ac3c3980-ef6a-11e8-90ca-1e8e56df8ee0.png)

## [0.9.524] - 2018-11-23
### Added
* $script:core for easy core detection in functions

### Fixed
* Resolve-Path added to core import routine

## [0.9.523] - 2018-11-23
### Added
* Support for Dacfx for core 🎉

### Fixed
* Weird thing in Core where a string comparison didn't work so it tried to copy dbatools.dll onto itself
* Get-DbaDbFile now works for CS collation

## [0.9.522] - 2018-11-23
### Added
* Support for PS Core on Windows 🎉
* SMO core DLLs from the SqlServer module

### Fixed
* AG versioning bugs

## [0.9.521] - 2018-11-22
### Added
* This changelog.md! 🎉

### Removed
* Extra DLLs that did not seem necessary

### Changed
* Updated Glen Berry's scripts

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
