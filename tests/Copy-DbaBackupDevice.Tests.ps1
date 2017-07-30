$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Setup" {
		BeforeAll {
			$devicename = "dbatoolsci-backupdevice"
			$backupdir = (Get-DbaDefaultPath -SqlInstance $script:instance1).Backup
			$backupfilename = "$backupdir\$devicename.bak"
			$server = Connect-DbaSqlServer -SqlInstance $script:instance1
			$server.Query("EXEC master.dbo.sp_addumpdevice  @devtype = N'disk', @logicalname = N'$devicename',@physicalname = N'$backupfilename'")
			$server.Query("BACKUP DATABASE master TO DISK = '$backupfilename'")
		}
		AfterAll {
			$server.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$devicename'")
			$server1 = Connect-DbaSqlServer -SqlInstance $script:instance2
			try {
				$server1.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$devicename'")
			}
			catch {
				# dont care	
			}
		}
		
		$results = Copy-DbaBackupDevice -Source $script:instance1 -Destination $script:instance2 -WarningVariable warn -WarningAction SilentlyContinue
		if ($warn) {
			It "warns if it has a problem moving (issue for local to local)" {
				$warn -match "backup device to destination" | Should Be $true
			}
		}
		else {
			It "should report success" {
				$results.Status | Should Be "Successful"
			}
		}
		
		if ($results.Status -eq "Successful") {
			$results = Copy-DbaBackupDevice -Source $script:instance1 -Destination $script:instance2 -WarningVariable warn -WarningAction SilentlyContinue
			if ($warn) {
				It "does not overwrite existing" {
					$warn -match "exists at destination" | Should Be $true
				}
			}
		}
	}
}
