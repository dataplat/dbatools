$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'WorkloadGroup', 'ResourcePool', 'ResourcePoolType', 'Importance', 'RequestMaximumMemoryGrantPercentage', 'RequestMaximumCpuTimeInSeconds', 'RequestMemoryGrantTimeoutInSeconds', 'MaximumDegreeOfParallelism', 'GroupMaximumRequests', 'SkipReconfigure', 'InputObject', 'EnableException'
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
        It "Sets a workload group in default resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $resourcePoolType = "Internal"
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $wklGroupName
                ResourcePool                        = "default"
                ResourcePoolType                    = $resourcePoolType
                Importance                          = "MEDIUM"
                RequestMaximumMemoryGrantPercentage = 25
                RequestMaximumCpuTimeInSeconds      = 0
                RequestMemoryGrantTimeoutInSeconds  = 0
                MaximumDegreeOfParallelism          = 0
                GroupMaximumRequests                = 0
                Force                               = $true
            }
            $splatSetWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $wklGroupName
                ResourcePool                        = "default"
                ResourcePoolType                    = $resourcePoolType
                Importance                          = "HIGH"
                RequestMaximumMemoryGrantPercentage = 26
                RequestMaximumCpuTimeInSeconds      = 5
                RequestMemoryGrantTimeoutInSeconds  = 5
                MaximumDegreeOfParallelism          = 2
                GroupMaximumRequests                = 1
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Set-DbaRgWorkloadGroup @splatSetWorkloadGroup
            $resGov = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $newWorkloadGroup | Should -Not -Be $null
            $resGov.ReconfigurePending | Should -Be $false
            $result.Importance | Should -Be $splatSetWorkloadGroup.Importance
            $result.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroup.RequestMaximumMemoryGrantPercentage
            $result.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroup.RequestMaximumCpuTimeInSeconds
            $result.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroup.RequestMemoryGrantTimeoutInSeconds
            $result.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroup.MaximumDegreeOfParallelism
            $result.GroupMaximumRequests | Should -Be $splatSetWorkloadGroup.GroupMaximumRequests
        }
        It "Sets a workload group in a user defined resource pool" {
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
                Importance                          = "MEDIUM"
                RequestMaximumMemoryGrantPercentage = 25
                RequestMaximumCpuTimeInSeconds      = 0
                RequestMemoryGrantTimeoutInSeconds  = 0
                MaximumDegreeOfParallelism          = 0
                GroupMaximumRequests                = 0
                Force                               = $true
            }
            $splatSetWorkloadGroup = @{
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
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Set-DbaRgWorkloadGroup @splatSetWorkloadGroup
            $resGov = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupName -ResourcePool $resourcePoolName
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -Type $resourcePoolType

            $newWorkloadGroup | Should -Not -Be $null
            $resGov.ReconfigurePending | Should -Be $false
            $result.Importance | Should -Be $splatSetWorkloadGroup.Importance
            $result.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroup.RequestMaximumMemoryGrantPercentage
            $result.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroup.RequestMaximumCpuTimeInSeconds
            $result.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroup.RequestMemoryGrantTimeoutInSeconds
            $result.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroup.MaximumDegreeOfParallelism
            $result.GroupMaximumRequests | Should -Be $splatSetWorkloadGroup.GroupMaximumRequests
        }
        It "Sets multiple workload groups" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = @($wklGroupName, $wklGroupName2)
                Importance                          = "MEDIUM"
                RequestMaximumMemoryGrantPercentage = 25
                RequestMaximumCpuTimeInSeconds      = 0
                RequestMemoryGrantTimeoutInSeconds  = 0
                MaximumDegreeOfParallelism          = 0
                GroupMaximumRequests                = 0
                Force                               = $true
            }
            $splatSetWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = @($wklGroupName, $wklGroupName2)
                ResourcePool                        = "default"
                Importance                          = "HIGH"
                RequestMaximumMemoryGrantPercentage = 26
                RequestMaximumCpuTimeInSeconds      = 5
                RequestMemoryGrantTimeoutInSeconds  = 5
                MaximumDegreeOfParallelism          = 2
                GroupMaximumRequests                = 1
            }
            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Set-DbaRgWorkloadGroup @splatSetWorkloadGroup
            $resGov = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $newWorkloadGroups | Should -Not -Be $null
            $resGov.ReconfigurePending | Should -Be $false
            $result.Foreach{ $_.Importance | Should -Be $splatSetWorkloadGroup.Importance }
            $result.Foreach{ $_.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroup.RequestMaximumMemoryGrantPercentage }
            $result.Foreach{ $_.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroup.RequestMaximumCpuTimeInSeconds }
            $result.Foreach{ $_.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroup.RequestMemoryGrantTimeoutInSeconds }
            $result.Foreach{ $_.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroup.MaximumDegreeOfParallelism }
            $result.Foreach{ $_.GroupMaximumRequests | Should -Be $splatSetWorkloadGroup.GroupMaximumRequests }
        }
        It "Sets a piped workload group" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $oldGroupMaximumRequests = 10
            $newGroupMaximumRequests = 10
            $splatNewWorkloadGroup = @{
                SqlInstance          = $TestConfig.instance2
                WorkloadGroup        = $wklGroupName
                ResourcePool         = "default"
                GroupMaximumRequests = $oldGroupMaximumRequests
                Force                = $true
            }
            $result = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = $result | Set-DbaRgWorkloadGroup -GroupMaximumRequests $newGroupMaximumRequests

            $result.GroupMaximumRequests | Should -Be $oldGroupMaximumRequests
            $result2.GroupMaximumRequests | Should -Be $newGroupMaximumRequests
        }
        It "Skips Resource Governor reconfiguration" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance     = $TestConfig.instance2
                WorkloadGroup   = $wklGroupName
                SkipReconfigure = $false
                Force           = $true
            }
            $splatSetWorkloadGroup = @{
                SqlInstance     = $TestConfig.instance2
                WorkloadGroup   = $wklGroupName
                ResourcePool    = "default"
                ResourcePoolType = "Internal"
                Importance      = "HIGH"
                SkipReconfigure = $true
            }

            $null = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2
            $result.ReconfigurePending | Should -Be $false

            $null = Set-DbaRgWorkloadGroup @splatSetWorkloadGroup
            $result2 = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2
            $result2.ReconfigurePending | Should -Be $true
        }
        AfterEach {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest2"
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupName, $wklGroupName2
        }
    }
}
