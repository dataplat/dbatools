$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'AllDatabases', 'State', 'FlushInterval', 'CollectionInterval', 'MaxSize', 'CaptureMode', 'CleanupMode', 'StaleQueryThreshold', 'MaxPlansPerQuery', 'WaitStatsCaptureMode', 'EnableException', 'CustomCapturePolicyExecutionCount', 'CustomCapturePolicyTotalCompileCPUTimeMS', 'CustomCapturePolicyTotalExecutionCPUTimeMS', 'CustomCapturePolicyStaleThresholdHours'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        Get-DbaDatabase -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
        New-DbaDatabase -SqlInstance $script:instance1, $script:instance2 -Name dbatoolsciqs
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
    }
    Context "Get some client protocols" {
        foreach ($instance in ($script:instance1, $script:instance2)) {
            $server = Connect-DbaInstance -SqlInstance $instance
            $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -WarningVariable warning 3>&1

            if ($server.VersionMajor -lt 13) {
                It "should warn" {
                    $warning | Should Not Be $null
                }
            } else {
                It "should return some valid results" {
                    $result = $results | Where-Object Database -eq dbatoolsciqs
                    $result.ActualState | Should Be 'Off'
                    $result.MaxStorageSizeInMB | Should BeGreaterThan 1
                }

                $newnumber = $result.DataFlushIntervalInSeconds + 1

                It "should change the specified param to the new value" {
                    $results = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs -FlushInterval $newnumber -State ReadWrite
                    $results.DataFlushIntervalInSeconds | Should Be $newnumber
                }

                It "should only get one database" {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs
                    $results.Count | Should Be 1
                    $results.Database | Should Be 'dbatoolsciqs'
                }

                It "should not get this one database" {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -ExcludeDatabase dbatoolsciqs
                    $result = $results | Where-Object Database -eq dbatoolsciqs
                    $result.Count | Should Be 0
                }
            }
        }
    }
}