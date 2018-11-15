$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaXESessionTarget).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'Target', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command output" {

        It "returns only the system_health session" {
            $results = Get-DbaXESessionTarget -SqlInstance $script:instance2 -Target package0.event_file
            foreach ($result in $results) {
                $result.Name -eq 'package0.event_file' | Should Be $true
            }
        }

        It "supports the pipeline" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 -Session system_health | Get-DbaXESessionTarget -Target package0.event_file
            $results.Count -gt 0 | Should Be $true
        }
    }
}