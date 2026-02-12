#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaClientAlias",
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
    BeforeAll {
        $newAlias = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias -Verbose:$false
    }

    AfterAll {
        $newAlias | Remove-DbaClientAlias -ErrorAction SilentlyContinue
    }

    Context "gets the alias" {
        BeforeAll {
            $results = Get-DbaClientAlias
        }

        It "returns accurate information" {
            $results.AliasName -contains "dbatoolscialias" | Should -Be $true
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "NetworkLibrary",
                "ServerName",
                "AliasName",
                "AliasString",
                "Architecture"
            )
            foreach ($prop in $expectedProps) {
                $results[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}