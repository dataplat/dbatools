param($ModuleName = 'dbatools')

Describe "Remove-DbaPfDataCollectorSet" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        # Import the collector set template before all tests
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
    }

    AfterAll {
        # Clean up after all tests
        $null = Remove-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaPfDataCollectorSet
        }
        It "has all the required parameters" {
            $params = @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "InputObject",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Verifying command returns the proper results" {
        It "removes the data collector set" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
            $results.Name | Should -Be 'Long Running Queries'
            $results.Status | Should -Be 'Removed'
        }

        It "returns a result when getting the collector set" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results.Name | Should -Be 'Long Running Queries'
        }

        It "returns no results after removing the collector set" {
            $null = Remove-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' -Confirm:$false
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results | Should -BeNullOrEmpty
        }
    }
}
