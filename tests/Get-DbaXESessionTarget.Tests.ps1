$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'Target', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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