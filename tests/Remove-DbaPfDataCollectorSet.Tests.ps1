$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Remove-DbaPfDataCollectorSet).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'CollectorSet', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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