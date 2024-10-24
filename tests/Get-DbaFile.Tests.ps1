$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'FileType', 'Depth', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Returns some files" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $random = Get-Random
            $db = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $db")
        }
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db | Remove-DbaDatabase -Confirm:$false
        }

        $results = Get-DbaFile -SqlInstance $TestConfig.instance2
        It "Should find the new database file" {
            ($results.Filename -match 'dbatoolsci').Count | Should -BeGreaterThan 0
        }

        $results = Get-DbaFile -SqlInstance $TestConfig.instance2 -Path (Get-DbaDefaultPath -SqlInstance $TestConfig.instance2).Log
        It "Should find the new database log file" {
            ($results.Filename -like '*dbatoolsci*ldf').Count | Should -BeGreaterThan 0
        }

        $masterpath = $server.MasterDBPath
        $results = Get-DbaFile -SqlInstance $TestConfig.instance2 -Path $masterpath
        It "Should find the master database file" {
            ($results.Filename -match 'master.mdf').Count | Should -BeGreaterThan 0
        }
    }
}
