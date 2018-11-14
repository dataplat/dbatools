$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
               #>
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Remove-DbaAvailabilityGroup).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'AllAvailabilityGroups', 'InputObject', 'EnableException'
        it "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_removewholegroup"
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false
    }
    Context "removes the newly created ag" {
        It "removes the ag" {
            $results = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
            $results.Status | Should -Be 'Removed'
            $results.AvailabilityGroup | Should -Be $agname
        }
        It "really removed the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname
            $results | Should -BeNullorEmpty
        }
    }
} #$script:instance2 for appveyor