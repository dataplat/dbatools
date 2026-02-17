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
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Check if replication is configured - skip all tests if not
        $replServer = Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle
        $global:skipRepl = -not $replServer.IsPublisher

        if (-not $global:skipRepl) {
            $splatLatency = @{
                SqlInstance = $TestConfig.InstanceSingle
                TimeToLive  = 30
                RetainToken = $true
            }
            $result = Test-DbaReplLatency @splatLatency -OutVariable "global:dbatoolsciOutput"
        }
    }

    Context "When testing replication latency" -Skip:$global:skipRepl {
        It "Should return results" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should have valid latency properties" {
            $result[0].PublicationServer | Should -Not -BeNullOrEmpty
            $result[0].PublicationDB | Should -Not -BeNullOrEmpty
            $result[0].PublicationName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "TokenID",
                "TokenCreateDate",
                "PublicationServer",
                "PublicationDB",
                "PublicationName",
                "PublicationType",
                "DistributionServer",
                "DistributionDB",
                "SubscriberServer",
                "SubscriberDB",
                "PublisherToDistributorLatency",
                "DistributorToSubscriberLatency",
                "TotalLatency"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "TokenID",
                "TokenCreateDate",
                "PublicationServer",
                "PublicationDB",
                "PublicationName",
                "PublicationType",
                "DistributionServer",
                "DistributionDB",
                "SubscriberServer",
                "SubscriberDB",
                "PublisherToDistributorLatency",
                "DistributorToSubscriberLatency",
                "TotalLatency"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
