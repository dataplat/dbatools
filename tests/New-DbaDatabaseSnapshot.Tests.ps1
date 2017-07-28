$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Parameters validation" {
		It "Stops if no Database or AllDatabases" {
			{ New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent } | Should Throw "You must specify"
		}
		It "Is nice by default" {
			{ New-DbaDatabaseSnapshot -SqlInstance $script:instance2 *> $null } | Should Not Throw "You must specify"
		}
	}
	
	Context "Operations on not supported databases" {
		It "Doesn't support model, master or tempdb" {
			$result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent -Database model,master,tempdb
			$result | Should Be $null
		}
		
	}
	Context "Operations on databases" {
		BeforeAll {
			$server = Connect-DbaSqlServer -SqlInstance $script:instance2
			$db1 = "dbatools_SnapMe"
			$db2 = "dbatools_SnapMe2"
			$db3 = "dbatools_SnapMe3_Offline"
			$server.Query("CREATE DATABASE $db1")
			$server.Query("CREATE DATABASE $db2")
			$server.Query("CREATE DATABASE $db3")
			$null = Set-DbaDatabaseState -Sqlinstance $script:instance2 -Database $db3 -Offline -Force
		}
		AfterAll {
			$null = Set-DbaDatabaseState -Sqlinstance $script:instance2 -Database $db3 -Online -Force
			Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1,$db2,$db3 -Force
			Remove-DbaDatabase -SqlInstance $script:instance2 -Database $db1,$db2,$db3
		}
		It "Skips over offline databases nicely" {
			$result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent -Database $db3
			$result | Should Be $null
		}
		It "Refuses to accept multiple source databases with a single name target" {
			{ New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent -Database $db1,$db2 -Name "dbatools_Snapped" } | Should Throw
		}
		It "Halts when path is not accessible" {
			{ New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Path B:\Funnydbatoolspath -Silent } | Should Throw
		}
		It "Creates snaps for multiple dbs by default" {
			$result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent -Database $db1,$db2
			$result | Should Not Be $null
			foreach($r in $result) {
				$r.SnapshotOf -in @($db1, $db2) | Should Be $true 
			}
		}
		It "Creates snap with the correct name" {
			$result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent -Database $db1 -Name "dbatools_SnapMe_right"
			$result | Should Not Be $null
			$result.SnapshotOf | Should Be $db1
			$result.Database | Should Be "dbatools_SnapMe_right"
		}
		It "Creates snap with the correct name template" {
			$result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent -Database $db2 -NameSuffix "dbatools_SnapMe_{0}_funny"
			$result | Should Not Be $null
			$result.SnapshotOf | Should Be $db2
			$result.Database | Should Be ("dbatools_SnapMe_{0}_funny" -f $db2)
		}
		It "Has the correct properties" {
			$result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Silent -Database $db2
			($result.PsObject.Properties.Name | Sort-Object) | Should Be 'ComputerName,Database,DatabaseCreated,InstanceName,Notes,PrimaryFilePath,SizeMB,SnapshotDb,SnapshotOf,SqlInstance,Status'.Split(',')
			($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be 'ComputerName,InstanceName,SqlInstance,Database,SnapshotOf,SizeMB,DatabaseCreated,PrimaryFilePath,Status'.Split(',')
		}
	}
}

