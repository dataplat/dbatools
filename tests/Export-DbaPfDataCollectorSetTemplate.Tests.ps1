$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeEach {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
    }
    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
    }
    Context "Verifying command returns all the required results" {
        It "returns a file system object" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Export-DbaPfDataCollectorSetTemplate
            $results.BaseName | Should Be 'Long Running Queries'
        }
        It "returns a file system object" {
            $results = Export-DbaPfDataCollectorSetTemplate -CollectorSet 'Long Running Queries'
            $results.BaseName | Should Be 'Long Running Queries'
        }
    }
}