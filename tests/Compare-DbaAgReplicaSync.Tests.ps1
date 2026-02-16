#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaSync",
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
                "AvailabilityGroup",
                "Exclude",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When comparing sync across AG replicas" {
        BeforeAll {
            $splatCompare = @{
                SqlInstance       = $TestConfig.instance1
                AvailabilityGroup = "AG01"
            }
            $results = Compare-DbaAgReplicaSync @splatCompare -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results for the availability group" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return results with the correct availability group name" {
            $results[0].AvailabilityGroup | Should -Be "AG01"
        }

        It "Should have valid Status values" {
            $results.Status | ForEach-Object { $PSItem | Should -BeIn @("Missing", "Different") }
        }

        It "Should have valid ObjectType values" {
            $validTypes = @("Login", "AgentJob", "Credential", "LinkedServer", "AgentOperator", "AgentAlert", "AgentProxy", "CustomError")
            $results.ObjectType | ForEach-Object { $PSItem | Should -BeIn $validTypes }
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
                "AvailabilityGroup",
                "Replica",
                "ObjectType",
                "ObjectName",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            foreach ($prop in $expectedProperties) {
                $prop | Should -BeIn $actualProperties
            }
        }

        It "Should have PropertyDifferences on Login-type output" {
            $loginOutput = $global:dbatoolsciOutput | Where-Object ObjectType -eq "Login"
            if ($loginOutput) {
                $loginOutput[0].PSObject.Properties.Name | Should -Contain "PropertyDifferences"
            } else {
                Set-ItResult -Skipped -Because "no Login-type differences were detected"
            }
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
