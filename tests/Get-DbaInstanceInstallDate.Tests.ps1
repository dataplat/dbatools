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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "IncludeWindows",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
