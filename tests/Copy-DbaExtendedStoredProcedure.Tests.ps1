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

        It "Returns output with the expected TypeName" {
            if (-not $results) { Set-ItResult -Skipped -Because "no custom Extended Stored Procedures exist to copy" }
            $results[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no custom Extended Stored Procedures exist to copy" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}
