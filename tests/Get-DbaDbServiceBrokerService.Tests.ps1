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
        $global:testServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:testProcName = "dbatools_{0}" -f $(Get-Random)
        $global:testServer.Query("CREATE PROCEDURE $global:testProcName AS SELECT 1", "tempdb")
        $global:testQueueName = "dbatools_{0}" -f $(Get-Random)
        $global:testServer.Query("CREATE QUEUE $global:testQueueName WITH STATUS = ON , RETENTION = OFF , ACTIVATION (  STATUS = ON , PROCEDURE_NAME = $global:testProcName , MAX_QUEUE_READERS = 1 , EXECUTE AS OWNER  ), POISON_MESSAGE_HANDLING (STATUS = ON)", "tempdb")
        $global:testServiceName = "dbatools_{0}" -f $(Get-Random)
        $global:testServer.Query("CREATE SERVICE $global:testServiceName ON QUEUE $global:testQueueName ([DEFAULT])", "tempdb")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup Service Broker components
        $null = $global:testServer.Query("DROP SERVICE $global:testServiceName", "tempdb")
        $null = $global:testServer.Query("DROP QUEUE $global:testQueueName", "tempdb")
        $null = $global:testServer.Query("DROP PROCEDURE $global:testProcName", "tempdb")
    }

    Context "Gets the service broker service" {
        BeforeAll {
            $testResults = Get-DbaDbServiceBrokerService -SqlInstance $TestConfig.instance2 -Database tempdb -ExcludeSystemService:$true
        }

        It "Gets results" {
            $testResults | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $global:testServiceName" {
            $testResults.Name | Should -Be $global:testServiceName
        }


        It "Should have an owner of dbo" {
            $testResults.Owner | Should -Be "dbo"
        }

        It "Should have a queuename of $global:testQueueName" {
            $testResults.QueueName | Should -Be $global:testQueueName
        }
    }
}