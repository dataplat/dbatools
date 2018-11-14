$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
               #>
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaAgReplica).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Replica', 'AvailabilityMode', 'InputObject', 'EnableException', 'FailoverMode', 'BackupPriority', 'EndpointUrl', 'ConnectionModeInPrimaryRole', 'ConnectionModeInSecondaryRole', 'ReadonlyRoutingConnectionUrl', 'SeedingMode'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_arepgroup"
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }
    Context "sets ag properties" {
        It "returns modified results" {
            $results = Set-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false -BackupPriority 5000
            $results.AvailabilityGroup | Should -Be $agname
            $results.BackupPriority | Should -Be 5000
        }
        It "returns modified results" {
            $results = Set-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false -BackupPriority 1000
            $results.AvailabilityGroup | Should -Be $agname
            $results.BackupPriority | Should -Be 1000
        }
    }
} #$script:instance2 for appveyor