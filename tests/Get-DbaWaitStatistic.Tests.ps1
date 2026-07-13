#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaWaitStatistic",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Threshold",
                "IncludeIgnorable",
                "ExcludeWaitType",
                "IncludeWaitType",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Wait type filter validation" {
            BeforeAll {
                $script:lastQuery = $null
                # A REAL (disconnected) SMO Server decorated with instance ETS members
                # rides the typed Connect-DbaInstance seam; a bare PSCustomObject cannot.
                $script:mockServer = New-Object Microsoft.SqlServer.Management.Smo.Server
                $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value "sql1"
                $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name ServiceName -Value "MSSQLSERVER"
                $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name DomainInstanceName -Value "sql1"
                $script:mockServer | Add-Member -Force -MemberType ScriptMethod -Name Query -Value {
                    param($Sql)
                    $script:lastQuery = $Sql
                    @()
                }
            }

            It "normalizes ExcludeWaitType values and still applies them when IncludeIgnorable is used" {
                Mock Connect-DbaInstance {
                    $script:mockServer
                }

                $null = Get-DbaWaitStatistic -SqlInstance "sql1" -IncludeIgnorable -ExcludeWaitType "cxpacket"

                $script:lastQuery | Should -Match "NOT IN \('CXPACKET'\)"
            }

            It "removes IncludeWaitType values from the default ignorable filter" {
                Mock Connect-DbaInstance {
                    $script:mockServer
                }

                $null = Get-DbaWaitStatistic -SqlInstance "sql1" -IncludeWaitType "sos_work_dispatcher"

                $script:lastQuery | Should -Match "LAZYWRITER_SLEEP"
                $script:lastQuery | Should -Not -Match "SOS_WORK_DISPATCHER"
            }

            It "rejects invalid wait type names before connecting" {
                {
                    Get-DbaWaitStatistic -SqlInstance "sql1" -ExcludeWaitType "CXPACKET'; DROP TABLE dbo.t;--"
                } | Should -Throw
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100
        }

        It "returns results" {
            $results.Count -gt 0 | Should -Be $true
        }

        It "returns a hyperlink for each result" {
            foreach ($result in $results) {
                $result.URL -match "sqlskills.com" | Should -Be $true
            }
        }
    }

    Context "Command returns proper info when using parameter IncludeIgnorable" {
        BeforeAll {
            $ignoredWaits = @(
                "REQUEST_FOR_DEADLOCK_SEARCH",
                "SLEEP_MASTERDBREADY",
                "SLEEP_TASK",
                "LAZYWRITER_SLEEP"
            )
            $results = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100 -IncludeIgnorable | Where-Object WaitType -in $ignoredWaits
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "results includes ignorable column" {
            $results[0].PSObject.Properties.Name.Contains("Ignorable") | Should -Be $true
        }

        It "returns a hyperlink for each result" {
            foreach ($result in $results) {
                $result.URL -match "sqlskills.com" | Should -Be $true
            }
        }
    }

}