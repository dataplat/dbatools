$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'ResourcePool', 'Type', 'MinimumCpuPercentage', 'MaximumCpuPercentage', 'CapCpuPercentage', 'MinimumMemoryPercentage', 'MaximumMemoryPercentage', 'MinimumIOPSPerVolume', 'MaximumIOPSPerVolume', 'MaximumProcesses', 'SkipReconfigure', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Functionality" {
        BeforeAll {
            $null = Set-DbaResourceGovernor -SqlInstance $script:instance2 -Enabled
        }
        It "Sets a resource pool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Set-DbaRgResourcePool -SqlInstance $script:instance2 -ResourcePool $resourcePoolName -MaximumCpuPercentage 99

            $result2.MaximumCpuPercentage | Should -Be 99
        }
        #TODO
        It "Works using -Type Internal" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Type                    = "Internal"
            }
            $splatSetResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 99
                MaximumMemoryPercentage = 99
                MaximumIOPSPerVolume    = 99
                CapCpuPercent           = 99
                MinimumCpuPercentage    = 2
                MinimumMemoryPercentage = 2
                MinimumIOPSPerVolume    = 2
                Type                    = "Internal"
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Set-DbaRgResourcePool @splatSetResourcePool

            $result.Name | Should -Be $resourcePoolName
            $result.MaximumCpuPercentage | Should -Be $splatSetResourcePool.MaximumCpuPercentage
            $result.MaximumMemoryPercentage | Should -Be $splatSetResourcePool.MaximumMemoryPercentage
            $result.MaximumIOPSPerVolume | Should -Be $splatSetResourcePool.MaximumIOPSPerVolume
            $result.CapCpuPercentage | Should -Be $splatSetResourcePool.CapCpuPercent
            $result.MinimumCpuPercentage | Should -Be $splatSetResourcePool.MinimumCpuPercentage
            $result.MinimumMemoryPercentage | Should -Be $splatSetResourcePool.MinimumMemoryPercentage
            $result.MinimumIOPSPerVolume | Should -Be $splatSetResourcePool.MinimumIOPSPerVolume
        }
        It "Works using -Type External" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumProcesses        = 1
                Type                    = "External"
            }
            $splatSetResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 99
                MaximumMemoryPercentage = 99
                MaximumProcesses        = 2
                Type                    = "External"
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Set-DbaRgResourcePool @splatSetResourcePool

            $result.Name | Should -Be $resourcePoolName
            $result.MaximumCpuPercentage | Should -Be $splatSetResourcePool.MaximumCpuPercentage
            $result.MaximumMemoryPercentage | Should -Be $splatSetResourcePool.MaximumMemoryPercentage
            $result.MaximumProcesses | Should -Be $splatSetResourcePool.MaximumProcesses
        }
        It "Skips Resource Governor reconfiguration" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $script:instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
            }

            $null = New-DbaRgResourcePool @splatNewResourcePool
            $null = Set-DbaRgResourcePool -SqlInstance $script:instance2 -ResourcePool $resourcePoolName -MaximumCpuPercentage 99 -SkipReconfigure
            $result = Get-DbaResourceGovernor -SqlInstance $script:instance2

            $result.ReconfigurePending | Should -Be $true
        }
        AfterEach {
            $resourcePoolName = "dbatoolssci_poolTest"
            $null = Remove-DbaRgResourcePool -SqlInstance $script:instance2 -ResourcePool $resourcePoolName -Type Internal
            $null = Remove-DbaRgResourcePool -SqlInstance $script:instance2 -ResourcePool $resourcePoolName -Type External
        }
    }
}