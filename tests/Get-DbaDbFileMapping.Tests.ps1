param($ModuleName = 'dbatools')

Describe "Get-DbaDbFileMapping" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbFileMapping
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" -Tag "IntegrationTests" {
        BeforeAll {
            $global:instance1 = $global:instance1 # Assuming this is defined in constants.ps1
        }

        It "Should return file information for multiple databases" {
            $results = Get-DbaDbFileMapping -SqlInstance $global:instance1
            $results.Database | Should -Contain "tempdb"
            $results.Database | Should -Contain "master"
        }

        It "Should return file information for a single database" {
            $results = Get-DbaDbFileMapping -SqlInstance $global:instance1 -Database tempdb
            $results.Database | Should -Contain "tempdb"
            $results.Database | Should -Not -Contain "master"
        }
    }
}
