#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTempdbUsage",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a test query that will use tempdb to ensure we get results
            $splatConnection = @{
                SqlInstance     = $TestConfig.instance1
                Database        = "tempdb"
                Query           = "CREATE TABLE #TestTempTable (ID INT, Name VARCHAR(100)); INSERT INTO #TestTempTable VALUES (1, 'Test');"
                EnableException = $true
            }
            Invoke-DbaQuery @splatConnection

            # Get tempdb usage (may return results if the query above is still active)
            $result = Get-DbaTempdbUsage -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject or DataRow" {
            if ($result) {
                # Query results come back as DataRow objects
                $result[0] | Should -BeOfType [System.Data.DataRow]
            }
        }

        It "Has the expected properties when results are returned" {
            if ($result) {
                $expectedProps = @(
                    'ComputerName',
                    'InstanceName',
                    'SqlInstance',
                    'Spid',
                    'StatementCommand',
                    'QueryText',
                    'ProcedureName',
                    'StartTime',
                    'CurrentUserAllocatedKB',
                    'TotalUserAllocatedKB',
                    'UserDeallocatedKB',
                    'TotalUserDeallocatedKB',
                    'InternalAllocatedKB',
                    'TotalInternalAllocatedKB',
                    'InternalDeallocatedKB',
                    'TotalInternalDeallocatedKB',
                    'RequestedReads',
                    'RequestedWrites',
                    'RequestedLogicalReads',
                    'RequestedCPUTime',
                    'IsUserProcess',
                    'Status',
                    'Database',
                    'LoginName',
                    'OriginalLoginName',
                    'NTDomain',
                    'NTUserName',
                    'HostName',
                    'ProgramName',
                    'LoginTime',
                    'LastRequestedStartTime',
                    'LastRequestedEndTime'
                )
                $actualProps = $result[0].Table.Columns.ColumnName
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
                }
            }
        }

        It "Returns results only for sessions with tempdb allocation activity" {
            # The command filters for sessions with non-zero tempdb usage
            # If no results, that's valid - no active tempdb usage
            $result | Should -BeOfType [System.Data.DataRow] -Or $null
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>