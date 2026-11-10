#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgRingBuffer",
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
                "RingBufferType",
                "CollectionMinutes",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Query handling" {
            BeforeAll {
                $script:lastQuery = $null
                $script:throwRingBufferQuery = $false

                $script:mockTimestampTable = New-Object System.Data.DataTable
                $null = $script:mockTimestampTable.Columns.Add("TimeStamp", [double])
                $timestampRow = $script:mockTimestampTable.NewRow()
                $timestampRow.TimeStamp = 123456
                $script:mockTimestampTable.Rows.Add($timestampRow)

                $script:mockServer = [PSCustomObject]@{
                    ComputerName       = "sql1"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "sql1"
                }

                $script:mockServer | Add-Member -Force -MemberType ScriptMethod -Name Query -Value {
                    param($Sql)

                    if ($Sql -like "*sys.dm_os_sys_info*") {
                        $script:mockTimestampTable
                    } elseif ($script:throwRingBufferQuery) {
                        throw "ring buffer query failed"
                    } else {
                        $script:lastQuery = $Sql
                        @()
                    }
                }
            }

            BeforeEach {
                $script:lastQuery = $null
                $script:throwRingBufferQuery = $false
            }

            It "uses the scalar timestamp value when building the HADR ring buffer query" {
                Mock Connect-DbaInstance {
                    $script:mockServer
                }

                $null = Get-DbaAgRingBuffer -SqlInstance "sql1"

                $script:lastQuery | Should -Match "CONVERT\(BIGINT, 123456 - \[timestamp\]\) AS age_ms"
                # 123456 minus the default of 60 minutes in milliseconds
                $script:lastQuery | Should -Match "\[timestamp\] > -3476544"
                $script:lastQuery | Should -Not -Match "System\.Data\.DataRow"
            }

            It "routes HADR ring buffer query failures through Stop-Function" {
                Mock Connect-DbaInstance {
                    $script:mockServer
                }
                Mock Stop-Function {
                    param(
                        $Message,
                        $Target,
                        $ErrorRecord
                    )

                    throw "$Message | inner: $($ErrorRecord.Exception.Message) | target: $Target"
                }

                $script:throwRingBufferQuery = $true

                { Get-DbaAgRingBuffer -SqlInstance "sql1" } | Should -Throw "*Failed to query HADR ring buffer data.*ring buffer query failed*target: sql1*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving HADR ring buffer data" {
        It "Returns results with expected properties" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $TestConfig.InstanceSingle)
            # A failing query only warns, see issue #10819
            $WarnVar | Should -BeNullOrEmpty
            if ($results.Count -gt 0) {
                $results[0].PSObject.Properties.Name | Should -Contain "ComputerName"
                $results[0].PSObject.Properties.Name | Should -Contain "InstanceName"
                $results[0].PSObject.Properties.Name | Should -Contain "SqlInstance"
                $results[0].PSObject.Properties.Name | Should -Contain "RingBufferType"
                $results[0].PSObject.Properties.Name | Should -Contain "RecordId"
                $results[0].PSObject.Properties.Name | Should -Contain "EventTime"
                $results[0].PSObject.Properties.Name | Should -Contain "Record"
            }
        }

        It "Filters by RingBufferType when specified" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $TestConfig.InstanceSingle -RingBufferType RING_BUFFER_HADRDBMGR_API)
            $WarnVar | Should -BeNullOrEmpty
            foreach ($result in $results) {
                $result.RingBufferType | Should -Be "RING_BUFFER_HADRDBMGR_API"
            }
        }
    }

    Context "When a record is older than 24.8 days" {
        BeforeAll {
            # A record that old needs an instance that has run that long, and the HADR ring buffers stay empty without
            # availability group activity. So the command reads the scheduler monitor ring buffer of the real instance,
            # which gets a record every minute, with the current timestamp moved 30 days ahead, see issue #10819.
            $ringBufferServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $shiftedQuery = {
                param($Sql)
                if ($Sql -like "*sys.dm_os_sys_info*") {
                    [PSCustomObject]@{
                        TimeStamp = [long]$this.ConnectionContext.ExecuteScalar("SELECT ms_ticks FROM sys.dm_os_sys_info") + 30L * 86400000
                    }
                } else {
                    $this.ConnectionContext.ExecuteWithResults(($Sql -replace "RING_BUFFER_HADR[A-Z_]*", "RING_BUFFER_SCHEDULER_MONITOR")).Tables[0].Rows
                }
            }
            # Add-Member -Force refuses to hide the Query method of the dbatools type data, adding it prevalidated does not
            $shiftedQueryMethod = New-Object System.Management.Automation.PSScriptMethod -ArgumentList "Query", $shiftedQuery
            $ringBufferServer.PSObject.Members.Add($shiftedQueryMethod, $true)
        }

        AfterAll {
            $ringBufferServer.ConnectionContext.Disconnect()
        }

        It "Returns the records with their time 30 days back" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $ringBufferServer -CollectionMinutes (31 * 24 * 60))
            $WarnVar | Should -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
            $results[0].EventTime | Should -BeLessThan (Get-Date).AddDays(-29)
            $results[0].EventTime | Should -BeGreaterThan (Get-Date).AddDays(-31)
        }

        It "Leaves the records out that are older than CollectionMinutes" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $ringBufferServer)
            $WarnVar | Should -BeNullOrEmpty
            $results.Count | Should -Be 0
        }
    }
}