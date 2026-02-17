#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting SPN information" {
        BeforeAll {
            $results = Test-DbaSpn -ComputerName $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
        }

        It "Returns some results" {
            $results.RequiredSPN | Should -Not -BeNullOrEmpty
        }

        It "Has the required properties for all results" {
            foreach ($result in $results) {
                $result.RequiredSPN | Should -Match "MSSQLSvc"
                $result.TcpEnabled | Should -Be $true
                $result.IsSet | Should -BeOfType [bool]
            }
        }
    }

    Context "Output validation" {
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
                "SqlProduct",
                "InstanceServiceAccount",
                "RequiredSPN",
                "IsSet",
                "Cluster",
                "TcpEnabled",
                "Port",
                "DynamicPort",
                "Warning",
                "Error",
                "Credential"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlProduct",
                "InstanceServiceAccount",
                "RequiredSPN",
                "IsSet",
                "Cluster",
                "TcpEnabled",
                "Port",
                "DynamicPort",
                "Warning",
                "Error"
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
