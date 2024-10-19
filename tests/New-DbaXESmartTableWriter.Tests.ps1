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
        It "has all the required parameters" {
            $requiredParameters = @(
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
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
