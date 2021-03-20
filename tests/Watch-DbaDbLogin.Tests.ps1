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
        $SkipLocalTest = $true # Change to $false to run locally. The Watch-DbaDbLogin excludes data generated from the local machine, so it's necessary to either test with a target instance that has connections from other machines or comment out the clause "| Where-Object { $_.Host -ne $instance.ComputerName -and ![string]::IsNullOrEmpty($_.Host) }" that used after the call to $instance.Query($sql).
        $random = Get-Random

        $tableName1 = 'dbatoolsciwatchdblogin1'
        $tableName2 = 'dbatoolsciwatchdblogin2'
        $tableName3 = 'dbatoolsciwatchdblogin3'
        $databaseName = "dbatoolsci_$random"
        $newDb = New-DbaDatabase -SqlInstance $script:instance1 -Name $databaseName

        $testFile = 'C:\temp\Servers_$random.txt'
        if (Test-Path $testFile) {
            Remove-Item $testFile -Force
        }

        $script:instance1, $script:instance2 | Out-File $testFile

        $instance1 = Connect-DbaInstance -SqlInstance $script:instance1
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2

        $regServer1 = Add-DbaRegServer -SqlInstance $script:instance1 -ServerName $script:instance1 -Name "dbatoolsci_instance1_$random"
        $regServer2 = Add-DbaRegServer -SqlInstance $script:instance1 -ServerName $script:instance2 -Name "dbatoolsci_instance2_$random"
    }

    AfterAll {
        $null = $newDb | Remove-DbaDatabase -Confirm:$false
        Get-DbaRegServer -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
    }
    Context "Command actually works" {

        It -Skip:$SkipLocalTest "ServersFromFile" {
            Watch-DbaDbLogin -SqlInstance $script:instance1 -Database $databaseName -Table $tableName1 -ServersFromFile $testFile -EnableException
            $result = Get-DbaDbTable -SqlInstance $script:instance1 -Database $databaseName -Table $tableName1 -IncludeSystemDBs
            $result.Name | Should Be $tableName1
            $result.Count | Should BeGreaterThan 0
        }

        It -Skip:$SkipLocalTest "Pipeline of instances" {
            $instance1, $instance2 | Watch-DbaDbLogin -SqlInstance $script:instance1 -Database $databaseName -Table $tableName2 -EnableException
            $result = Get-DbaDbTable -SqlInstance $script:instance1 -Database $databaseName -Table $tableName2 -IncludeSystemDBs
            $result.Name | Should Be $tableName2
            $result.Count | Should BeGreaterThan 0
        }

        It -Skip:$SkipLocalTest "ServersFromCMS" {
            Watch-DbaDbLogin -SqlInstance $script:instance1 -Database $databaseName -Table $tableName3 -SqlCms $script:instance1 -EnableException
            $result = Get-DbaDbTable -SqlInstance $script:instance1 -Database $databaseName -Table $tableName3 -IncludeSystemDBs
            $result.Name | Should Be $tableName3
            $result.Count | Should BeGreaterThan 0
        }
    }
}