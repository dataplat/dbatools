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
            $results = Set-DbaAgentAlert @splatDisable -OutVariable "global:dbatoolsciOutput"
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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Alert]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.Alert"
        }
    }
}