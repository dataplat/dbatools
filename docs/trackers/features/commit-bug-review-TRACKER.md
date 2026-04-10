# Commit Bug Review Tracker

Review each commit from `297844e964bfe5197d914e7b794bea8cffeeb066` to HEAD for bugs.
Find real bugs (logic errors, null refs, incorrect behavior) and fix them. Skip version bumps, CI fixes, and doc-only changes.

| Hash | Subject | Status | Notes |
|------|---------|--------|-------|
| 899ea759c | Copy-DbaDbMail: Enhance handling of dedicated admin connections (#10155) | DONE | Fixed forced Get-DecryptedObject -EnableException regression. |
| add550fd2 | Copy-DbaLinkedServer: Enhance handling of dedicated admin connections (#10156) | DONE | Fixed forced Get-DecryptedObject -EnableException regression. |
| f43a61348 | Added SQL Server 2025 CU2 to dbatools-buildref-index.json (#10168) | DONE | Missed LastUpdated metadata; corrected by follow-up commit 54e65cf5c. |
| 54e65cf5c | Updated LastUpdated of dbatools-buildref-index.json followup to SQL Server 2025 CU2 (#10169) | DONE | Reviewed metadata-only LastUpdated fix; no bugs found. |
| 4ef488757 | Get-DbaDbTable: Optimize usage of ClearAndInitialize (#10157) | DONE | Fixed config bypass so ClearAndInitialize stays opt-in; added regression test. |
| f8e673145 | Export-DbaCredential: Enhance handling of dedicated admin connections (#10158) | DONE | Fixed forced Get-DecryptedObject -EnableException regression; added unit regression test. |
| ed1c8b0bb | Export-DbaLinkedServer: Enhance handling of dedicated admin connections (#10159) | DONE | Fixed forced Get-DecryptedObject -EnableException regression; added unit regression test. |
| 9e15aa3e3 | Invoke-DbaDbDecryptObject: Enhance handling of dedicated admin connections (#10160) | DONE | Fixed DAC detection so reused DAC connections are not disconnected; added regression tests. |
| a06ff44dc | [Start|Stop]-DbaDbEncryption: Fix usage of Disconnect-DbaInstance (#10161) | DONE | Fixed parallel cleanup to disconnect thread connections during WhatIf; added unit regressions. |
| d7d327f25 | Sync-DbaAvailabilityGroup: Enhance handling of dedicated admin connections (#10163) | DONE | Stopped forcing DAC at top level so password-aware Copy-Dba* commands manage it; added unit regression tests. |
| be1c99333 | Get-DbaNetworkConfiguration: Fix bug and really add SuitableCertificate property to output (#10165) | DONE | Fixed new test cleanup to remove the certificate from the target SQL host instead of defaulting to localhost. |
| 72ba70110 | New-DbaComputerCertificate: Update security defaults to industry standards (#10167) | DONE | Fixed NonExportable regression so remote installs keep the source cert exportable; added unit regression test. |
| ffb91a13e | Correct help text to correctly reflect Duration units (#10171) | DONE | Reviewed help-text-only change; no bugs found. |
| dd58a4edb | Export-DbaInstance: Enhance handling of dedicated admin connections (#10173) | DONE | Fixed leaked DAC cleanup on export failure paths; added unit regression test. |
| 276b0f6d3 | Add-DbaComputerCertificate - handle multiple flags for NonExportable keys (#10176) | DONE | Fixed combined UserProtected/NonExportable detection so remote imports are skipped; added unit regression test. |
| 1a510a12d | Part 2 of refactoring of Get-DecryptedObject (#10174) | DONE | Restored Stop-Function handling for password query failures; added unit regression test. |
| b82f01eeb | Install-DbaMaintenanceSolution: make off switches work and increase test coverage (#10172) | DONE | Default-false switches forced Compress/Verify/CheckSum off when omitted; corrected by follow-up commit 1f43cbbf0. |
| b0403f5f5 | Start-DbaMigration: Enhance handling of dedicated admin connections (#10162) | DONE | Guarded null DAC/source connections and added unit regression tests. |
| 920fe547b | v2.7.25 | DONE | version bump - skip |
| 58f64c580 | speedup dependency detection for integration tests (#10179) | DONE | Fixed debug helper name parsing, corrected dependency return bookkeeping, removed backtick recursion, and added a regression test. |
| cb7a5d77a | Comment out 2008R2SP2Express AppVeyor jobs | DONE | Reviewed CI-only AppVeyor matrix change; no bugs found. |
| 9799c1877 | Minor test fixes for Connect-DbaInstance (#10175) | DONE | Reviewed test-only cleanup-output suppression change; no bugs found. |
| 1616a6d04 | Add command Test-DbaNetworkCertificate (#10178) | DONE | Fixed ConfiguredCertificateValid so future or missing NotBefore values do not report false positives; added unit regression tests. |
| dbe2f29ca | Get-DbaDbTable: Fix for Azure SQL Database (#10182) | DONE | Fixed Azure default view to skip unsupported IndexSpaceUsed/DataSpaceUsed properties; added unit regression test. |
| eb40ff802 | Test-DbaLsnChain: Fix bug in case log backup is taken during full backup (#10185) | DONE | Introduced deserialized BigInt comparison regression; already corrected by follow-up commit 91972b420 (#10201). |
| 71d1310b4 | Backup-DbaDatabase: Respect explicit FileCount when using StorageBaseUrl (S3/Azure) (#10186) | DONE | Fixed multi-URL StorageBaseUrl striping so explicit FileCount only applies to single URLs; added OutputScriptOnly regression coverage. |
| 8f7039699 | Copy-DbaDatabase: Fix renaming for database names with special characters (#10187) | PENDING | |
| e798ca45e | Start-DbaDbEncryption: Add missing parameter and fix documentation (#10191) | PENDING | |
| 218a98a4a | Import-DbaCsv - Fix RFC 4180 multiline quoted field handling (#10190) | PENDING | |
| 861b0dbce | Import-DbaCsv: Add -NoColumnOptimize switch (#10195) | PENDING | |
| 91972b420 | Test-DbaLsnChain: Fix bug when reading history from file (#10201) | PENDING | |
| 0332cfbae | Get-DbaAgentJob and Sync-DbaAvailabilityGroup: Move filter for MSX jobs (#10198) | PENDING | |
| a0833cc2b | Test-DbaBackupInformation: Add member IsVerified to output if not already present (#10200) | PENDING | |
| 14a287e37 | Connect-DbaInstance: Use localhost for dedicated admin connections (#10199) | PENDING | |
| 7777c1401 | Export-DbaLogin: Add -IncludeRolePermissions switch (#10196) | PENDING | |
| fd7402b94 | Get-DbaUserPermission: Fix incorrect schema name shown as 'STIG' (#10210) | PENDING | |
| da0941593 | Export-DbaInstance: Propagate -EnableException to sub-commands and wrap exports in try-catch (#10211) | PENDING | |
| 85e129c4d | Get-DbaReportingService: Use Credential in every call to Get-DbaCmObject (#10207) | PENDING | |
| f3e40229f | New-DbaLogin: add ExternalGroup support and SQL Server 2022 Entra login handling (#10225) | PENDING | |
| d5d9fd3e2 | Get-DbaStartupParameter: Fix multiple issues (#10208) | PENDING | |
| 2bc80a623 | Test-DbaKerberos: Remove CNAME test (#10209) | PENDING | |
| 95e3aa220 | Update-DbaInstance: Fall back to computer name if Resolve-DbaNetworkName fails (#10212) | PENDING | |
| 480e72a46 | New-DbaDbMailProfile - Fix to allow multiple accounts per profile (#10214) | PENDING | |
| b94e33eaa | Connect-DbaInstance: Auto-retry with Initial Catalog=master for mirrored SQL Server instances (#10215) | PENDING | |
| dc581344d | Export-DbaScript: Handle Distributed Availability Groups gracefully (#10216) | PENDING | |
| 8dacfa20a | Get-DbaReplSubscription: Also check distribution DB for pull subscriptions (#10218) | PENDING | |
| eb0aa1d3d | Invoke-DbaDbLogShipping: Add -IgnoreFileChecks parameter (#10219) | PENDING | |
| f2fb47857 | Copy-DbaPolicyManagement: Add ObjectSets migration (#10220) | PENDING | |
| 902f23b98 | Get-DbaDb[StoredProcedure|Table|Udf|View]: Wrap all ClearAndInitialize in try-catch-block (#10226) | PENDING | |
| 23b429bfc | Backup-DbaDatabase: Prevent duplicate dbname when using CreateFolder with ReplaceInName (#10224) | PENDING | |
| e79bef926 | Invoke-DbaDbDataMasking: Fix MaskingID column and index left behind after masking (#10223) | PENDING | |
| 7240105e0 | Invoke-DbaDbDataMasking: Fix Deterministic masking not applied with multiple columns (#10222) | PENDING | |
| 156fc62e1 | Read-DbaXEFile: Fix database_name and other action columns being empty (#10221) | PENDING | |
| d5b122bf5 | March 2026 CVEs (#10230) | PENDING | |
| 2472ea8fd | Remove Invoke-SmoCheck - no longer needed (#10229) | PENDING | |
| 5e0b70d66 | Set-DbaPrivilege: Use per-service SID (NT SERVICE\ServiceName) for IFI, LPIM, SecAudit (#10228) | PENDING | |
| aa4e253cb | v2.7.26 | DONE | version bump - skip |
| 9c81f3d3d | Latest CUs for 2022 and 2025 (#10231) | PENDING | |
| 3e26310f2 | Add Test-DbaInstantFileInitialization command (#10236) | PENDING | |
| a26e6195b | Add-DbaAgDatabase, New-DbaAvailabilityGroup - auto-copy TDE certificate to replicas (#10237) | PENDING | |
| 8099963d1 | Get-DbaRegServer - Fix IncludeSelf to return pipeline-compatible object (#10238) | PENDING | |
| 6084ecbe5 | Get-DbaLastBackup - Add -ExcludeReplica switch for AlwaysOn preferred backup replica filtering (#10240) | PENDING | |
| fe26c8764 | Export-DbaInstance - Wire up IncludeDbMasterKey to export certs and master keys (#10251) | PENDING | |
| 0ee03fc32 | New-DbaAgentJobStep - Fix OnFailAction ValidateSet order to match actual default (#10244) | PENDING | |
| 63c906f9d | Set-DbaDbCompression - Add SortInTempDB parameter and fix views T-SQL bug (#10248) | PENDING | |
| 4d1a9d80c | v2.7.27 | DONE | version bump - skip |
| 232395207 | Set-DbaPrivilege, Get-DbaPrivilege - Add CreateGlobalObjects privilege support (#10235) | PENDING | |
| 099624061 | Get-DbaDbRestoreHistory - Add BackupStartDate, StopAt, and LastRestorePoint columns (#10249) | PENDING | |
| 4f1e56ce4 | New-DbaDbMailAccount, Set-DbaDbMailAccount - Add Port, SSL, and authentication parameters (#10257) | PENDING | |
| 8218d327e | Restore-DbaDatabase, Invoke-DbaAdvancedRestore - Add ErrorBrokerConversations parameter (#10253) | PENDING | |
| 9a4e4bacb | Connect-DbaInstance - Set NonPooledConnection on ServerConnection (#10260) | PENDING | |
| a0ab78a66 | Get-DbaCmObject - Apply CimOperationTimeout to all CIM connections (#10252) | PENDING | |
| fbdb47053 | Import-DbaXESessionTemplate - Add event_file target when TargetFilePath specified (#10250) | PENDING | |
| 3d6fa113f | Connect-DbaInstance - Trust server certificate for localhost DAC connections (#10263) | PENDING | |
| 0c0629d25 | Restore-DbaDatabase - Add examples for filtering partial backup files (#10242) | PENDING | |
| bb56c43d3 | Read-DbaXEFile, Get-DbaXESessionTargetFile - Document Windows-only admin share requirement (#10243) | PENDING | |
| 152fec170 | Test-DbaLastBackup - Add -Path parameter to test backups from folder paths (#10241) | PENDING | |
| 5590bc30d | New-DbaComputerCertificate - Add DocumentEncryptionCert switch for Always Encrypted (#10264) | PENDING | |
| f73e4413c | Get-DbaAgDatabase - Add -ExcludeDatabase parameter (#10269) | PENDING | |
| 118aed54e | New-DbaDbTable - Handle bracket-quoted names and two-part names (#10279) | PENDING | |
| 27f3fef01 | Save-DbaKbUpdate - Add UseWebRequest switch and BitsTransfer fallback (#10278) | PENDING | |
| 7c7b8ed9c | Get-DbaWaitStatistic - Add ExcludeWaitType and IncludeWaitType parameters (#10276) | PENDING | |
| 562e3ac31 | Expand-DbaDbLogFile - Add -TargetVlfCount parameter (#10272) | PENDING | |
| 3bda32716 | Test-DbaLastBackup - Add DbccOutput property with detailed DBCC messages (#10239) | PENDING | |
| d6552592e | Update-DbaInstance - Add early validation for empty -Path parameter (#10283) | PENDING | |
| c82ae190c | Get-DbaAgRingBuffer - Add command for HADR ring buffer diagnostics (#10282) | PENDING | |
| 552b77af4 | Invoke-DbaDbDataMasking - Fix StaticValue empty string fallback and FilterQuery in Actions (#10281) | PENDING | |
| 99a4a9067 | Update-ServiceStatus - Fix WinRM error on machines without WinRM configured (#10274) | PENDING | |
| 1f70b62bd | Add Remove-DbaAgentJobSchedule cmdlet (#10273) | PENDING | |
| 50c0bfdaf | Connect-DbaInstance - Add -AuthenticationType parameter for Entra ID support (#10271) | PENDING | |
| 27e4da9d1 | Get-DbaDbOrphanUser - Skip SQL login orphan check for contained databases (#10270) | PENDING | |
| 21a522047 | Test-DbaAgPolicyState - Add new command for Always On policy state checks (#10246) | PENDING | |
| 1f43cbbf0 | Install-DbaMaintenanceSolution: change Compress/Verify/CheckSum to ValidateSet string params (#10247) | PENDING | |
| 444659b0a | Get-DbaDbMailAccount, Get-DbaDbMailProfile - Add Account-Profile link details (#10280) | PENDING | |
| 57fa89a0e | Invoke-DbaDbShrink - Add error message output for failed shrink operations (#10258) | PENDING | |
| df60d986f | Export-DbaUser - Add schema ownership to exported scripts (#10275) | PENDING | |
| 7b349b546 | Test-DbaPath - Handle xp_fileexist execution failures gracefully (#10288) | PENDING | |
| 89c06e287 | Invoke-DbaCycleErrorLog - Fix example command names (#10290) | PENDING | |
| 899cdc30c | Update-SqlPermission - Remove unnecessary SqlConnectionObject.Close() calls (#10291) | PENDING | |
| 97d03bee3 | Restore-DbaDatabase - Add -StopAtLsn parameter for LSN-based restore (#10245) | PENDING | |
| 1fdfddee6 | New-DbaFirewallRule - Fix binary path extraction and remove dead code (#10294) | PENDING | |
| aaa8f9eaa | Add ReleaseDate for SQL Server releases to buildref-index / Get-DbaBuild / Test-DbaBuild / Add -MaxTimeBehind (#10277) | PENDING | |
| c16f7f349 | Export-DbaCredential - Add IF NOT EXISTS guard to exported SQL scripts (#10295) | PENDING | |
| e83ff4854 | Compare-DbaDbSchema - Add new command for schema comparison via sqlpackage (#10299) | PENDING | |
| 67ce694ee | Get-DbaNetworkEncryption - Add command to retrieve TLS certificate from SQL Server network (#10293) | PENDING | |
| ce6d7c159 | Add manual instance autocomplete list (Add/Get/Remove-DbaInstanceList) (#10300) | PENDING | |
| 0d4acaa0a | Invoke-DbaDbShrink - Add WAIT_AT_LOW_PRIORITY support (#10307) | PENDING | |
| 092a092bb | Copy-DbaLogin - Add -ExcludeDatabaseMapping to sync only server permissions (#10305) | PENDING | |
| 1ab8d1fba | Get-DbaHelpIndex - Fix SQL injection and remove SQL 2005 code path (#10302) | PENDING | |
| fb94490d9 | Install-DbaMaintenanceSolution - Fix AutoScheduleJobs schedule bugs (#10303) | PENDING | |
| 45e46e6ae | Copy-DbaAgentJob - Add AD group membership check for job owner login validation (#10297) | PENDING | |
| daa4e306e | Invoke-DbaBalanceDataFiles - Add -TargetFileGroup parameter (#10296) | PENDING | |
| 02ad1f092 | ConvertTo-DbaTimeline - Add support for Find-DbaDbGrowthEvent input (#10304) | PENDING | |
| 8987045a9 | Refactor Set-DbaNetworkCertificate (#10232) | PENDING | |
| 392fc9dea | Set-DbaDbCompression, Invoke-DbaBalanceDataFiles, Invoke-DbaDbPiiScan - Normalize table names via Get-ObjectNameParts (#10312) | PENDING | |
| b2f217f47 | Invoke-TlsWebRequest - Auto-detect system proxy (#10310) | PENDING | |
| 1662d73a6 | New-DbaDatabase - Support Azure Blob Storage paths for data and log files (#10315) | PENDING | |
| 241a118ce | Test-DbaDbCompression, Get-DbaDbPageInfo - Normalize table names via Get-ObjectNameParts (#10313) | PENDING | |
| 14a47a26c | Export-DbaCsv, Export-DbaDacPackage - Normalize table/schema names via Get-ObjectNameParts (#10314) | PENDING | |
| fe639f6e6 | Remove-DbaDbTableData - Normalize table name via Get-ObjectNameParts (#10316) | PENDING | |
| 070d2ee7f | Fix AppVeyor dbatools.library cache miss by installing to AllUsers scope (#10335) | PENDING | |
| e3f6cc121 | Fix test for Invoke-DbaAdvancedUpdate (#10334) | PENDING | |
| 6aafd24ed | Fix test for Test-DbaSpn by suppressing the warning on AppVeyor (#10331) | PENDING | |
| 7ad9acf9f | Refactor test for Stop-Function (#10332) | PENDING | |
| 13807a2b3 | Test-DbaBuild: Fix bug introduced in last change (#10328) | PENDING | |
| 4382a8118 | Test-DbaLinkedServerConnection - Fix test failure when Named Pipes is disabled (#10326) | PENDING | |
| b09063aa0 | Get-DbaWaitStatistic - Fix bug from recent refactoring (#10323) | PENDING | |
| eddfeeeca | Find-DbaInstance - Fix TcpConnected false for default instances (#10327) | PENDING | |
| 5f483d42c | Get-DbaPermission - Fix Azure SQL DB compatibility (#10320) | PENDING | |
| a38bc6b35 | Get-DbaDbIdentity, Set-DbaDbIdentity, Invoke-DbaDbDbccUpdateUsage - Normalize table names (#10318) | PENDING | |
| 9899bd274 | Copy-DbaDbTableData - Add -ScriptingOptionsObject parameter (#10317) | PENDING | |
| 0c486b964 | Backup-DbaDbCertificate: Don't use decryption password if cert encrypted by master key (#10329) | PENDING | |
| db77a3476 | Find-DbaObject - Add unified command to search database objects by name (#10321) | PENDING | |
| 6416b4e91 | Add Compare-DbaLogin command (#10319) | PENDING | |
| bee08f8e7 | Copy-DbaSsisCatalog - Add standard MigrationObject output, integrate with Start-DbaMigration (#10311) | PENDING | |
| 21e4795ee | Get-DbaService - Add PowerBI Report Server detection (#10298) | PENDING | |
| 828ebc3b3 | Get-DbaBackupInformation - Fix inconsistencies with Get-DbaDbBackupHistory (#10308) | PENDING | |
| 74a2d1ae1 | Import-DbaCsv, Export-DbaCsv - Normalize table/schema names via Get-ObjectNameParts (#10306) | PENDING | |
