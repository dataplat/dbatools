param($ModuleName = 'dbatools')

Describe "Find-DbaDbGrowthEvent" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaDbGrowthEvent
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have EventType as a parameter" {
            $CommandUnderTest | Should -HaveParameter EventType -Type System.String
        }
        It "Should have FileType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileType -Type System.String
        }
        It "Should have UseLocalTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter UseLocalTime -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $random = Get-Random
            $databaseName1 = "dbatoolsci1_$random"
            $db1 = New-DbaDatabase -SqlInstance $server -Name $databaseName1

            $sqlGrowthAndShrink = @"
CREATE TABLE Tab1 (ID INTEGER);

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
"@

            $null = $db1.Query($sqlGrowthAndShrink)
        }

        AfterAll {
            $db1 | Remove-DbaDatabase -Confirm:$false
        }

        It "Should find auto growth events in the default trace" {
            $results = Find-DbaDbGrowthEvent -SqlInstance $server -Database $databaseName1 -EventType Growth
            ($results | Where-Object { $_.EventClass -in (92, 93) }).count | Should -BeGreaterThan 0
            $results.DatabaseName | Select-Object -Unique | Should -Be $databaseName1
            $results.DatabaseId | Select-Object -Unique | Should -Be $db1.ID
        }

        <# Leaving this commented out since the background process for auto shrink cannot be triggered

        It "Should find auto shrink events in the default trace" {
            $results = Find-DbaDbGrowthEvent -SqlInstance $server -Database $databaseName1 -EventType Shrink
            $results.EventClass | Should -Contain 94 # data file shrink
            $results.EventClass | Should -Contain 95 # log file shrink
            $results.DatabaseName | Select-Object -Unique | Should -Be $databaseName1
            $results.DatabaseId | Select-Object -Unique | Should -Be $db1.ID
        }
        #>
    }
}
