#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaClientAlias",
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
                "ServerName",
                "Alias",
                "Protocol",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When creating client alias" {
        AfterAll {
            # Cleanup - Remove any aliases that may have been created
            Get-DbaClientAlias | Remove-DbaClientAlias
        }

        It "Returns accurate information when creating alias" {
            $aliasName = "dbatoolscialias-new"
            $serverName = "sql2016"
            $results = New-DbaClientAlias -ServerName $serverName -Alias $aliasName -Verbose:$false
            $results.AliasName | Should -Be $aliasName, $aliasName
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $aliasName = "dbatoolscialias-output"
            $serverName = "sql2016"
            $result = New-DbaClientAlias -ServerName $serverName -Alias $aliasName -EnableException
        }

        AfterAll {
            # Cleanup
            Get-DbaClientAlias | Where-Object AliasName -eq "dbatoolscialias-output" | Remove-DbaClientAlias
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "NetworkLibrary",
                "ServerName",
                "AliasName",
                "AliasString",
                "Architecture"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}