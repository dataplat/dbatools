#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceTrigger",
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
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create unique trigger names for this test run to avoid conflicts
        $random = Get-Random
        $trigger1Name = "dbatoolsci_trigger1_$random"
        $trigger2Name = "dbatoolsci_trigger2_$random"

        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $sql1 = "CREATE TRIGGER [$trigger1Name] ON ALL SERVER FOR CREATE_DATABASE AS PRINT 'Database Created.'"
        $sql2 = "CREATE TRIGGER [$trigger2Name] ON ALL SERVER FOR CREATE_DATABASE AS PRINT 'Database Created.'"
        $instance.query($sql1)
        $instance.query($sql2)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup the created triggers
        $sql = "DROP TRIGGER [$trigger1Name] ON ALL SERVER;DROP TRIGGER [$trigger2Name] ON ALL SERVER"
        $instance.query($sql)
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When retrieving instance triggers" {
        BeforeAll {
            $results = Get-DbaInstanceTrigger -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should return the expected number of triggers" {
            $results.Count | Should -BeGreaterOrEqual 2
        }

        It "Should have correct properties" {
            $expectedProperties = @(
                "AnsiNullsStatus", "AssemblyName", "BodyStartIndex", "ClassName", "ComputerName",
                "CreateDate", "DatabaseEngineEdition", "DatabaseEngineType", "DateLastModified",
                "DdlTriggerEvents", "ExecutionContext", "ExecutionContextLogin", "ExecutionManager",
                "ID", "ImplementationType", "InstanceName", "IsDesignMode", "IsEnabled", "IsEncrypted",
                "IsSystemObject", "MethodName", "Name", "Parent", "ParentCollection", "Properties",
                "QuotedIdentifierStatus", "ServerVersion", "SqlInstance", "State", "Text", "TextBody",
                "TextHeader", "TextMode", "Urn", "UserData"
            )
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProperties | Sort-Object)
        }

        It "Should return our test triggers" {
            $triggerNames = $results | Where-Object Name -in $trigger1Name, $trigger2Name
            $triggerNames.Count | Should -BeExactly 2
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.ServerDdlTrigger"
        }

        It "Has the expected default display properties" {
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName", "InstanceName", "SqlInstance", "ID", "Name",
                "AnsiNullsStatus", "AssemblyName", "BodyStartIndex", "ClassName",
                "CreateDate", "DateLastModified", "DdlTriggerEvents", "ExecutionContext",
                "ExecutionContextLogin", "ImplementationType", "IsDesignMode", "IsEnabled",
                "IsEncrypted", "IsSystemObject", "MethodName", "QuotedIdentifierStatus",
                "State", "TextHeader", "TextMode"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}