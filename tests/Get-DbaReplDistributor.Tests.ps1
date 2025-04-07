$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count -eq 0) | Should Be $true
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("EXEC sp_get_distributor")
    }

    Context "Command actually works" {
        It "Should return distributor information" {
            $results = Get-DbaReplDistributor -SqlInstance $script:instance2
            $results | Should Not Be $null
            $results.IsDistributor | Should BeOfType [bool]
            $results.IsPublisher | Should BeOfType [bool]
            $results.DistributionServer | Should BeOfType [string]
        }
    }
}
