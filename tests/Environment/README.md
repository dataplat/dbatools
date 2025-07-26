This directory contains files to test dbatools in a clound vm.

This is not a replacement for the AppVeyor tests but an addition.

Details about the used cloud vm will follow.

These tests are currently excluded:
* Add-DbaAgReplica.Tests.ps1 (Needs an seconds Hadr-instance)
* Invoke-DbaDbMirroring.Tests.ps1 ("the partner server name must be distinct")
* Watch-DbaDbLogin.Tests.ps1 (Command does not work)
* Get-DbaWindowsLog.Tests.ps1 (will be included in next run)

These pester 5 tests currently fail:
* Add-DbaPfDataCollectorCounter.Tests.ps1
* Disable-DbaDbEncryption.Tests.ps1
* Enable-DbaDbEncryption.Tests.ps1

These pester 4 tests currently fail:
* Backup-DbaDatabase.Tests.ps1
* Copy-DbaCredential.Tests.ps1
* Copy-DbaDatabase.Tests.ps1
* Copy-DbaDbAssembly.Tests.ps1
* Find-DbaStoredProcedure.Tests.ps1
* Get-DbaClientProtocol.Tests.ps1
* Get-DbaCredential.Tests.ps1
* Get-DbaDbUserDefinedTableType.Tests.ps1
* Get-DbaPageFileSetting.Tests.ps1
* New-DbaCredential.Tests.ps1
* New-DbaDbMailAccount.Tests.ps1
* New-DbaLogin.Tests.ps1
* New-DbaSsisCatalog.Tests.ps1
* Read-DbaAuditFile.Tests.ps1
* Read-DbaXEFile.Tests.ps1
* Remove-DbaDatabaseSafely.Tests.ps1
* Watch-DbaXESession.Tests.ps1

Issues that I will address in the next days:
* pester5 tests don't use "$PSDefaultParameterValues". So `$PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults` only sets `$TestConfig`, but not `$PSDefaultParameterValues`.
* Some tests use `Get-ChildItem -Path $result.Path | Remove-Item` even if $result is emptpy because the test command failed. Then the script deletes files in the current folder.
* Some tests just don't test because of missing `Should`.
* Every test must not output any warning. So if the test command outputs a warning, we use `-WarningAction SilentlyContinue` to suppress it. If we want the warning we use `-WarningVariable warn` and test `$warn`. In the end there should not be any orange or red in the output. So that a human can check if everything is ok.

Goals for the future:
* All tests should use a share to write output files like backups or scripts.
* That way we can move the instances away from the test engine. Like in production: You don't run dbatools on the server. Every test should work against a remote instance.
* Using two servers in an active directory domain with a failover cluster (without shared storage) to test Availability Groups, Mirroring, database migrations and other related stuff.
* Test different versions of SQL Server. Currently I use 2022.
* All BeforeAll and AfterAll must use -EnableException to make sure that the test setup is correct.
