#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaReplPublishing",
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
                "SnapshotShare",
                "PublisherSqlLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

# Check if replication is configured - set at script level so Pester v5 can evaluate -Skip during discovery
$global:skipRepl = $true
try {
    $replServer = Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle -EnableException
    $global:skipRepl = -not ($replServer.IsDistributor -and $replServer.IsPublisher)
} catch {
    $global:skipRepl = $true
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not $global:skipRepl) {
            # Disable publishing so we can re-enable it and capture the output
            $null = Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -Confirm:$false

            # Re-enable publishing and capture output
            $global:dbatoolsciOutput = Enable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $global:dbatoolsciOutput = $null
    }

    Context "Output validation" -Skip:$global:skipRepl {
        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Replication.ReplicationServer]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "IsDistributor",
                "IsPublisher",
                "DistributionServer",
                "DistributionDatabase"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Replication\.ReplicationServer"
        }
    }
}
