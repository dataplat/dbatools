param($ModuleName = 'dbatools')

Describe "Set-DbaRgWorkloadGroup" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaRgWorkloadGroup
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have WorkloadGroup parameter" {
            $CommandUnderTest | Should -HaveParameter WorkloadGroup -Type String[] -Not -Mandatory
        }
        It "Should have ResourcePool parameter" {
            $CommandUnderTest | Should -HaveParameter ResourcePool -Type String -Not -Mandatory
        }
        It "Should have ResourcePoolType parameter" {
            $CommandUnderTest | Should -HaveParameter ResourcePoolType -Type String -Not -Mandatory
        }
        It "Should have Importance parameter" {
            $CommandUnderTest | Should -HaveParameter Importance -Type String -Not -Mandatory
        }
        It "Should have RequestMaximumMemoryGrantPercentage parameter" {
            $CommandUnderTest | Should -HaveParameter RequestMaximumMemoryGrantPercentage -Type Int32 -Not -Mandatory
        }
        It "Should have RequestMaximumCpuTimeInSeconds parameter" {
            $CommandUnderTest | Should -HaveParameter RequestMaximumCpuTimeInSeconds -Type Int32 -Not -Mandatory
        }
        It "Should have RequestMemoryGrantTimeoutInSeconds parameter" {
            $CommandUnderTest | Should -HaveParameter RequestMemoryGrantTimeoutInSeconds -Type Int32 -Not -Mandatory
        }
        It "Should have MaximumDegreeOfParallelism parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumDegreeOfParallelism -Type Int32 -Not -Mandatory
        }
        It "Should have GroupMaximumRequests parameter" {
            $CommandUnderTest | Should -HaveParameter GroupMaximumRequests -Type Int32 -Not -Mandatory
        }
        It "Should have SkipReconfigure parameter" {
            $CommandUnderTest | Should -HaveParameter SkipReconfigure -Type Switch -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type WorkloadGroup[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Enabled
        }

        It "Sets a workload group in default resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $resourcePoolType = "Internal"
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $global:instance2
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
                SqlInstance                         = $global:instance2
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
            $resGov = Get-DbaResourceGovernor -SqlInstance $global:instance2

            $newWorkloadGroup | Should -Not -BeNullOrEmpty
            $resGov.ReconfigurePending | Should -BeFalse
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
                SqlInstance  = $global:instance2
                ResourcePool = $resourcePoolName
                Type         = $resourcePoolType
                Force        = $true
            }
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $global:instance2
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
                SqlInstance                         = $global:instance2
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
            $resGov = Get-DbaResourceGovernor -SqlInstance $global:instance2

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $global:instance2 -WorkloadGroup $wklGroupName -ResourcePool $resourcePoolName
            $null = Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName -Type $resourcePoolType

            $newWorkloadGroup | Should -Not -BeNullOrEmpty
            $resGov.ReconfigurePending | Should -BeFalse
            $result.Importance | Should -Be $splatSetWorkloadGroup.Importance
            $result.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroup.RequestMaximumMemoryGrantPercentage
            $result.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroup.RequestMaximumCpuTimeInSeconds
            $result.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroup.RequestMemoryGrantTimeoutInSeconds
            $result.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroup.MaximumDegreeOfParallelism
            $result.GroupMaximumRequests | Should -Be $splatSetWorkloadGroup.GroupMaximumRequests
        }

        It "Sets multiple workload groups" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest2"
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $global:instance2
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
                SqlInstance                         = $global:instance2
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
            $resGov = Get-DbaResourceGovernor -SqlInstance $global:instance2

            $newWorkloadGroups | Should -Not -BeNullOrEmpty
            $resGov.ReconfigurePending | Should -BeFalse
            $result | ForEach-Object { $_.Importance | Should -Be $splatSetWorkloadGroup.Importance }
            $result | ForEach-Object { $_.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroup.RequestMaximumMemoryGrantPercentage }
            $result | ForEach-Object { $_.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroup.RequestMaximumCpuTimeInSeconds }
            $result | ForEach-Object { $_.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroup.RequestMemoryGrantTimeoutInSeconds }
            $result | ForEach-Object { $_.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroup.MaximumDegreeOfParallelism }
            $result | ForEach-Object { $_.GroupMaximumRequests | Should -Be $splatSetWorkloadGroup.GroupMaximumRequests }
        }

        It "Sets a piped workload group" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $oldGroupMaximumRequests = 10
            $newGroupMaximumRequests = 20
            $splatNewWorkloadGroup = @{
                SqlInstance          = $global:instance2
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
                SqlInstance     = $global:instance2
                WorkloadGroup   = $wklGroupName
                SkipReconfigure = $false
                Force           = $true
            }
            $splatSetWorkloadGroup = @{
                SqlInstance      = $global:instance2
                WorkloadGroup    = $wklGroupName
                ResourcePool     = "default"
                ResourcePoolType = "Internal"
                Importance       = "HIGH"
                SkipReconfigure  = $true
            }

            $null = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaResourceGovernor -SqlInstance $global:instance2
            $result.ReconfigurePending | Should -BeFalse

            $null = Set-DbaRgWorkloadGroup @splatSetWorkloadGroup
            $result2 = Get-DbaResourceGovernor -SqlInstance $global:instance2
            $result2.ReconfigurePending | Should -BeTrue
        }

        AfterEach {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest2"
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $global:instance2 -WorkloadGroup $wklGroupName, $wklGroupName2
        }
    }
}
