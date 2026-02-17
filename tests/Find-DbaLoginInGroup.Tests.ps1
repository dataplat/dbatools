#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaLoginInGroup",
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
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When enumerating AD group logins" {
        It "Should return results from a SQL instance" {
            $results = Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue -OutVariable "global:dbatoolsciOutput"
            if (-not $results) {
                Set-ItResult -Skipped -Because "no AD group logins found on test instance"
                return
            }
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $expectedProperties = @(
                "SqlInstance",
                "InstanceName",
                "ComputerName",
                "Login",
                "DisplayName",
                "MemberOf",
                "ParentADGroupLogin"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $expectedColumns = @(
                "SqlInstance",
                "Login",
                "DisplayName",
                "MemberOf",
                "ParentADGroupLogin"
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
