#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaResourceGovernor",
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
                "Enabled",
                "Disabled",
                "ClassifierFunction",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $classifierFunction = "dbatoolsci_fnRGClassifier"
            $qualifiedClassifierFunction = "[dbo].[$classifierFunction]"

            $createUDFQuery = "CREATE FUNCTION $classifierFunction()
            RETURNS SYSNAME
            WITH SCHEMABINDING
            AS
            BEGIN
            RETURN DB_NAME();
            END;"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $createUDFQuery -Database "master"
            Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -Disabled

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "enables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -Enabled -OutVariable "global:dbatoolsciOutput"
            $results.Enabled | Should -Be $true
        }

        It "disables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -Disabled
            $results.Enabled | Should -Be $false
        }

        It "modifies resource governor classifier function" {
            $results = Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -ClassifierFunction $classifierFunction
            $results.ClassifierFunction | Should -Be $qualifiedClassifierFunction
        }

        It "removes resource governor classifier function" {
            $results = Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -ClassifierFunction "NULL"
            $results.ClassifierFunction | Should -Be ""
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dropUDFQuery = "DROP FUNCTION $qualifiedClassifierFunction;"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $dropUDFQuery -Database "master" -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ResourceGovernor]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ClassifierFunction",
                "Enabled",
                "MaxOutstandingIOPerVolume",
                "ReconfigurePending",
                "ResourcePools",
                "ExternalResourcePools"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ResourceGovernor"
        }
    }
}