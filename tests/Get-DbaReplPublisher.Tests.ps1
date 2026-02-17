#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplPublisher",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

# Check if replication is configured before discovery - Pester 5 evaluates -Skip during discovery before BeforeAll runs
$global:skipRepl = -not (Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle).IsDistributor

Describe $CommandName -Tag IntegrationTests {
    Context "When getting publisher information" -Skip:$global:skipRepl {
        It "Should return publisher information" {
            $result = Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.PublisherType | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Replication.DistributionPublisher]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Status",
                "WorkingDirectory",
                "DistributionDatabase",
                "DistributionPublications",
                "PublisherType",
                "Name"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Replication\.DistributionPublisher"
        }
    }
}