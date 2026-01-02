#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaExtendedStoredProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "ExtendedProcedure",
                "ExcludeExtendedProcedure",
                "DestinationPath",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Note: Extended Stored Procedures require DLL files which may not be available in test environment
        # This test focuses on the command structure and will skip if no custom XPs exist
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1

        # Check if any custom Extended Stored Procedures exist
        $xpCheckSql = @"
SELECT COUNT(*) AS XPCount
FROM sys.procedures p
WHERE p.type = 'X'
    AND p.is_ms_shipped = 0
"@
        $xpCount = $sourceServer.Query($xpCheckSql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying Extended Stored Procedures" {
        It "Should connect to source and destination servers" {
            $splatConnection = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
            }
            { Copy-DbaExtendedStoredProcedure @splatConnection } | Should -Not -Throw
        }

        It "Should handle missing custom XPs gracefully" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
            }
            $results = Copy-DbaExtendedStoredProcedure @splatCopy
            # Results may be null if no custom XPs exist
            $results | Should -BeNullOrEmpty -Because "Test environment typically has no custom Extended Stored Procedures"
        }

        It "Should support WhatIf parameter" {
            $splatWhatIf = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                WhatIf      = $true
            }
            { Copy-DbaExtendedStoredProcedure @splatWhatIf } | Should -Not -Throw
        }
    }
}
