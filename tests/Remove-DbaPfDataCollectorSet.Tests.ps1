$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'CollectorSet', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeEach {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
    }
    Context "Verifying command return the proper results" {

        It "removes the data collector set" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
            $results.Name | Should Be 'Long Running Queries'
            $results.Status | Should Be 'Removed'
        }

        It "returns a result" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results.Name | Should Be 'Long Running Queries'
        }

        It "returns no results" {
            $null = Remove-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' -Confirm:$false
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results.Name | Should Be $null
        }
    }
}