$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'AllDatabases', 'State', 'FlushInterval', 'CollectionInterval', 'MaxSize', 'CaptureMode', 'CleanupMode', 'StaleQueryThreshold', 'MaxPlansPerQuery', 'WaitStatsCaptureMode', 'EnableException', 'CustomCapturePolicyExecutionCount', 'CustomCapturePolicyTotalCompileCPUTimeMS', 'CustomCapturePolicyTotalExecutionCPUTimeMS', 'CustomCapturePolicyStaleThresholdHours'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        Get-DbaDatabase -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
        New-DbaDatabase -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Name dbatoolsciqs
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
    }
    Context "Get some client protocols" {
        foreach ($instance in ($TestConfig.instance1, $TestConfig.instance2)) {
            $server = Connect-DbaInstance -SqlInstance $instance
            $results = Get-DbaDbQueryStoreOption -SqlInstance $server -WarningVariable warning 3>&1

            if ($server.VersionMajor -lt 13) {
                It "should warn" {
                    $warning | Should Not Be $null
                }
            } else {
                It "should return some valid results" {
                    $result = $results | Where-Object Database -eq dbatoolsciqs
                    if ($server.VersionMajor -lt 16) {
                        $result.ActualState | Should Be 'Off'
                    } else {
                        $result.ActualState | Should Be 'ReadWrite'
                    }
                    $result.MaxStorageSizeInMB | Should BeGreaterThan 1
                }

                It "should change the specified param to the new value" {
                    $results = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs -FlushInterval 901 -State ReadWrite
                    $results.DataFlushIntervalInSeconds | Should Be 901
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
