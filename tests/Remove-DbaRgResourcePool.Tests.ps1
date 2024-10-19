param($ModuleName = 'dbatools')

Describe "Remove-DbaRgResourcePool" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaRgResourcePool
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "ResourcePool",
                "Type",
                "SkipReconfigure",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Enabled
        }

        It "Removes a resource pool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $global:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaRgResourcePool -SqlInstance $global:instance2
            Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName
            $result2 = Get-DbaRgResourcePool -SqlInstance $global:instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
        }

        It "Works using -Type Internal" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $global:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Type                    = "Internal"
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaRgResourcePool -SqlInstance $global:instance2 -Type Internal
            Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName -Type Internal
            $result2 = Get-DbaRgResourcePool -SqlInstance $global:instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
        }

        It "Works using -Type External" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $global:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Type                    = "External"
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaRgResourcePool -SqlInstance $global:instance2 -Type External
            Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName -Type External
            $result2 = Get-DbaRgResourcePool -SqlInstance $global:instance2 -Type External

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
        }

        It "Accepts a list of resource pools" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $splatNewResourcePool = @{
                SqlInstance             = $global:instance2
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName2
            $result = Get-DbaRgResourcePool -SqlInstance $global:instance2
            Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName, $resourcePoolName2
            $result2 = Get-DbaRgResourcePool -SqlInstance $global:instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
            $result2.Name | Should -Not -Contain $resourcePoolName2
        }

        It "Accepts input from Get-DbaRgResourcePool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $splatNewResourcePool = @{
                SqlInstance             = $global:instance2
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName2
            $result = Get-DbaRgResourcePool -SqlInstance $global:instance2
            $result | Where-Object Name -in ($resourcePoolName, $resourcePoolName2) | Remove-DbaRgResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $global:instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
            $result2.Name | Should -Not -Contain $resourcePoolName2
        }

        It "Skips Resource Governor reconfiguration" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $global:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            Remove-DbaRgResourcePool -SqlInstance $global:instance2 -ResourcePool $resourcePoolName -SkipReconfigure
            $result = Get-DbaResourceGovernor -SqlInstance $global:instance2

            $result.ReconfigurePending | Should -Be $true
        }
    }
}
