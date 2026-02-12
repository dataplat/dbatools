#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbServiceBrokerQueue",
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
                "ExcludeSystemQueue",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $procname = "dbatools_$(Get-Random)"
        $server.Query("CREATE PROCEDURE $procname AS SELECT 1", "tempdb")
        $queuename = "dbatools_$(Get-Random)"
        $server.Query("CREATE QUEUE $queuename WITH STATUS = ON , RETENTION = OFF , ACTIVATION (  STATUS = ON , PROCEDURE_NAME = $procname , MAX_QUEUE_READERS = 1 , EXECUTE AS OWNER  ), POISON_MESSAGE_HANDLING (STATUS = ON)", "tempdb")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("DROP QUEUE $queuename", "tempdb")
        $null = $server.Query("DROP PROCEDURE $procname", "tempdb")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets the service broker queue" {
        BeforeAll {
            $splatGetQueue = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Database           = "tempdb"
                ExcludeSystemQueue = $true
            }
            $results = Get-DbaDbServiceBrokerQueue @splatGetQueue
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $queuename" {
            $results.Name | Should -BeExactly $queuename
        }

        It "Should have a schema of dbo" {
            $results.Schema | Should -BeExactly "dbo"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $splatOutputQueue = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Database           = "tempdb"
                ExcludeSystemQueue = $true
            }
            $outputResult = Get-DbaDbServiceBrokerQueue @splatOutputQueue
        }

        It "Returns output of the documented type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Broker.ServiceQueue"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "QueueID", "CreateDate", "DateLastModified", "Name", "ProcedureName", "ProcedureSchema")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].psobject.Properties["QueueID"] | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.Properties["QueueID"].MemberType | Should -Be "AliasProperty"
        }
    }
}