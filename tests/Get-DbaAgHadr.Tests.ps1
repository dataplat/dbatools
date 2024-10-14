$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

# $script:instance3 is used for Availability Group tests and needs Hadr service setting enabled

Describe "$CommandName Integration Test" -Tag "IntegrationTests" {
    $results = Get-DbaAgHadr -SqlInstance $script:instance3
    Context "Validate output" {
        It "returns the correct properties" {
            $results.IsHadrEnabled | Should -Be $true
        }
    }
} #$script:instance2 for appveyor