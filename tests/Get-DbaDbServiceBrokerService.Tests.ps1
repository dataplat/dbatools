#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbServiceBrokerService",
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
                "Database",
                "ExcludeDatabase",
                "ExcludeSystemService",
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

        # Set up Service Broker components for testing
        $testServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $testProcName = "dbatools_{0}" -f $(Get-Random)
        $testServer.Query("CREATE PROCEDURE $testProcName AS SELECT 1", "tempdb")
        $testQueueName = "dbatools_{0}" -f $(Get-Random)
        $testServer.Query("CREATE QUEUE $testQueueName WITH STATUS = ON , RETENTION = OFF , ACTIVATION (  STATUS = ON , PROCEDURE_NAME = $testProcName , MAX_QUEUE_READERS = 1 , EXECUTE AS OWNER  ), POISON_MESSAGE_HANDLING (STATUS = ON)", "tempdb")
        $testServiceName = "dbatools_{0}" -f $(Get-Random)
        $testServer.Query("CREATE SERVICE $testServiceName ON QUEUE $testQueueName ([DEFAULT])", "tempdb")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup Service Broker components
        $null = $testServer.Query("DROP SERVICE $testServiceName", "tempdb")
        $null = $testServer.Query("DROP QUEUE $testQueueName", "tempdb")
        $null = $testServer.Query("DROP PROCEDURE $testProcName", "tempdb")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets the service broker service" {
        BeforeAll {
            $testResults = Get-DbaDbServiceBrokerService -SqlInstance $TestConfig.instance2 -Database tempdb -ExcludeSystemService:$true
        }

        It "Gets results" {
            $testResults | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $testServiceName" {
            $testResults.Name | Should -Be $testServiceName
        }


        It "Should have an owner of dbo" {
            $testResults.Owner | Should -Be "dbo"
        }

        It "Should have a queuename of $testQueueName" {
            $testResults.QueueName | Should -Be $testQueueName
        }
    }
}