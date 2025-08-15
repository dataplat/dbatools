#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbServiceBrokerService",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $procname = "dbatools_$(Get-Random)"
        $server.Query("CREATE PROCEDURE $procname AS SELECT 1", "tempdb")
        $queuename = "dbatools_$(Get-Random)"
        $server.Query("CREATE QUEUE $queuename WITH STATUS = ON , RETENTION = OFF , ACTIVATION (  STATUS = ON , PROCEDURE_NAME = $procname , MAX_QUEUE_READERS = 1 , EXECUTE AS OWNER  ), POISON_MESSAGE_HANDLING (STATUS = ON)", "tempdb")
        $servicename = "dbatools_$(Get-Random)"
        $server.Query("CREATE SERVICE $servicename ON QUEUE $queuename ([DEFAULT])", "tempdb")
    }

    AfterAll {
        try {
            $null = $server.Query("DROP SERVICE $servicename", "tempdb")
            $null = $server.Query("DROP QUEUE $queuename", "tempdb")
            $null = $server.Query("DROP PROCEDURE $procname", "tempdb")
        } catch {
            # Suppress errors during cleanup
        }
    }

    Context "Gets the service broker service" {
        BeforeAll {
            $splatServiceBroker = @{
                SqlInstance          = $TestConfig.instance2
                Database          = "tempdb"
                ExcludeSystemService             = $true
            }
            $results = Get-DbaDbServiceBrokerService @splatServiceBroker
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $servicename" {
            $results.Name | Should -BeExactly $servicename
        }

        It "Should have an owner of dbo" {
            $results.Owner | Should -BeExactly "dbo"
        }

        It "Should have a queuename of $queuename" {
            $results.QueueName | Should -BeExactly $queuename
        }
    }
}