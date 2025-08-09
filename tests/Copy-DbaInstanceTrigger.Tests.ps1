#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "ServerTrigger",
                "ExcludeServerTrigger",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set variables. They are available in all the It blocks.
        $triggerName = "dbatoolsci-trigger"
        $sql         = "CREATE TRIGGER [$triggerName] -- Trigger name
                ON ALL SERVER FOR LOGON -- Tells you it's a logon trigger
                AS
                PRINT 'hello'"

        # Create the server trigger on the source instance.
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $sourceServer.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $sourceServer.Query("DROP TRIGGER [$triggerName] ON ALL SERVER")

        try {
            $destServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $destServer.Query("DROP TRIGGER [$triggerName] ON ALL SERVER")
        } catch {
            # Ignore cleanup errors
        }

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When copying server triggers between instances" {
        BeforeAll {
            $splatCopy = @{
                Source        = $TestConfig.instance1
                Destination   = $TestConfig.instance2
                WarningAction = "SilentlyContinue"
            }
            $results = Copy-DbaInstanceTrigger @splatCopy
        }

        It "Should report successful copy operation" {
            $results.Status | Should -BeExactly "Successful"
        }
    }
}
