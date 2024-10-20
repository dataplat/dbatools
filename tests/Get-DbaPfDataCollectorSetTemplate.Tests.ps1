param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorSetTemplate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorSetTemplate
        }
        $params = @(
            "Path",
            "Pattern",
            "Template",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Verifying command returns all the required results" {
        It "returns not null values for required fields" {
            $results = Get-DbaPfDataCollectorSetTemplate
            foreach ($result in $results) {
                $result.Name | Should -Not -BeNullOrEmpty
                $result.Source | Should -Not -BeNullOrEmpty
                $result.Description | Should -Not -BeNullOrEmpty
            }
        }

        It "returns only one (and the proper) template" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries'
            $results.Name | Should -Be 'Long Running Queries'
        }
    }
}
