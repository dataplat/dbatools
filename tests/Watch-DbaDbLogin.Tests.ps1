$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'Database', 'Table', 'SqlCredential', 'SqlCms', 'ServersFromFile', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random

        $tableName1 = 'dbatoolsciwatchdblogin1'
        $tableName2 = 'dbatoolsciwatchdblogin2'
        $tableName3 = 'dbatoolsciwatchdblogin3'
        $databaseName = "dbatoolsci_$random"
        $newDb = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $databaseName

        $testFile = 'C:\temp\Servers_$random.txt'
        if (Test-Path $testFile) {
            Remove-Item $testFile -Force
        }

        $TestConfig.instance1, $TestConfig.instance2 | Out-File $testFile

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        $regServer1 = Add-DbaRegServer -SqlInstance $TestConfig.instance1 -ServerName $TestConfig.instance1 -Name "dbatoolsci_instance1_$random"
        $regServer2 = Add-DbaRegServer -SqlInstance $TestConfig.instance1 -ServerName $TestConfig.instance2 -Name "dbatoolsci_instance2_$random"
    }

    AfterAll {
        $null = $newDb | Remove-DbaDatabase -Confirm:$false
        Get-DbaRegServer -SqlInstance $TestConfig.instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
    }
    Context "Command actually works" {

        It "ServersFromFile" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName1 -ServersFromFile $testFile -EnableException
            $result = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName1 -IncludeSystemDBs
            $result.Name | Should Be $tableName1
            $result.Count | Should BeGreaterThan 0
        }

        It "Pipeline of instances" {
            $server1, $server2 | Watch-DbaDbLogin -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName2 -EnableException
            $result = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName2 -IncludeSystemDBs
            $result.Name | Should Be $tableName2
            $result.Count | Should BeGreaterThan 0
        }

        It "ServersFromCMS" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName3 -SqlCms $TestConfig.instance1 -EnableException
            $result = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName3 -IncludeSystemDBs
            $result.Name | Should Be $tableName3
            $result.Count | Should BeGreaterThan 0
        }
    }
}
