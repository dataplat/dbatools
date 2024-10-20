param($ModuleName = 'dbatools')

Describe "Get-DbaDbExtentDiff" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $server.Query("Create Database [$dbname]")
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbExtentDiff
        }
        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Gets Changed Extents for Multiple Databases" {
        BeforeAll {
            $results = Get-DbaDbExtentDiff -SqlInstance $global:instance2
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have extents for each database" {
            foreach ($row in $results) {
                $row.ExtentsTotal | Should -BeGreaterThan 0
                $row.ExtentsChanged | Should -BeGreaterOrEqual 0
            }
        }
    }

    Context "Gets Changed Extents for Single Database" {
        BeforeAll {
            $results = Get-DbaDbExtentDiff -SqlInstance $global:instance2 -Database $dbname
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have extents for the specified database" {
            $results.ExtentsTotal | Should -BeGreaterThan 0
            $results.ExtentsChanged | Should -BeGreaterOrEqual 0
        }
    }
}
