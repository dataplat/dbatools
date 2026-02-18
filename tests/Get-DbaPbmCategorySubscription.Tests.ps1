#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmCategorySubscription",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because working with policies is not supported.

    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Create a test policy category and subscribe a database to it
        $categoryId = $server.ConnectionContext.ExecuteScalar("
            DECLARE @category_id INT
            EXEC msdb.dbo.sp_syspolicy_add_policy_category @name=N'dbatoolsci_TestCategory', @mandate_database_subscriptions=0, @policy_category_id=@category_id OUTPUT
            SELECT @category_id
        ")

        $subscriptionId = $server.ConnectionContext.ExecuteScalar("
            DECLARE @subscription_id INT
            EXEC msdb.dbo.sp_syspolicy_add_policy_category_subscription @target_type=N'DATABASE', @target_object=N'master', @policy_category=N'dbatoolsci_TestCategory', @policy_category_subscription_id=@subscription_id OUTPUT
            SELECT @subscription_id
        ")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_policy_category_subscription @policy_category_subscription_id=$subscriptionId")
        $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_policy_category @policy_category_id=$categoryId")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "Gets Results" {
            $results = Get-DbaPbmCategorySubscription -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Dmf.PolicyCategorySubscription]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "PolicyCategory",
                "Target",
                "TargetType",
                "ID",
                "State",
                "IdentityKey",
                "Metadata",
                "KeyChain"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Dmf\.PolicyCategorySubscription"
        }
    }
}