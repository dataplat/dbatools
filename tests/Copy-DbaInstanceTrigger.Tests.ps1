#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaInstanceTrigger" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaInstanceTrigger
            $expected = $TestConfig.CommonParameters
            $expected += @(
                'Source',
                'SourceSqlCredential',
                'Destination', 
                'DestinationSqlCredential',
                'ServerTrigger',
                'ExcludeServerTrigger',
                'Force',
                'EnableException',
                'Confirm',
                'WhatIf'
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasParams = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasParams | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaInstanceTrigger" -Tag "IntegrationTests" {
    BeforeAll {
        $triggerName = "dbatoolsci-trigger"
        $sql = "CREATE TRIGGER [$triggerName] -- Trigger name
                ON ALL SERVER FOR LOGON -- Tells you it's a logon trigger
                AS
                PRINT 'hello'"
        
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $sourceServer.Query($sql)
    }

    AfterAll {
        $sourceServer.Query("DROP TRIGGER [$triggerName] ON ALL SERVER")

        try {
            $destServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $destServer.Query("DROP TRIGGER [$triggerName] ON ALL SERVER")
        } catch {
            # Ignore cleanup errors
        }
    }

    Context "When copying server triggers between instances" {
        BeforeAll {
            $results = Copy-DbaInstanceTrigger -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -WarningAction SilentlyContinue
        }

        It "Should report successful copy operation" {
            $results.Status | Should -BeExactly "Successful"
        }
    }
}
