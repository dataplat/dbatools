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
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaTempdbUsage -SqlInstance $TestConfig.InstanceSingle)
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no active tempdb usage to validate" }
            $result[0] | Should -BeOfType System.Data.DataRow
        }

        It "Returns output with expected properties when tempdb activity exists" {
            if (-not $result) { Set-ItResult -Skipped -Because "no active tempdb usage to validate" }
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Spid",
                "StatementCommand",
                "QueryText",
                "ProcedureName",
                "StartTime",
                "CurrentUserAllocatedKB",
                "TotalUserAllocatedKB",
                "UserDeallocatedKB",
                "TotalUserDeallocatedKB",
                "InternalAllocatedKB",
                "TotalInternalAllocatedKB",
                "InternalDeallocatedKB",
                "TotalInternalDeallocatedKB",
                "RequestedReads",
                "RequestedWrites",
                "RequestedLogicalReads",
                "RequestedCPUTime",
                "IsUserProcess",
                "Status",
                "Database",
                "LoginName",
                "OriginalLoginName",
                "NTDomain",
                "NTUserName",
                "HostName",
                "ProgramName",
                "LoginTime",
                "LastRequestedStartTime",
                "LastRequestedEndTime"
            )
            foreach ($prop in $expectedProps) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}