$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'WorkloadGroup', 'ResourcePool', 'ResourcePoolType', 'SkipReconfigure', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $script:instance2 -Enabled
        }
        It "Removes a workload group in default resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $script:instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -eq $wklGroupName
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $script:instance2 -WorkloadGroup $wklGroupName
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -Be $null
            $result.Count | Should -BeGreaterThan $result2.Count
            $result2 | Should -Be $null
        }
        It "Removes a workload group in a user defined resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolType = "Internal"
            $splatNewResourcePool = @{
                SqlInstance  = $script:instance2
                ResourcePool = $resourcePoolName
                Type         = $resourcePoolType
                Force        = $true
            }
            $splatNewWorkloadGroup = @{
                SqlInstance      = $script:instance2
                WorkloadGroup    = $wklGroupName
                ResourcePool     = $resourcePoolName
                ResourcePoolType = $resourcePoolType
                Force            = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -eq $wklGroupName
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $script:instance2 -WorkloadGroup $wklGroupName -ResourcePool $resourcePoolName -ResourcePoolType $resourcePoolType
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -eq $wklGroupName

            $null = Remove-DbaRgResourcePool -SqlInstance $script:instance2 -ResourcePool $resourcePoolName -Type $resourcePoolType

            $newWorkloadGroup | Should -Not -Be $null
            $result.Count | Should -BeGreaterThan $result2.Count
            $result2 | Should -Be $null
        }
        It "Removes multiple workload groups" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $script:instance2
                WorkloadGroup = @($wklGroupName, $wklGroupName2)
                Force         = $true
            }

            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $script:instance2 -WorkloadGroup $wklGroupName, $wklGroupName2
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2

            $newWorkloadGroups | Should -Not -Be $null
            $result.Count | Should -BeGreaterThan $result2.Count
            $result2 | Should -Be $null
        }
        It "Removes a piped workload group" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $script:instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -eq $wklGroupName
            $newWorkloadGroup | Remove-DbaRgWorkloadGroup
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $script:instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -Be $null
            $result.Count | Should -BeGreaterThan $result2.Count
            $result2 | Should -Be $null
        }
    }
}