# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
    and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2019-06-20
### Fixed
* Version number now starts with 1 instead of 0
* `Get-DbaRegisteredServer` fixed on Linux & macOS [#5655](https://github.com/sqlcollaborative/dbatools/pull/5655)
* `ConvertTo-DbaDataTable` is not converting all data [#4938](https://github.com/sqlcollaborative/dbatools/issues/4938)
* `Stop-DbaProcess` does not support `-whatif` [#5658](https://github.com/sqlcollaborative/dbatools/issues/5658)
* `New-DbaDbSnapshot` doesn't create snapshot on a mirrored database [#5631](https://github.com/sqlcollaborative/dbatools/issues/5631)
* `Get-DbaRegisteredServer` filter group properly for all types [#5671](https://github.com/sqlcollaborative/dbatools/pull/5671)
* `Set-DbaLogin` and `New-DbaLogin` have slightly different parameter names [#5684](https://github.com/sqlcollaborative/dbatools/issues/5684)
* Handling of special characters in `Invoke-DbaDbDecryptObject` [#5689](https://github.com/sqlcollaborative/dbatools/pull/5689)
* `Test-DbaDbCompatability` uses `Credential` parameter and fails when a SQL credential is passed [#5666](https://github.com/sqlcollaborative/dbatools/issues/5666)
* `Invoke-DbaDbClone` server version check failed [#5673](https://github.com/sqlcollaborative/dbatools/issues/5673)
* Script batch terminator fix in `Export-DbaScript` [#5693](https://github.com/sqlcollaborative/dbatools/pull/5693)
* `Copy-DbaLogin` - stop if `force` is used when `truelogin` is not in login list [#5665](https://github.com/sqlcollaborative/dbatools/issues/5665)
* `Restore-DbaDatabase` calculates file size incorrectly [#5688](https://github.com/sqlcollaborative/dbatools/issues/5688)
* `Add-DbaAgDatabase` targets restore at Primary server rather than secondary [#5682](https://github.com/sqlcollaborative/dbatools/issues/5682)
* Fix comparison bug in `Set-DbaAgentSchedule` [#5713](https://github.com/sqlcollaborative/dbatools/pull/5713)
* `Import-DbaRegServer` doesn't properly import subgroups [#5706](https://github.com/sqlcollaborative/dbatools/issues/5706)
* Improve errors/warnings on `Add-DbaRegServerGroup` [#5752](https://github.com/sqlcollaborative/dbatools/pull/5752)
* Fix `Backup-DbaDatabase` date conversion
  * [#5751](https://github.com/sqlcollaborative/dbatools/issues/5751)
  * [#5748](https://github.com/sqlcollaborative/dbatools/issues/5748)
  * [#5744](https://github.com/sqlcollaborative/dbatools/issues/5744)
  * [#5742](https://github.com/sqlcollaborative/dbatools/issues/5742)
  * [#5308](https://github.com/sqlcollaborative/dbatools/issues/5308)
  * [#5024](https://github.com/sqlcollaborative/dbatools/issues/5024)
* `Add-DbaRegServer` not adding if group is specified [#5756](https://github.com/sqlcollaborative/dbatools/issues/5756)
* `Add-DbaAgDatabase` uses English for date comparison [#5701](https://github.com/sqlcollaborative/dbatools/issues/5701)
* Fix Secondary Log Shipping Monitor [#5764](https://github.com/sqlcollaborative/dbatools/pull/5764)
* .NET Core on macOS no longer throws errors on loading [#5773](https://github.com/sqlcollaborative/dbatools/pull/5773)
* `Add-DbaAgDatabase` tries to modify seeding mode on SQL Server 2014 [#5702](https://github.com/sqlcollaborative/dbatools/issues/5702)
* Avoid errors on importing on x86 processors [#5785](https://github.com/sqlcollaborative/dbatools/pull/5785)

### Removed
* Remove "LATEST" from buildreference in `Get-DbaBuildReference` [#5379](https://github.com/sqlcollaborative/dbatools/issues/5379)
* Remove fallbacks for `Expand-Archive` [#5731](https://github.com/sqlcollaborative/dbatools/pull/5731)

### Changed
* Skip HKEY_LOCAL_MACHINE checks on Linux [#5663](https://github.com/sqlcollaborative/dbatools/pull/5663)
* Improved data masking [#5664](https://github.com/sqlcollaborative/dbatools/pull/5664)
* Improved progress bar and performance in `Invoke-DbaDbDataMasking` [#5667](https://github.com/sqlcollaborative/dbatools/pull/5667)
* Rename path parameters in `Invoke-DbaDbLogShipping` [#5672](https://github.com/sqlcollaborative/dbatools/pull/5672)
* Revised `ComputerName` resolution in `Connect-DbaInstance` [#5687](https://github.com/sqlcollaborative/dbatools/pull/5687)
* For commands that support `-Force`, it should not prompt for confirmation [#5422](https://github.com/sqlcollaborative/dbatools/issues/5422)
* Various small changes suggested by PowerShell Script Analyzer including removing unused variables
* Remove duplicated effort in `Install-DbaInstance` [#5723](https://github.com/sqlcollaborative/dbatools/pull/5723)
* Improve patterns for PII recognition [#5740](https://github.com/sqlcollaborative/dbatools/pull/5740)
* Improve date masking [#5741](https://github.com/sqlcollaborative/dbatools/pull/5741)
* Latest versions of Glenn Berry's diagnostic queries
* Mass rename `InstanceRole` to `ServerRole` [#5787](https://github.com/sqlcollaborative/dbatools/pull/5787)

### Added
* Pipeline support for certificate functions [#5659](https://github.com/sqlcollaborative/dbatools/pull/5659)
* `Set-DbatoolsConfig -Register` & `Find-DbaInstance` Domain Discovery [#5675](https://github.com/sqlcollaborative/dbatools/pull/5675)
* `ShouldProcess` support in `Export-DbaDbTableData` [#5727](https://github.com/sqlcollaborative/dbatools/pull/5727)
* Additional support for Local Server Groups [#5734](https://github.com/sqlcollaborative/dbatools/pull/5734)
* New Command Data Masking and Generator Tests [#5738](https://github.com/sqlcollaborative/dbatools/pull/5738)
* New functions to work with instance and database roles [#5746](https://github.com/sqlcollaborative/dbatools/pull/5746)
* Add support for SQL Server 2000 and piping to `Restore-DbaDatabase` [#5771](https://github.com/sqlcollaborative/dbatools/pull/5771)
* Allow piped input to `Backup-DbaDatabase` SQL Server 2000 [#5778](https://github.com/sqlcollaborative/dbatools/pull/5778)

## [prerelease] - 2019-05-30
### Fixed
* `New-DbaAvailabilityGroup` does not assign permissions for service account to connect to Endpoint [#5341](https://github.com/sqlcollaborative/dbatools/issues/5341)

## [prerelease] - 2019-05-30
### Fixed
* Rename multiple `DbaServer` functions to `DbaInstance` [#4580](https://github.com/sqlcollaborative/dbatools/issues/4580)
* `New-DbaDbUser` errors when database is missing or incorrect [#5613](https://github.com/sqlcollaborative/dbatools/pull/5613)
* Allow `Start-DbaXESession` `stopat` parameter to include longer running periods [#5362](https://github.com/sqlcollaborative/dbatools/issues/5362)
* Workaround for `.Databases` collection in Azure [#5621](https://github.com/sqlcollaborative/dbatools/issues/5621)
* Export Add Append and other Fixes [#5627](https://github.com/sqlcollaborative/dbatools/pull/5627)
* `Export-DbaScript` returns 2 spaces if object doesn't exist [#5418](https://github.com/sqlcollaborative/dbatools/issues/5418)
* `New-DbaComputerCertificate -SelfSigned` throws error [#5637](https://github.com/sqlcollaborative/dbatools/issues/5637)
* `Encoding` property fixed on `Import-DbaCsv` [#5634](https://github.com/sqlcollaborative/dbatools/issues/5634)
* `Get-DbaRegisteredServer` Local Server Groups bad grouping when instances are used [#5632](https://github.com/sqlcollaborative/dbatools/issues/5632)
* `Start-DbaMigration` with `-BackupRestore -SetSourceReadOnly` tries to update database owner while restored DB is still READ_ONLY [#5370](https://github.com/sqlcollaborative/dbatools/issues/5370)
* Greedy AG creation [#5650](https://github.com/sqlcollaborative/dbatools/issues/5650)

### Removed
* Remove synconly from `Copy-DbaLogin` [#5510](https://github.com/sqlcollaborative/dbatools/issues/5510)
* Remove `-CheckForSql` parameter from `Get-DbaDiskSpace` as it doesn't work well [#5023](https://github.com/sqlcollaborative/dbatools/issues/5023)
* Remove various parameters marked for removal at version 1.0.0

### Changed
* Rename `Test-DbaVirtualLogFile` to `Measure-DbaDbVirtualLogFile` [#2407](https://github.com/sqlcollaborative/dbatools/issues/2407)
* Replace output with Progress Bar in `Install-DbaMaintenanceSolution` [#5644](https://github.com/sqlcollaborative/dbatools/pull/5644)
* Standardize `Remove-DbaDatabaseSafely` [#5618](https://github.com/sqlcollaborative/dbatools/pull/5618)
* Parameter names `BackupDirectory` and `backupFileName` changed on `Backup-DbaDatabase` to match PowerShell standard [#5648](https://github.com/sqlcollaborative/dbatools/pull/5648)

### Added
* Multifactor authentication support for Azure [#5593](https://github.com/sqlcollaborative/dbatools/pull/5593)
* Certificate support in `Connect-DbaInstance` [#5605](https://github.com/sqlcollaborative/dbatools/pull/5605)
* Add default configuration for CMS and IncludeLocal in `Get-DbaRegisteredServer` [#5607](https://github.com/sqlcollaborative/dbatools/pull/5607)
* Add `Source` column to output of `Get-DbaRegistered Server` [#5606](https://github.com/sqlcollaborative/dbatools/pull/5606)
* Latest CU and SP build numbers to builds
* Allow user to specify client name in `Connect-DbaInstance` [#5564](https://github.com/sqlcollaborative/dbatools/issues/5564)
* Multi-instance support for `Export-DbaLogin` [#5635](https://github.com/sqlcollaborative/dbatools/pull/5635)
* Azure support for `Write-DbaDbTableData` [#5643](https://github.com/sqlcollaborative/dbatools/pull/5643)

## [prerelease] - 2019-05-24
### Fixed
* `Restore-DbaDatabase` Fails To Process Other Databases After Failure [#5400](https://github.com/sqlcollaborative/dbatools/issues/5400)
* `Get-DbaLastGoodCheckDb` fails on Database names with non standard characters [#5585](https://github.com/sqlcollaborative/dbatools/issues/5585)

### Changed
* `CmsReg` in function names is now `Reg` to reflect support for registered servers beyond CMS [#5575](https://github.com/sqlcollaborative/dbatools/pull/5575)
* Improve `Find-DbaTrigger` [#5570](https://github.com/sqlcollaborative/dbatools/pull/5570)
* Export function output standardized to one directory [#4704](https://github.com/sqlcollaborative/dbatools/issues/4704)

### Removed
* Aliases and deprecation warnings for compatibility with old function names [#5582](https://github.com/sqlcollaborative/dbatools/pull/5582)

### Added
* New function `Get-DbaDbFileGroup` to get filegroup information [#5568](https://github.com/sqlcollaborative/dbatools/pull/5568)
* Add Azure Data Studio support to `Get-DbaRegisteredServer` [#5578](https://github.com/sqlcollaborative/dbatools/pull/5578)
* New function `Get-DbaDbObjectTrigger` [#5570](https://github.com/sqlcollaborative/dbatools/pull/5570)
* Add Connection String support for Registered Servers in `Connect-DbaInstance` [#5579](https://github.com/sqlcollaborative/dbatools/pull/5579)
* New command `New-DbaDiagnosticAdsNotebook` [#5577](https://github.com/sqlcollaborative/dbatools/pull/5577)
* Add support for alternative credentials in Azure Data Studio in `Get-DbaRegisteredServer` [#5580](https://github.com/sqlcollaborative/dbatools/pull/5580)

## [prerelease] - 2019-05-22
### Fixed
* Now able to install multiple features at once with `Install-DbaInstance` [#5573](https://github.com/sqlcollaborative/dbatools/pull/5573)

### Added
* Latest CU and SP build numbers to builds
* Functions for managing Server and Database Roles [#5520](https://github.com/sqlcollaborative/dbatools/pull/5520)

## [prerelease] - 2019-05-20
### Fixed
* `Import-DbaCsv` sometimes does not work if `AutoCreateTable` is not used [#5553](https://github.com/sqlcollaborative/dbatools/issues/5553)
* `Get-DbaDatabase` function `-Encrypted` switch parameter not working [#5554](https://github.com/sqlcollaborative/dbatools/issues/5554)
* Unable to pipe `Get-DbaUser` into `Remove-DbaUser` when multiple users are selected on the same database [#4971](https://github.com/sqlcollaborative/dbatools/issues/4971)
* `Set-DbaDbRecoveryModel` - error on snapshot [#5543](https://github.com/sqlcollaborative/dbatools/issues/5534)

### Removed
* Unusable parameter `IncludeSystemDb` from `Remove-DbaDatabase` [#5561](https://github.com/sqlcollaborative/dbatools/pull/5561)

### Added
* New function `Add-DbaTable` [#5272](https://github.com/sqlcollaborative/dbatools/issues/5272)

## [prerelease] - 2019-05-17
### Fixed
* Module base location in multiple functions
* Improved module load time
* `Get-DbaOperatingSystem` - Caption is blank [#5549](https://github.com/sqlcollaborative/dbatools/issues/5549)

## Changed
* Rename `Watch-DbaWatchUpdate` to `Watch-DbatoolsWatchUpdate` [#5537](https://github.com/sqlcollaborative/dbatools/issues/5537)
* Connection String enhancements for `New-DbaConnectionString` and `Connect-DbaInstance` [#5196](https://github.com/sqlcollaborative/dbatools/issues/5196)

### Added
* More names to `Invoke-DbatoolsRenameHelper`
* Support for PowerShell Core in `Invoke-DbaAsync`
* `ExtractPath` parameter to multiple commands [#5529](https://github.com/sqlcollaborative/dbatools/pull/5529) (also fixes [#5512](https://github.com/sqlcollaborative/dbatools/issues/5512))
* Pipeline support for `Set-DbaDbOwner` [#5545](https://github.com/sqlcollaborative/dbatools/issues/5545)

## [0.9.828] - 2019-05-15
### Added
* `Get-DbatoolsChangeLog` to open link to this changelog [#5528](https://github.com/sqlcollaborative/dbatools/pull/5528)

## [0.9.827] - 2019-05-14
### Fixed
* `Export-DbaCredential` - `-Identity` doesn't filter, DAC duplication problem [#5443](https://github.com/sqlcollaborative/dbatools/issues/5443)
* Fix step count and retry when using `Start-DbaAgentJob` and `-Verbose` [#5519](https://github.com/sqlcollaborative/dbatools/pull/5519)
* `Invoke-DbaDbLogShipping` line 1360 has a extra `)` [#5523](https://github.com/sqlcollaborative/dbatools/issues/5523)

## [0.9.826] - 2019-05-13
### Fixed
* `Set-DbaAgentSchedule` does not properly set `EndTime` [#5513](https://github.com/sqlcollaborative/dbatools/issues/5513)
### Changed
* Updates to Sync Permissions and Copy Login `-SyncOnly` [#5511](https://github.com/sqlcollaborative/dbatools/pull/5511)
### Added
* Add progress bars to Find-DbaInstance [#5515](https://github.com/sqlcollaborative/dbatools/issues/5515)

## [0.9.825] - 2019-05-09
### Fixed
* Throw error when attempting to fetch user permissions from Azure SQL DB (currently not supported) [#5076](https://github.com/sqlcollaborative/dbatools/issues/5076)
* Sync-DbaLoginPermission ignores "Login" parameter; syncs everything [#5505](https://github.com/sqlcollaborative/dbatools/issues/5505)
* Errors with Copy-DbaLogin -SyncOnly [#4909](https://github.com/sqlcollaborative/dbatools/issues/4909)
### Added
* Add `Write-ProgressHelper` to `Update-SqlPermission` [#5509](https://github.com/sqlcollaborative/dbatools/issues/5509)

## [0.9.824] - 2019-05-09
### Fixed
* `Invoke-DbaDbMirroring` fails to establish connection with Mirror server [#5318](https://github.com/sqlcollaborative/dbatools/issues/5318)
### Added
* Support for Linux paths in `Get-DbaMaintenanceSolutionLog` [#5035](https://github.com/sqlcollaborative/dbatools/issues/5035)
* Support for `-WhatIf` in `Reset-DbatoolsConfig` [#5499](https://github.com/sqlcollaborative/dbatools/pull/5499)

## [0.9.823] - 2019-05-08
### Fixed
* `Show-DbaDbList` calls non-existent function [#5494](https://github.com/sqlcollaborative/dbatools/issues/5494)
* Return elapsed minutes from `Get-DbaSsisExecutionHistory` [#5492](https://github.com/sqlcollaborative/dbatools/pull/5492)
### Added
* Additional verbose output in `Start-DbaAgentJob` [#5488](https://github.com/sqlcollaborative/dbatools/pull/5488)

## [0.9.822] - 2019-05-06
### Fixed
* `Get-DbaCmsRegServer` overwrites the first server in the list with the CMS when using `-IncludeSelf` [#5367](https://github.com/sqlcollaborative/dbatools/issues/5367)
### Changed
* Error handling & messaging in `Find-DbaInstance` [#5482](https://github.com/sqlcollaborative/dbatools/pull/5482)
* Replace output with progress bar in certificate-related functions [#5471](https://github.com/sqlcollaborative/dbatools/pull/5471)
### Added
* Certificate type in Get-DbaComputerCertificate [#5483](https://github.com/sqlcollaborative/dbatools/pull/5483)

## [0.9.821] - 2019-05-02
### Fixed
* Turkish "I" Char Problem When using OS functions [#5453](https://github.com/sqlcollaborative/dbatools/issues/5453) [#5467](https://github.com/sqlcollaborative/dbatools/pull/5467)
### Changed
* Overhaul of `Show-DbaDbList` for 1.0 compliance [#5458](https://github.com/sqlcollaborative/dbatools/issues/5458i)
* Overhaul of `Get-DbaMsdtc` for 1.0 compliance [#5456](https://github.com/sqlcollaborative/dbatools/issues/5456)
* Overhaul of `Get-DbaDetachedDatabaseInfo` for 1.0 compliance [#5455](https://github.com/sqlcollaborative/dbatools/issues/5455)
### Removed
* `Restore-DbaBackupFromDirectory`, superseded by `Restore-DbaDatabase` [#5457](https://github.com/sqlcollaborative/dbatools/issues/5457)
* Remove default value of seeding mode in `Add-DbaAgReplica` [#5469](https://github.com/sqlcollaborative/dbatools/pull/5469)

## [0.9.820] - 2019-05-02
### Fixed
* `Update-DbaInstance` uses the same folder to extract the files [#5447](https://github.com/sqlcollaborative/dbatools/issues/5447)
* `Restore-DbaDatabase` reports more than 1 database passed in when only 1 was passed  [#5425](https://github.com/sqlcollaborative/dbatools/issues/5425)
### Changed
* Access token enhancements

## [0.9.819] - 2019-05-01
### Added
* `LastError` parameter on `Get-DbaToolsLog` to only get the most recent error in the log
* Support for Managed Identities in `New-DbaAzAccessToken`

## [0.9.818] - 2019-04-30
### Fixed
* `Get-DBAAvailabilityGroup` `IsPrimary` returns false when a port number is passed in under `$SQLInstance` [#5435](https://github.com/sqlcollaborative/dbatools/issues/5435)

## [0.9.817] - 2019-04-30
### Changed
* `Test-DbaLasBackup` explains why the `master` database is skipped
### Added
* `New-DbaAccessToken` for generating Azure oauth2 tokens
* `Invoke-DbaDbPiiScan` to scan for Personally Identifiable Information

## [0.9.814] - 2019-04-29
### Fixed
* `Copy-DbaAgentSchedule` does not overwrite schedules that already exist, even with `-Force` supplied [#5412](https://github.com/sqlcollaborative/dbatools/issues/5412)
* `Get-DBABuildReference` missing 13.0.5270 [#5408](https://github.com/sqlcollaborative/dbatools/issues/5408)
### Added
* Azure AccessToken support

## [0.9.812] - 2019-04-27
### Fixed
* Various migration fixes [#5414](https://github.com/sqlcollaborative/dbatools/pull/5414)
* `Set-DbaNetworkCertificate` not granting permissions to private key [#5417](https://github.com/sqlcollaborative/dbatools/pull/5417)

## [0.9.811] - 2019-04-25
### Changed
* Enhancements to data masking [#5388](https://github.com/sqlcollaborative/dbatools/pull/5388)
### Added
* Add multi-IP and subnet support to `Add-DbaAgListener` [#5411](https://github.com/sqlcollaborative/dbatools/pull/5411)
* Functions to get, enable and disable startup procedures [#5407](https://github.com/sqlcollaborative/dbatools/pull/5407)

## [0.9.810] - 2019-04-25
### Fixed
* `Test-DbaDbCompression` fails on case-sensitive collations [#5404](https://github.com/sqlcollaborative/dbatools/issues/5404)
### Added
* Latest SQL Server build references
* `Backup-DbaServiceMasterKey` function to back up the service master key for instances [#5397](https://github.com/sqlcollaborative/dbatools/issues/5397)

## [0.9.809] - 2019-04-20
### Fixed
* `Test-DbaConnection` returns warnings and more useful objects when unable to resolve/connect to host

## [0.9.808] - 2019-04-18
### Fixed
* `Get-DbaDbMasterKey` does not use `$SQLCredential` if passed [#5381](https://github.com/sqlcollaborative/dbatools/issues/5381)

## [0.9.805] - 2019-04-17
### Fixed
* `Restore-DBADatabase` with multiple DBs found picks one at random [#5364](https://github.com/sqlcollaborative/dbatools/issues/5364)
* Assignment of subschedule interval when a daily job schedule is set via `Set-DbaAgentSchedule` [#5288](https://github.com/sqlcollaborative/dbatools/issues/5288)
* `Set-DbaAgentJobStep` throws db not present error when updating `CmdExec` steps [#5354](https://github.com/sqlcollaborative/dbatools/issues/5354)

### Added
* Support for striping backups with multiple block blobs on Azure in `Backup-DbaDatabase`
* Basic support for migrations with Azure Managed Instances

## [0.9.804] - 2019-04-14
### Fixed
* `Copy-DBAAgentAlert` incorrectly asserting that Agent Operators do not exist [#5300](https://github.com/sqlcollaborative/dbatools/issues/5300)
* `Test-DbaLastBackup` fails if backup was mirrored based on Get-DbaBackupHistory output [#5360](https://github.com/sqlcollaborative/dbatools/issues/5360)
* Issue handling restores of striped backups from non file/history sources in `Select-DbaBackupInformation` [#5357](https://github.com/sqlcollaborative/dbatools/issues/5357)
### Added
* Add check and warning when copying a Windows login to Azure Managed Instance via `Copy-DbaLogin`

## [0.9.803] - 2019-04-10
### Fixed
* Correct support for AWS in `Get-DbaComputerSystem` [#5336](https://github.com/sqlcollaborative/dbatools/issues/5336)
* Remove empty notes from output of `Set-DbaDbState` [#5345](https://github.com/sqlcollaborative/dbatools/pull/5345)
* Backup to URL with Folder Fails with Error [#5347](https://github.com/sqlcollaborative/dbatools/issues/5347)
* `Invoke-DbaLogShipping` error thrown when specifying a folder containing the full backup [#5348](https://github.com/sqlcollaborative/dbatools/pull/5348)

## [0.9.802] - 2019-04-06
### Fixed
* `Find-DbaStoredProcedure` does not report TextHeader content [#3687](https://github.com/sqlcollaborative/dbatools/issues/3687)
### Changed
* Parameter for setting default database to specified db by parameter for all logins in `Export-DbaLogin`

## [0.9.801] - 2019-04-04
### Fixed
* Properly use `append` in `Export-DbaRepServerSetting` [#5333](https://github.com/sqlcollaborative/dbatools/pull/5333)
### Added
* New functions for data generation [#5331](https://github.com/sqlcollaborative/dbatools/pull/5331)

## [0.9.800] - 2019-04-02
### Changed
* Latest versions of Glenn Berry's diagnostic queries
### Added
* Auto-map column names in `Import-DbaCsv` [#5321](https://github.com/sqlcollaborative/dbatools/pull/5321)

## [0.9.799] - 2019-03-31
### Fixed
* `New-DbaAvailabilityGroup` Missing Implementation of DtcSupport [#5310](https://github.com/sqlcollaborative/dbatools/issues/5310)
### Added
* Support for Managed Instances and Azure Blob Storage in `Copy-DbaDatabase` [#5322](https://github.com/sqlcollaborative/dbatools/pull/5322)

## [0.9.798] - 2019-03-28
### Changed
* Remove output from `Write-DbaDataTable` [#5313](https://github.com/sqlcollaborative/dbatools/pull/5313)
### Added
* Session timeout parameter for `Set-DbaAgReplica` [#5139](https://github.com/sqlcollaborative/dbatools/issues/5139)
* PS Core support for `Read-DbaBackupHeader` [#5070](https://github.com/sqlcollaborative/dbatools/issues/5070)
* Restores in Managed Instances [#5309](https://github.com/sqlcollaborative/dbatools/pull/5309)

## [0.9.797] - 2019-03-25
### Fixed
* `Test-DbaDbLogShipStatus` incorrectly reports no information available [#5287](https://github.com/sqlcollaborative/dbatools/issues/5287)
* Job ownership transfer logic in `Update-SqlPermission`

### Added
* Managed Instance parameter warnings

## [0.9.795] - 2019-03-23
### Fixed
* `Get-DbaUserPermission` misses database role assignments [#4887](https://github.com/sqlcollaborative/dbatools/issues/4887)
* Build dates for the latest SQL Server Cumulative Updates

## [0.9.794] - 2019-03-22
### Fixed
* `Get-DbaBackupHistory` warnings and not finding the right backup [#5263](https://github.com/sqlcollaborative/dbatools/issues/5263)
* `New-DbaAvailabilityGroup` lacks resiliency [#4933](https://github.com/sqlcollaborative/dbatools/issues/4933)
* `Add-DbaAgReplica` missing permission for automatic seeding [#4816](https://github.com/sqlcollaborative/dbatools/issues/4816)
* `Test-DbaLastBackup` is not restoring user databases [#4574](https://github.com/sqlcollaborative/dbatools/issues/4574)
* `Set-DbaSpConfigure` & `Get-DbaSpConfigure` "The property 'ConfigValue' cannot be found on this object" [#5199](https://github.com/sqlcollaborative/dbatools/issues/5199)
* DLL error when importing [#5195](https://github.com/sqlcollaborative/dbatools/issues/5195)
* `Add-DbaAgListener` parameter for Listener Name [#5000](https://github.com/sqlcollaborative/dbatools/issues/5000)
* `Copy-DbaSqlServerAgent` fails when copying across a job that's dependent on a new proxy account or operator [#2166](https://github.com/sqlcollaborative/dbatools/issues/2166)
* `New-DbaDbUser` not properly referencing the `$Login` variable
* `Export-DbaLinkedServer` confuses when linked has multiple mappings [#5243](https://github.com/sqlcollaborative/dbatools/issues/5243)

### Added
* Prerelease installation support for `Install-DbaSqlWatch`
* Build references for the latest SQL Server Cumulative Updates
* New function `Copy-DbaStartupProcedure` [#555](https://github.com/sqlcollaborative/dbatools/issues/555)

## [0.9.793] - 2019-03-20
* `Restore-DbaDbCertificate` - fails when importing all certs from a folder [#5256](https://github.com/sqlcollaborative/dbatools/issues/5256)
### Changed
* Improved connection strings in `Connect-DbaInstance`

## [0.9.792] - 2019-03-20
### Fixed
* `Test-DbaLastBackup` doesn't execute if backup file is corrupted [#4957](https://github.com/sqlcollaborative/dbatools/issues/4957)
* `Restore-DbaDbCertificate` from a file fails on SQL Server 2012 [#5082](https://github.com/sqlcollaborative/dbatools/issues/5082)
* Databases with same name on multiple instances do not render properly in `ConvertTo-DbaTimeline` [#3916](https://github.com/sqlcollaborative/dbatools/issues/3916)
* Correct service name detection in `Remove-DbaDatabaseSafely` [#5210](https://github.com/sqlcollaborative/dbatools/issues/5210)
* While doing `Start-DbaMigration`, `-SetSourceRedOnly` fails if there are even inactive sessions on database [#5177](https://github.com/sqlcollaborative/dbatools/issues/5177)
### Changed
* Tweaks to `ConvertTo-DbaTimeline` output

## [0.9.791] - 2019-03-18
### Fixed
* `Read-DbaBackupHeader` - SQL 2005 backup fails with column "CompressedBackupSize" does not belong to table [#4945](https://github.com/sqlcollaborative/dbatools/issues/4945)
### Added
* New function `Install-DbaInstance` to script as much of the installation of a new SQL Server instance as possible
* `Copy-DbaAgentJob` now supports piped-in Job objects [#5240](https://github.com/sqlcollaborative/dbatools/issues/5240)

## [0.9.790] - 2019-03-18
### Added
* New function `Export-DbaDbDataTable`

## [0.9.788] - 2019-03-17
### Fixed
* `SqlCredential` parameter not working with `Get-DbaCmsRegServer` [#5025](https://github.com/sqlcollaborative/dbatools/issues/5025)
* Include the `SqlInstance` in the "failure to connect" error message (impacts _many_ functions) [#5091](https://github.com/sqlcollaborative/dbatools/issues/5091)
* `Get-DbaPermission` fails on contained databases [#5093](https://github.com/sqlcollaborative/dbatools/issues/5093)
* Resolved issue creating login from Windows with square brackets in the name in `New-DbaLogin` [#5138](https://github.com/sqlcollaborative/dbatools/issues/5138)
* Fix column mappings in `Write-DbaDataTable` [#5124](https://github.com/sqlcollaborative/dbatools/issues/5124)
* `Get-DbaUserPermission` misses database role assignments [#4887](https://github.com/sqlcollaborative/dbatools/issues/4887)
* `Copy-DbaDbTableData` causes failure on max pool size [#5080](https://github.com/sqlcollaborative/dbatools/issues/5080)
* `-Force` handling in `New-DbaDbUser` [#4962](https://github.com/sqlcollaborative/dbatools/issues/4962)
* Multiple computers not being processed in `Resolve-DbaNetworkName`
### Changed
* Renamed `Write-DbaDataTable` to `Write-DbaDbDataTable`
### Added
* Ability to bypass server name resolution in `Resolve-DbaNetworkName` [#5101](https://github.com/sqlcollaborative/dbatools/issues/5101)

## [0.9.787] - 2019-03-17
## Fixed
* TEPP is no longer broken [#5171](https://github.com/sqlcollaborative/dbatools/issues/5171)
* Resolved issues in `Get-DbaCmObject` [#4096](https://github.com/sqlcollaborative/dbatools/issues/4096)
* `Stop-Function` not recognized in `Set-DbatoolsConfig` [#5065](https://github.com/sqlcollaborative/dbatools/issues/5065)

## [0.9.785] - 2019-03-16
### Fixed
* TLS handling for AWS instances in `Get-DbaComputerSystem`
* Improved connection support for Azure
* `Export-DbaLogin` produces an empty file [#4604](https://github.com/sqlcollaborative/dbatools/issues/4604)

## [0.9.784] - 2019-03-11
### Fixed
* `Copy-DbaPolicyManagement` doesn't copy policy categories [#1040](https://github.com/sqlcollaborative/dbatools/issues/1040)
* `Copy-DbaPolicyManagement` copies conditions but not policies [#1049](https://github.com/sqlcollaborative/dbatools/issues/1049)
### Added
* New function `New-DbaDbMailAccount`

## [0.9.783] - 2019-03-11
### Fixed
* Azure support in `Invoke-DbaDbDataMasking` [#5122](https://github.com/sqlcollaborative/dbatools/issues/5122)
### Changed
* Improved speed of `Get-DbaLogin` for instances with many logins
### Added
* Alias for database name in `New-DbaDatabase`
* More Azure support

## [0.9.782] - 2019-03-10
### Added
* More Azure support

## [0.9.781] - 2019-03-08
### Fixed
* `Get-DbaAgentJobHistory` adds an hour to the `enddate` and duration [#4345](https://github.com/sqlcollaborative/dbatools/issues/4345)
* `Find-DbaLoginInGroup` returns incorrect domain [#3608](https://github.com/sqlcollaborative/dbatools/issues/3608)
* `Get-DbaLogin -WindowsLogins` doesn't include groups [#5165](https://github.com/sqlcollaborative/dbatools/issues/5165)
### Added
* More Azure support

## [0.9.780] - 2019-03-06
### Fixed
* `Install-DbaMaintenanceSolution` does not run CommandExecute if the Solution is not "All"
### Added
* Azure support for `Connect-DbaInstance`

## [0.9.779] - 2019-03-05
### Added
* Registered server support for PowerShell Core

## [0.9.778] - 2019-03-05
### Fixed
* `GetDbaDbFile` incorrectly accounts for pages when calculating `NextGrowthEventSize` [#5147](https://github.com/sqlcollaborative/dbatools/issues/5147)

## [0.9.777] - 2019-03-03
### Fixed
* `Get-DbaServerRoleMember` now correctly calls `Get-DbaLogin`
* `Get-DbaUserPermission` does not drop STIG schema[#5083](https://github.com/sqlcollaborative/dbatools/issues/5083)
* `Backup-DbaDbCertificate` doesn't properly filter on parameter `-Certificate` [#5106](https://github.com/sqlcollaborative/dbatools/issues/5106)
* `Copy-DbaAgentAlert` now verifies that the operator exists on the destination [#4920](https://github.com/sqlcollaborative/dbatools/issues/4920)

## [0.9.775] - 2019-02-26
### Fixed
* Comparison error in `Test-DbaLastBackup` [#5125](https://github.com/sqlcollaborative/dbatools/issues/5125)

## [0.9.774] - 2019-02-26
### Fixed
* Various issues with dynamic data masking [#4910](https://github.com/sqlcollaborative/dbatools/issues/4910), [#4970](https://github.com/sqlcollaborative/dbatools/issues/4970)
* `Sync-DbaAvailabilityGroup` now passes login values to `Copy-DbaLogin` [#5119](https://github.com/sqlcollaborative/dbatools/issues/5119)

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
