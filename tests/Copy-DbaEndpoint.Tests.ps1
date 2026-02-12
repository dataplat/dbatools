#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaEndpoint",
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
                "Endpoint",
                "ExcludeEndpoint",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Explain what needs to be set up for the test:
        # To test copying endpoints, we need to create a test endpoint on the source instance.

        # Set variables. They are available in all the It blocks.
        $endpointName = "dbatoolsci_MirroringEndpoint"
        $endpointPort = 5022

        # Create the objects.
        $splatEndpoint = @{
            SqlInstance     = $TestConfig.InstanceCopy1
            Name            = $endpointName
            Type            = "DatabaseMirroring"
            Port            = $endpointPort
            Owner           = "sa"
            EnableException = $true
        }
        $null = New-DbaEndpoint @splatEndpoint

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying endpoints between instances" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any leftover test endpoint on destination using T-SQL to avoid ShouldProcess issues
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "IF EXISTS (SELECT 1 FROM sys.endpoints WHERE name = 'Hadr_endpoint') DROP ENDPOINT [Hadr_endpoint]" -ErrorAction SilentlyContinue

            # Copy the Hadr_endpoint for output validation
            $splatOutputCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = "Hadr_endpoint"
            }
            $script:outputForValidation = Copy-DbaEndpoint @splatOutputCopy

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # Clean up copied endpoint on destination using T-SQL to avoid ShouldProcess issues
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "IF EXISTS (SELECT 1 FROM sys.endpoints WHERE name = 'Hadr_endpoint') DROP ENDPOINT [Hadr_endpoint]" -ErrorAction SilentlyContinue
        }

        It "Successfully copies a mirroring endpoint" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $endpointName
            }
            $results = Copy-DbaEndpoint @splatCopy
            $results.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $results.Status | Should -Be "Successful"
            $results.Name | Should -Be $endpointName
        }

        It "Returns output with the expected TypeName" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:outputForValidation[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $script:outputForValidation[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has correct property values" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:outputForValidation[0].Type | Should -Be "Endpoint"
            $script:outputForValidation[0].Name | Should -Not -BeNullOrEmpty
            $script:outputForValidation[0].SourceServer | Should -Not -BeNullOrEmpty
            $script:outputForValidation[0].DestinationServer | Should -Not -BeNullOrEmpty
        }
    }
}
