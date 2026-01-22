#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentAlert",
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
                "ExcludeAlert",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatAddAlert = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = "master"
        }
        $server = Connect-DbaInstance @splatAddAlert
        $server.Query("EXEC msdb.dbo.sp_add_alert @name=N'dbatoolsci test alert',@message_id=0,@severity=6,@enabled=1,@delay_between_responses=0,@include_event_description_in=0,@category_name=N'[Uncategorized]',@job_id=N'00000000-0000-0000-0000-000000000000'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatDeleteAlert = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = "master"
        }
        $server = Connect-DbaInstance @splatDeleteAlert
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'dbatoolsci test alert'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When getting agent alerts" {
        It "Gets the newly created alert" {
            $results = Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceSingle
            $results.Name | Should -Contain "dbatoolsci test alert"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceSingle -EnableException
            $firstResult = $result | Where-Object { $_.Name -eq "dbatoolsci test alert" } | Select-Object -First 1
        }

        It "Returns the documented output type" {
            $firstResult | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Alert]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'SqlInstance',
                'InstanceName',
                'Name',
                'ID',
                'JobName',
                'AlertType',
                'CategoryName',
                'Severity',
                'MessageId',
                'IsEnabled',
                'DelayBetweenResponses',
                'LastRaised',
                'OccurrenceCount'
            )
            $actualProps = $firstResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the custom properties added by dbatools" {
            $firstResult.PSObject.Properties.Name | Should -Contain 'ComputerName' -Because "ComputerName is added by dbatools"
            $firstResult.PSObject.Properties.Name | Should -Contain 'InstanceName' -Because "InstanceName is added by dbatools"
            $firstResult.PSObject.Properties.Name | Should -Contain 'SqlInstance' -Because "SqlInstance is added by dbatools"
            $firstResult.PSObject.Properties.Name | Should -Contain 'Notifications' -Because "Notifications is added by dbatools"
            $firstResult.PSObject.Properties.Name | Should -Contain 'LastRaised' -Because "LastRaised is added by dbatools"
        }

        It "Has LastRaised property of correct type" {
            # LastRaised should be of type dbadatetime or $null if never raised
            if ($null -ne $firstResult.LastRaised) {
                $firstResult.LastRaised.GetType().Name | Should -BeIn @('DbaDateTime', 'DBNull')
            }
        }
    }
}