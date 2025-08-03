$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EventType', 'FileType', 'UseLocalTime', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $random = Get-Random
            $databaseName1 = "dbatoolsci1_$random"
            $db1 = New-DbaDatabase -SqlInstance $server -Name $databaseName1

            $null = $db1.Query("CREATE TABLE justspace (a NCHAR(1000))")
            $null = $db1.Query("INSERT INTO justspace SELECT TOP 5000 'x' FROM sys.all_objects a, sys.all_objects b")
        }
        AfterAll {
            $db1 | Remove-DbaDatabase -Confirm:$false
        }

        It "Should find auto growth events in the default trace" {
            $results = Find-DbaDbGrowthEvent -SqlInstance $server -Database $databaseName1 -EventType Growth
            ($results | Where-Object { $_.EventClass -in (92, 93) }).count | Should -BeGreaterThan 0
            $results.DatabaseName | unique | Should -Be $databaseName1
            $results.DatabaseId | unique | Should -Be $db1.ID
        }

        <# Leaving this commented out since the background process for auto shrink cannot be triggered

        It "Should find auto shrink events in the default trace" {
            $results = Find-DbaDbGrowthEvent -SqlInstance $server -Database $databaseName1 -EventType Shrink
            $results.EventClass | Should -Contain 94 # data file shrink
            $results.EventClass | Should -Contain 95 # log file shrink
            $results.DatabaseName | unique | Should -Be $databaseName1
            $results.DatabaseId | unique | Should -Be $db1.ID
        }
        #>
    }
}
