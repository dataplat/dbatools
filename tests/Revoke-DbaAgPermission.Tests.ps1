$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'AvailabilityGroup', 'Type', 'Permission', 'InputObject', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Invoke-DbaQuery -SqlInstance $script:instance3 -InputFile $script:appveyorlabrepo\sql2008-scripts\logins.sql -ErrorAction SilentlyContinue
        $agname = "dbatoolsci_ag_revoke"
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }
    Context "revokes big perms" {
        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $script:instance3 -Login tester | Revoke-DbaAgPermission -Type EndPoint
            $results.Status | Should -Be 'Success'
        }
    }
} #$script:instance2 for appveyor