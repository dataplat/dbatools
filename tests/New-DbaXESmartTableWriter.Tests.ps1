param($ModuleName = 'dbatools')

Describe "New-DbaXESmartTableWriter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartTableWriter
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Table",
            "AutoCreateTargetTable",
            "UploadIntervalSeconds",
            "Event",
            "OutputColumn",
            "Filter",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Creates a smart object" {
        BeforeAll {
            $results = New-DbaXESmartReplay -SqlInstance $global:instance2 -Database planning
        }
        It "returns the object with all of the correct properties" {
            $results.ServerName | Should -Be $global:instance2
            $results.DatabaseName | Should -Be 'planning'
            $results.Password | Should -BeNullOrEmpty
            $results.DelaySeconds | Should -Be 0
        }
    }
}
