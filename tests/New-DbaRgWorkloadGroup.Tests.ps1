param($ModuleName = 'dbatools')

Describe "New-DbaRgWorkloadGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaRgWorkloadGroup
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have WorkloadGroup parameter" {
            $CommandUnderTest | Should -HaveParameter WorkloadGroup
        }
        It "Should have ResourcePool parameter" {
            $CommandUnderTest | Should -HaveParameter ResourcePool
        }
        It "Should have ResourcePoolType parameter" {
            $CommandUnderTest | Should -HaveParameter ResourcePoolType
        }
        It "Should have Importance parameter" {
            $CommandUnderTest | Should -HaveParameter Importance
        }
        It "Should have RequestMaximumMemoryGrantPercentage parameter" {
            $CommandUnderTest | Should -HaveParameter RequestMaximumMemoryGrantPercentage
        }
        It "Should have RequestMaximumCpuTimeInSeconds parameter" {
            $CommandUnderTest | Should -HaveParameter RequestMaximumCpuTimeInSeconds
        }
        It "Should have RequestMemoryGrantTimeoutInSeconds parameter" {
            $CommandUnderTest | Should -HaveParameter RequestMemoryGrantTimeoutInSeconds
        }
        It "Should have MaximumDegreeOfParallelism parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumDegreeOfParallelism
        }
        It "Should have GroupMaximumRequests parameter" {
            $CommandUnderTest | Should -HaveParameter GroupMaximumRequests
        }
        It "Should have SkipReconfigure parameter" {
            $CommandUnderTest | Should -HaveParameter SkipReconfigure
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Enabled
        }

        It "Creates a workload group in default resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $global:instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -BeNullOrEmpty
            $result2.Count | Should -BeGreaterThan $result.Count
            $result2.Name | Should -Contain $wklGroupName
        }

        It "Does nothing without -Force if workload group exists" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $global:instance2
                WorkloadGroup = $wklGroupName
            }
            $result1 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup

            $result1 | Should -Not -BeNullOrEmpty
            $result2 | Should -BeNullOrEmpty
        }

        It "Creates a workload group in a user defined resource pool" {
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

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $global:instance2 -WorkloadGroup $wklGroupName -ResourcePool $resourcePoolName
            $null = Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName -Type $resourcePoolType

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
                SqlInstance   = $global:instance2
                Force         = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2
            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup -WorkloadGroup $wklGroupName, $wklGroupName2
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2

            $newWorkloadGroups | Should -Not -BeNullOrEmpty
            $result2.Count | Should -Be 2
            $result.Count | Should -Be ($result2.Count - 2)
        }

        It "Skips Resource Governor reconfiguration" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance     = $global:instance2
                WorkloadGroup   = $wklGroupName
                SkipReconfigure = $true
                Force           = $true
            }

            $null = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaResourceGovernor -SqlInstance $global:instance2

            $result.ReconfigurePending | Should -BeTrue
        }

        AfterEach {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest2"
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $global:instance2 -WorkloadGroup $wklGroupName, $wklGroupName2
        }
    }
}
