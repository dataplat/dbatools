#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaReplLatency",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "PublicationName",
                "TimeToLive",
                "RetainToken",
                "DisplayTokenHistory",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" -Tag UnitTests {
        It "Has the expected output type documented" {
            $commandHelp = Get-Help $CommandName
            $commandHelp.returnValues.returnValue[0].type.name | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties documented" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'TokenID',
                'TokenCreateDate',
                'PublicationServer',
                'PublicationDB',
                'PublicationName',
                'PublicationType',
                'DistributionServer',
                'DistributionDB',
                'SubscriberServer',
                'SubscriberDB',
                'PublisherToDistributorLatency',
                'DistributorToSubscriberLatency',
                'TotalLatency'
            )
            $commandHelp = Get-Help $CommandName
            $outputSection = $commandHelp.description.Text
            foreach ($prop in $expectedProps) {
                $outputSection | Should -Match $prop -Because "property '$prop' should be documented in .OUTPUTS section"
            }
        }
    }
}