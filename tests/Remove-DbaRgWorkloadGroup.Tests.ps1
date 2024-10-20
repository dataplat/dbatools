param($ModuleName = 'dbatools')

Describe "Remove-DbaRgWorkloadGroup" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaRgWorkloadGroup
        }
        
        It "has the required parameter: SqlInstance" {
            $CommandUnderTest | Should -HaveParameter "SqlInstance"
        }
        
        It "has the required parameter: SqlCredential" {
            $CommandUnderTest | Should -HaveParameter "SqlCredential"
        }
        
        It "has the required parameter: WorkloadGroup" {
            $CommandUnderTest | Should -HaveParameter "WorkloadGroup"
        }
        
        It "has the required parameter: ResourcePool" {
            $CommandUnderTest | Should -HaveParameter "ResourcePool"
        }
        
        It "has the required parameter: ResourcePoolType" {
            $CommandUnderTest | Should -HaveParameter "ResourcePoolType"
        }
        
        It "has the required parameter: SkipReconfigure" {
            $CommandUnderTest | Should -HaveParameter "SkipReconfigure"
        }
        
        It "has the required parameter: InputObject" {
            $CommandUnderTest | Should -HaveParameter "InputObject"
        }
        
        It "has the required parameter: EnableException" {
            $CommandUnderTest | Should -HaveParameter "EnableException"
        }
    }

    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Enabled
        }

        It "Removes a workload group in default resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $global:instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName
            $result2 = Remove-DbaRgWorkloadGroup -SqlInstance $global:instance2 -WorkloadGroup $wklGroupName
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan $result3.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -BeTrue
            $result3 | Should -BeNullOrEmpty
        }

        It "Removes a workload group in a user defined resource pool" {
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
                SqlInstance      = $global:instance2
                WorkloadGroup    = $wklGroupName
                ResourcePool     = $resourcePoolName
                ResourcePoolType = $resourcePoolType
                Force            = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName
            $result2 = Remove-DbaRgWorkloadGroup -SqlInstance $global:instance2 -WorkloadGroup $wklGroupName -ResourcePool $resourcePoolName -ResourcePoolType $resourcePoolType
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName

            $null = Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName -Type $resourcePoolType

            $newWorkloadGroup | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan $result3.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -BeTrue
            $result3 | Should -BeNullOrEmpty
        }

        It "Removes multiple workload groups" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest2"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $global:instance2
                WorkloadGroup = @($wklGroupName, $wklGroupName2)
                Force         = $true
            }

            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2
            $result2 = Remove-DbaRgWorkloadGroup -SqlInstance $global:instance2 -WorkloadGroup $wklGroupName, $wklGroupName2
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2

            $newWorkloadGroups | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan $result3.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -BeTrue
            $result3 | Should -BeNullOrEmpty
        }

        It "Removes a piped workload group" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $global:instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName
            $result2 = $newWorkloadGroup | Remove-DbaRgWorkloadGroup
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $global:instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan $result3.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -BeTrue
            $result3 | Should -BeNullOrEmpty
        }
    }
}
