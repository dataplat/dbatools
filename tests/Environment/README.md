This directory contains files to test dbatools in a clound vm.

This is not a replacement for the AppVeyor tests but an addition.

Details about the used cloud vm will follow.

These tests are currently excluded:
* Invoke-DbaDbMirroring.Tests.ps1 ("the partner server name must be distinct")
* Watch-DbaDbLogin.Tests.ps1 (Command does not work)
* Get-DbaWindowsLog.Tests.ps1 (Sometimes failes and gets no data, sometimes takes forever)
* Get-DbaPageFileSetting.Tests.ps1 (Classes Win32_PageFile and Win32_PageFileSetting do not return any information)
* New-DbaSsisCatalog.Tests.ps1 (needs an SSIS server)
* Get-DbaClientProtocol.Tests.ps1 (No ComputerManagement Namespace on CLIENT.dom.local)

These pester 5 tests currently fail:
* Copy-DbaEndpoint.Tests.ps1

These pester 4 tests currently fail:
* Backup-DbaDatabase.Tests.ps1
* New-DbaEndpoint.Tests.ps1
* Remove-DbaDatabaseSafely.Tests.ps1
* Remove-DbaEndpoint.Tests.ps1
* Test-DbaBackupEncrypted.Tests.ps1
* Test-DbaEndpoint.Tests.ps1

Issues that I will address in the next days:
* Some tests use `Get-ChildItem -Path $result.Path | Remove-Item` even if $result is emptpy because the test command failed. Then the script deletes files in the current folder.
* Some tests just don't test because of missing `Should`.
* Every test must not output any warning. So if the test command outputs a warning, we use `-WarningAction SilentlyContinue` to suppress it. If we want the warning we use `-WarningVariable WarnVar` and test `$WarnVar`. In the end there should not be any orange or red in the output. So that a human can check if everything is ok.

Goals for the future:
* All tests should use a share to write output files like backups or scripts.
* That way we can move the instances away from the test engine. Like in production: You don't run dbatools on the server. Every test should work against a remote instance.
* Using two servers in an active directory domain with a failover cluster (without shared storage) to test Availability Groups, Mirroring, database migrations and other related stuff.
* Test different versions of SQL Server. Currently I use 2022.
* All BeforeAll and AfterAll must use -EnableException to make sure that the test setup is correct.
