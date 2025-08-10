$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'ResourcePool', 'Type', 'MinimumCpuPercentage', 'MaximumCpuPercentage', 'CapCpuPercentage', 'MinimumMemoryPercentage', 'MaximumMemoryPercentage', 'MinimumIOPSPerVolume', 'MaximumIOPSPerVolume', 'MaximumProcesses', 'SkipReconfigure', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $TestConfig.instance2 -Enabled
        }
        It "Creates a resource pool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool | Should -Not -Be $null

        }
        It "Works using -Type Internal" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                MinimumCpuPercentage    = 1
                MinimumMemoryPercentage = 1
                MinimumIOPSPerVolume    = 1
                Type                    = "Internal"
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type Internal
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type Internal

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool.MaximumCpuPercentage | Should -Be $splatNewResourcePool.MaximumCpuPercentage
            $newResourcePool.MaximumMemoryPercentage | Should -Be $splatNewResourcePool.MaximumMemoryPercentage
            $newResourcePool.MaximumIOPSPerVolume | Should -Be $splatNewResourcePool.MaximumIOPSPerVolume
            $newResourcePool.CapCpuPercentage | Should -Be $splatNewResourcePool.CapCpuPercent
            $newResourcePool.MinimumCpuPercentage | Should -Be $splatNewResourcePool.MinimumCpuPercentage
            $newResourcePool.MinimumMemoryPercentage | Should -Be $splatNewResourcePool.MinimumMemoryPercentage
            $newResourcePool.MinimumIOPSPerVolume | Should -Be $splatNewResourcePool.MinimumIOPSPerVolume
        }
        It "Works using -Type External" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumProcesses        = 5
                Type                    = "External"
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type External
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type External

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool.MaximumCpuPercentage | Should -Be $splatNewResourcePool.MaximumCpuPercentage
            $newResourcePool.MaximumMemoryPercentage | Should -Be $splatNewResourcePool.MaximumMemoryPercentage
            $newResourcePool.MaximumProcesses | Should -Be $splatNewResourcePool.MaximumProcesses
        }
        It "Skips Resource Governor reconfiguration" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
                SkipReconfigure         = $true
                WarningAction           = "SilentlyContinue"
            }

            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $result.ReconfigurePending | Should -Be $true
        }
        AfterEach {
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName, $resourcePoolName2 -Type Internal
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName, $resourcePoolName2 -Type External
        }
    }
}
