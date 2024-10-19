param($ModuleName = 'dbatools')

Describe "Get-DbaDbMirror" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMirror
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 | Where-Object Program -Match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $db1 = "dbatoolsci_mirroring"
            $db2 = "dbatoolsci_mirroring_db2"

            Remove-DbaDbMirror -SqlInstance $global:instance2, $global:instance3 -Database $db1, $db2 -Confirm:$false
            $null = Get-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false

            $null = $server.Query("CREATE DATABASE $db1")
            $null = $server.Query("CREATE DATABASE $db2")
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Database $db1, $db2 | Remove-DbaDbMirror -Confirm:$false
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2, $global:instance3 -Database $db1, $db2 -ErrorAction SilentlyContinue
        }

        It "returns more than one database" -Skip {
            $null = Invoke-DbaDbMirroring -Primary $global:instance2 -Mirror $global:instance3 -Database $db1, $db2 -Confirm:$false -Force -SharedPath C:\temp -WarningAction Continue
            (Get-DbaDbMirror -SqlInstance $global:instance3).Count | Should -BeGreaterThan 1
        }

        It "returns just one database" -Skip {
            (Get-DbaDbMirror -SqlInstance $global:instance3 -Database $db2).Count | Should -Be 1
        }

        It "returns 2x1 database" -Skip {
            (Get-DbaDbMirror -SqlInstance $global:instance2, $global:instance3 -Database $db2).Count | Should -Be 2
        }
    }
}
