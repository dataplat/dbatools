#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentOperator",
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
                "Operator",
                "ExcludeOperator",
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
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
        $server.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $server.Query($sql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Get back some operators" {
        It "return at least two results" {
            $results = Get-DbaAgentOperator -SqlInstance $TestConfig.InstanceSingle
            $results.Count -ge 2 | Should -Be $true
        }

        It "return one result" {
            $results = Get-DbaAgentOperator -SqlInstance $TestConfig.InstanceSingle -Operator dbatoolsci_operator
            $results.Count | Should -BeExactly 1
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaAgentOperator -SqlInstance $TestConfig.InstanceSingle -Operator dbatoolsci_operator -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Operator]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'ID',
                'IsEnabled',
                'EmailAddress',
                'LastEmail'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the RelatedJobs property added by dbatools" {
            $result.PSObject.Properties.Name | Should -Contain 'RelatedJobs' -Because "dbatools adds this property via Add-Member"
        }

        It "Has the RelatedAlerts property added by dbatools" {
            $result.PSObject.Properties.Name | Should -Contain 'RelatedAlerts' -Because "dbatools adds this property via Add-Member"
        }

        It "Has the AlertLastEmail property added by dbatools" {
            $result.PSObject.Properties.Name | Should -Contain 'AlertLastEmail' -Because "dbatools adds this property via Add-Member"
        }
    }
}