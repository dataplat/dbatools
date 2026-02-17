#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmCategory",
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
                "Category",
                "InputObject",
                "ExcludeSystemObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because working with policies is not supported.

    Context "Command actually works" {
        It "Gets Results" {
            $results = Get-DbaPbmCategory -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -Category" {
        It "Gets Results" {
            $results = Get-DbaPbmCategory -SqlInstance $TestConfig.InstanceSingle -Category "Availability database errors"
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -ExcludeSystemObject" {
        It "Gets Results" {
            $results = Get-DbaPbmCategory -SqlInstance $TestConfig.InstanceSingle -ExcludeSystemObject
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Dmf.PolicyCategory]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Name",
                "MandateDatabaseSubscriptions"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Sdk\.Sfc\.ISfcInstance"
        }
    }
}