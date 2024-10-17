param($ModuleName = 'dbatools')

Describe "Get-DbaDbExtentDiff" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("Create Database [$dbname]")
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbExtentDiff
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Gets Changed Extents for Multiple Databases" {
        BeforeAll {
            $results = Get-DbaDbExtentDiff -SqlInstance $script:instance2
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
            $results = Get-DbaDbExtentDiff -SqlInstance $script:instance2 -Database $dbname
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
