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
        It "Successfully copies a mirroring endpoint" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $endpointName
            }
            $results = Copy-DbaEndpoint @splatCopy -OutVariable "global:dbatoolsciOutput"
            $results.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $results.Status | Should -Be "Successful"
            $results.Name | Should -Be $endpointName
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}