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
}