$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeEach {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate |
        Get-DbaPfDataCollector | Get-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length' | Remove-DbaPfDataCollectorCounter -Confirm:$false
    }
    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
    }
    Context "Verifying command returns all the required results" {
        It "returns the correct values" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Get-DbaPfDataCollector | Add-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'
            $results.DataCollectorSet | Should Be 'Long Running Queries'
            $results.Name | Should Be '\LogicalDisk(*)\Avg. Disk Queue Length'
        }
    }
}