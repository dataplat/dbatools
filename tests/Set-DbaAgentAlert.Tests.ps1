#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentAlert",
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
                "Alert",
                "NewName",
                "Enabled",
                "Disabled",
                "Force",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatConnection = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = "master"
        }
        $server = Connect-DbaInstance @splatConnection
        $server.Query("EXEC msdb.dbo.sp_add_alert @name=N'dbatoolsci test alert',@message_id=0,@severity=6,@enabled=1,@delay_between_responses=0,@include_event_description_in=0,@category_name=N'[Uncategorized]',@job_id=N'00000000-0000-0000-0000-000000000000'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatConnection = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = "master"
        }
        $server = Connect-DbaInstance @splatConnection
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'dbatoolsci test alert NEW'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When modifying agent alerts" {
        It "Changes alert to disabled" {
            $splatDisable = @{
                SqlInstance = $TestConfig.InstanceSingle
                Alert       = "dbatoolsci test alert"
                Disabled    = $true
            }
            $results = Set-DbaAgentAlert @splatDisable
            $results.IsEnabled | Should -Be "False"
        }

        It "Changes alert name to new name" {
            $splatRename = @{
                SqlInstance = $TestConfig.InstanceSingle
                Alert       = "dbatoolsci test alert"
                NewName     = "dbatoolsci test alert NEW"
            }
            $results = Set-DbaAgentAlert @splatRename
            $results.Name | Should -Be "dbatoolsci test alert NEW"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $splatOutputTest = @{
                SqlInstance = $TestConfig.InstanceSingle
                Alert       = "dbatoolsci test alert NEW"
                Enabled     = $true
            }
            $outputResult = Set-DbaAgentAlert @splatOutputTest
        }

        It "Returns output of the expected type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Alert"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "SqlInstance",
                "InstanceName",
                "Name",
                "ID",
                "JobName",
                "AlertType",
                "CategoryName",
                "Severity",
                "MessageId",
                "IsEnabled",
                "DelayBetweenResponses",
                "LastRaised",
                "OccurrenceCount"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}