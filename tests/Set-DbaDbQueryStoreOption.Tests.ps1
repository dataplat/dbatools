param($ModuleName = 'dbatools')

Describe "Set-DbaDbQueryStoreOption" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbQueryStoreOption
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "AllDatabases",
                "State",
                "FlushInterval",
                "CollectionInterval",
                "MaxSize",
                "CaptureMode",
                "CleanupMode",
                "StaleQueryThreshold",
                "MaxPlansPerQuery",
                "WaitStatsCaptureMode",
                "CustomCapturePolicyExecutionCount",
                "CustomCapturePolicyTotalCompileCPUTimeMS",
                "CustomCapturePolicyTotalExecutionCPUTimeMS",
                "CustomCapturePolicyStaleThresholdHours",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $global:instances = @($global:instance1, $global:instance2)
            Get-DbaDatabase -SqlInstance $global:instances | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
            New-DbaDatabase -SqlInstance $global:instances -Name dbatoolsciqs
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instances | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
        }

        Context "Get some client protocols" {
            BeforeDiscovery {
                $global:instances = @($global:instance1, $global:instance2)
            }
            It "Should return valid results for <_>" -ForEach $global:instances {
                $server = Connect-DbaInstance -SqlInstance $_
                $results = Get-DbaDbQueryStoreOption -SqlInstance $server -WarningVariable warning 3>&1

                if ($server.VersionMajor -lt 13) {
                    $warning | Should -Not -BeNullOrEmpty
                } else {
                    $result = $results | Where-Object Database -eq dbatoolsciqs
                    if ($server.VersionMajor -lt 16) {
                        $result.ActualState | Should -Be 'Off'
                    } else {
                        $result.ActualState | Should -Be 'ReadWrite'
                    }
                    $result.MaxStorageSizeInMB | Should -BeGreaterThan 1
                }
            }

            It "Should change the specified param to the new value for <_>" -ForEach $global:instances {
                $results = Set-DbaDbQueryStoreOption -SqlInstance $_ -Database dbatoolsciqs -FlushInterval 901 -State ReadWrite
                $results.DataFlushIntervalInSeconds | Should -Be 901
            }

            It "Should only get one database for <_>" -ForEach $global:instances {
                $results = Get-DbaDbQueryStoreOption -SqlInstance $_ -Database dbatoolsciqs
                $results.Count | Should -Be 1
                $results.Database | Should -Be 'dbatoolsciqs'
            }

            It "Should not get this one database for <_>" -ForEach $global:instances {
                $results = Get-DbaDbQueryStoreOption -SqlInstance $_ -ExcludeDatabase dbatoolsciqs
                $result = $results | Where-Object Database -eq dbatoolsciqs
                $result.Count | Should -Be 0
            }
        }
    }
}
