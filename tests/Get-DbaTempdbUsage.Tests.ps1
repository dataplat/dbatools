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
    Context "When getting tempdb usage" {
        BeforeAll {
            $result = @(Get-DbaTempdbUsage -SqlInstance $TestConfig.instance1 -OutVariable "global:dbatoolsciOutput")
        }

        It "Should return results" {
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
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
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name | Where-Object { $PSItem -notin ("RowError", "RowState", "Table", "ItemArray", "HasErrors") }
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataRow"
        }
    }
}
