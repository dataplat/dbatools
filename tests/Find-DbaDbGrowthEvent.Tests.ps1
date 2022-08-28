$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

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
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $random = Get-Random
            $databaseName1 = "dbatoolsci1_$random"
            $db1 = New-DbaDatabase -SqlInstance $server -Name $databaseName1

            $sqlGrowthAndShrink =
            "CREATE TABLE Tab1 (ID INTEGER);

            INSERT INTO Tab1 (ID)
            SELECT
                1
            FROM
                sys.all_objects a
            CROSS JOIN
                sys.all_objects b;

            TRUNCATE TABLE Tab1;
            DBCC SHRINKFILE ($databaseName1, TRUNCATEONLY);
            DBCC SHRINKFILE ($($databaseName1)_Log, TRUNCATEONLY);
            "

            $null = $db1.Query($sqlGrowthAndShrink)
        }
        AfterAll {
            $db1 | Remove-DbaDatabase -Confirm:$false
        }

        It "Should find auto growth events in the default trace" {
            $results = Find-DbaDbGrowthEvent -SqlInstance $server -Database $databaseName1 -EventType Growth
            $results.EventClass | Should -Contain 92 # data file growth
            $results.EventClass | Should -Contain 93 # log file growth
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