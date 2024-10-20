param($ModuleName = 'dbatools')

Describe "Get-DbaDump" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDump
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Skip:($null -ne $env:appveyor) {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $server.Query("DBCC STACKDUMP")
            $server.Query("DBCC STACKDUMP")
        }

        It "finds at least one dump" {
            $results = Get-DbaDump -SqlInstance $global:instance1
            $results.Count | Should -BeGreaterOrEqual 1
        }
    }
}
