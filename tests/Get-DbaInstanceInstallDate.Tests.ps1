param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceInstallDate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceInstallDate
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "IncludeWindows",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Gets SQL Server Install Date" {
        BeforeAll {
            $results = Get-DbaInstanceInstallDate -SqlInstance $global:instance2
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets SQL Server Install Date and Windows Install Date" {
        BeforeAll {
            $results = Get-DbaInstanceInstallDate -SqlInstance $global:instance2 -IncludeWindows
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
