param($ModuleName = 'dbatools')

Describe "New-DbaRgResourcePool" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaRgResourcePool
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have ResourcePool parameter" {
            $CommandUnderTest | Should -HaveParameter ResourcePool -Type String[] -Not -Mandatory
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Not -Mandatory
        }
        It "Should have MinimumCpuPercentage parameter" {
            $CommandUnderTest | Should -HaveParameter MinimumCpuPercentage -Type Int32 -Not -Mandatory
        }
        It "Should have MaximumCpuPercentage parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumCpuPercentage -Type Int32 -Not -Mandatory
        }
        It "Should have CapCpuPercentage parameter" {
            $CommandUnderTest | Should -HaveParameter CapCpuPercentage -Type Int32 -Not -Mandatory
        }
        It "Should have MinimumMemoryPercentage parameter" {
            $CommandUnderTest | Should -HaveParameter MinimumMemoryPercentage -Type Int32 -Not -Mandatory
        }
        It "Should have MaximumMemoryPercentage parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumMemoryPercentage -Type Int32 -Not -Mandatory
        }
        It "Should have MinimumIOPSPerVolume parameter" {
            $CommandUnderTest | Should -HaveParameter MinimumIOPSPerVolume -Type Int32 -Not -Mandatory
        }
        It "Should have MaximumIOPSPerVolume parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumIOPSPerVolume -Type Int32 -Not -Mandatory
        }
        It "Should have MaximumProcesses parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumProcesses -Type Int32 -Not -Mandatory
        }
        It "Should have SkipReconfigure parameter" {
            $CommandUnderTest | Should -HaveParameter SkipReconfigure -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $script:instance2 -Enabled
        }

        It "Creates a resource pool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercentage        = 100
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $script:instance2
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $script:instance2

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool | Should -Not -BeNullOrEmpty
        }

        It "Works using -Type Internal" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercentage        = 100
                MinimumCpuPercentage    = 1
                MinimumMemoryPercentage = 1
                MinimumIOPSPerVolume    = 1
                Type                    = "Internal"
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $script:instance2 -Type Internal
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $script:instance2 -Type Internal

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool.MaximumCpuPercentage | Should -Be $splatNewResourcePool.MaximumCpuPercentage
            $newResourcePool.MaximumMemoryPercentage | Should -Be $splatNewResourcePool.MaximumMemoryPercentage
            $newResourcePool.MaximumIOPSPerVolume | Should -Be $splatNewResourcePool.MaximumIOPSPerVolume
            $newResourcePool.CapCpuPercentage | Should -Be $splatNewResourcePool.CapCpuPercentage
            $newResourcePool.MinimumCpuPercentage | Should -Be $splatNewResourcePool.MinimumCpuPercentage
            $newResourcePool.MinimumMemoryPercentage | Should -Be $splatNewResourcePool.MinimumMemoryPercentage
            $newResourcePool.MinimumIOPSPerVolume | Should -Be $splatNewResourcePool.MinimumIOPSPerVolume
        }

        It "Works using -Type External" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumProcesses        = 5
                Type                    = "External"
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $script:instance2 -Type External
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $script:instance2 -Type External

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool.MaximumCpuPercentage | Should -Be $splatNewResourcePool.MaximumCpuPercentage
            $newResourcePool.MaximumMemoryPercentage | Should -Be $splatNewResourcePool.MaximumMemoryPercentage
            $newResourcePool.MaximumProcesses | Should -Be $splatNewResourcePool.MaximumProcesses
        }

        It "Skips Resource Governor reconfiguration" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercentage        = 100
                Force                   = $true
                SkipReconfigure         = $true
            }

            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaResourceGovernor -SqlInstance $script:instance2

            $result.ReconfigurePending | Should -BeTrue
        }

        AfterEach {
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $null = Remove-DbaRgResourcePool -SqlInstance $script:instance2 -ResourcePool $resourcePoolName, $resourcePoolName2 -Type Internal
            $null = Remove-DbaRgResourcePool -SqlInstance $script:instance2 -ResourcePool $resourcePoolName, $resourcePoolName2 -Type External
        }
    }
}
