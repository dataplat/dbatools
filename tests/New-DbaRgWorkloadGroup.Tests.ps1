$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'WorkloadGroup', 'ResourcePool', 'ResourcePoolType', 'Importance', 'RequestMaximumMemoryGrantPercentage', 'RequestMaximumCpuTimeInSeconds', 'RequestMemoryGrantTimeoutInSeconds', 'MaximumDegreeOfParallelism', 'GroupMaximumRequests', 'SkipReconfigure', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $TestConfig.instance2 -Enabled
        }
        It "Creates a workload group in default resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -Be $null
            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $wklGroupName
        }
        It "Does nothing without -Force if workload group exists" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                WorkloadGroup = $wklGroupName
                WarningAction = "SilentlyContinue"
            }
            $result1 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup

            $result1 | Should -Not -Be $null
            $result2 | Should -Be $null
        }
        It "Creates a workload group in a user defined resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolType = "Internal"
            $splatNewResourcePool = @{
                SqlInstance  = $TestConfig.instance2
                ResourcePool = $resourcePoolName
                Type         = $resourcePoolType
                Force        = $true
            }
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $wklGroupName
                ResourcePool                        = $resourcePoolName
                ResourcePoolType                    = $resourcePoolType
                Importance                          = "HIGH"
                RequestMaximumMemoryGrantPercentage = 26
                RequestMaximumCpuTimeInSeconds      = 5
                RequestMemoryGrantTimeoutInSeconds  = 5
                MaximumDegreeOfParallelism          = 2
                GroupMaximumRequests                = 1
                Force                               = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupName -ResourcePool $resourcePoolName
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -Type $resourcePoolType

            $newWorkloadGroup.Parent.Name | Should -Be $resourcePoolName
            $newWorkloadGroup.Parent.GetType().Name | Should -Be "ResourcePool"
            $newWorkloadGroup.Importance | Should -Be $splatNewWorkloadGroup.Importance
            $newWorkloadGroup.RequestMaximumMemoryGrantPercentage | Should -Be $splatNewWorkloadGroup.RequestMaximumMemoryGrantPercentage
            $newWorkloadGroup.RequestMaximumCpuTimeInSeconds | Should -Be $splatNewWorkloadGroup.RequestMaximumCpuTimeInSeconds
            $newWorkloadGroup.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatNewWorkloadGroup.RequestMemoryGrantTimeoutInSeconds
            $newWorkloadGroup.MaximumDegreeOfParallelism | Should -Be $splatNewWorkloadGroup.MaximumDegreeOfParallelism
            $newWorkloadGroup.GroupMaximumRequests | Should -Be $splatNewWorkloadGroup.GroupMaximumRequests
        }
        It "Creates multiple workload groups" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest2"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                Force         = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2
            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup -WorkloadGroup $wklGroupName, $wklGroupName2
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2

            $newWorkloadGroups | Should -Not -Be $null
            $result2.Count | Should -Be 2
            $result.Count | Should -Be ($result2.Count - 2)
        }
        It "Skips Resource Governor reconfiguration" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance     = $TestConfig.instance2
                WorkloadGroup   = $wklGroupName
                SkipReconfigure = $true
                Force           = $true
                WarningAction   = "SilentlyContinue"
            }

            $null = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $result.ReconfigurePending | Should -Be $true
        }
        AfterEach {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest2"
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupName, $wklGroupName2
        }
    }
}
