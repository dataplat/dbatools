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
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have AllDatabases parameter" {
            $CommandUnderTest | Should -HaveParameter AllDatabases -Type Switch -Not -Mandatory
        }
        It "Should have State parameter" {
            $CommandUnderTest | Should -HaveParameter State -Type String[] -Not -Mandatory
        }
        It "Should have FlushInterval parameter" {
            $CommandUnderTest | Should -HaveParameter FlushInterval -Type Int64 -Not -Mandatory
        }
        It "Should have CollectionInterval parameter" {
            $CommandUnderTest | Should -HaveParameter CollectionInterval -Type Int64 -Not -Mandatory
        }
        It "Should have MaxSize parameter" {
            $CommandUnderTest | Should -HaveParameter MaxSize -Type Int64 -Not -Mandatory
        }
        It "Should have CaptureMode parameter" {
            $CommandUnderTest | Should -HaveParameter CaptureMode -Type String[] -Not -Mandatory
        }
        It "Should have CleanupMode parameter" {
            $CommandUnderTest | Should -HaveParameter CleanupMode -Type String[] -Not -Mandatory
        }
        It "Should have StaleQueryThreshold parameter" {
            $CommandUnderTest | Should -HaveParameter StaleQueryThreshold -Type Int64 -Not -Mandatory
        }
        It "Should have MaxPlansPerQuery parameter" {
            $CommandUnderTest | Should -HaveParameter MaxPlansPerQuery -Type Int64 -Not -Mandatory
        }
        It "Should have WaitStatsCaptureMode parameter" {
            $CommandUnderTest | Should -HaveParameter WaitStatsCaptureMode -Type String[] -Not -Mandatory
        }
        It "Should have CustomCapturePolicyExecutionCount parameter" {
            $CommandUnderTest | Should -HaveParameter CustomCapturePolicyExecutionCount -Type Int64 -Not -Mandatory
        }
        It "Should have CustomCapturePolicyTotalCompileCPUTimeMS parameter" {
            $CommandUnderTest | Should -HaveParameter CustomCapturePolicyTotalCompileCPUTimeMS -Type Int64 -Not -Mandatory
        }
        It "Should have CustomCapturePolicyTotalExecutionCPUTimeMS parameter" {
            $CommandUnderTest | Should -HaveParameter CustomCapturePolicyTotalExecutionCPUTimeMS -Type Int64 -Not -Mandatory
        }
        It "Should have CustomCapturePolicyStaleThresholdHours parameter" {
            $CommandUnderTest | Should -HaveParameter CustomCapturePolicyStaleThresholdHours -Type Int64 -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $env:instances = @($env:instance1, $env:instance2)
            Get-DbaDatabase -SqlInstance $env:instances | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
            New-DbaDatabase -SqlInstance $env:instances -Name dbatoolsciqs
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $env:instances | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
        }

        Context "Get some client protocols" {
            BeforeDiscovery {
                $env:instances = @($env:instance1, $env:instance2)
            }
            It "Should return valid results for <_>" -ForEach $env:instances {
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

            It "Should change the specified param to the new value for <_>" -ForEach $env:instances {
                $results = Set-DbaDbQueryStoreOption -SqlInstance $_ -Database dbatoolsciqs -FlushInterval 901 -State ReadWrite
                $results.DataFlushIntervalInSeconds | Should -Be 901
            }

            It "Should only get one database for <_>" -ForEach $env:instances {
                $results = Get-DbaDbQueryStoreOption -SqlInstance $_ -Database dbatoolsciqs
                $results.Count | Should -Be 1
                $results.Database | Should -Be 'dbatoolsciqs'
            }

            It "Should not get this one database for <_>" -ForEach $env:instances {
                $results = Get-DbaDbQueryStoreOption -SqlInstance $_ -ExcludeDatabase dbatoolsciqs
                $result = $results | Where-Object Database -eq dbatoolsciqs
                $result.Count | Should -Be 0
            }
        }
    }
}
