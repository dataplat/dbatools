#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbatoolsInsecureConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Register",
                "SessionOnly",
                "Scope"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}


Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeEach {
            # Set defaults just for this session
            Set-DbatoolsConfig -FullName "sql.connection.trustcert" -Value $false -Register
            Set-DbatoolsConfig -FullName "sql.connection.encrypt" -Value $true -Register
        }

        It "Should set the default connection settings to trust all server certificates and not require encrypted connections" {
            $trustcert = Get-DbatoolsConfigValue -FullName "sql.connection.trustcert"
            $encrypt = Get-DbatoolsConfigValue -FullName "sql.connection.encrypt"
            $trustcert | Should -BeFalse
            $encrypt | Should -BeTrue

            $null = Set-DbatoolsInsecureConnection -OutVariable "global:dbatoolsciOutput"
            Get-DbatoolsConfigValue -FullName "sql.connection.trustcert" | Should -BeTrue
            Get-DbatoolsConfigValue -FullName "sql.connection.encrypt" | Should -BeFalse
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Dataplat.Dbatools.Configuration.Config]
        }

        It "Should return two configuration objects" {
            $global:dbatoolsciOutput.Count | Should -Be 2
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Description",
                "FullName",
                "Handler",
                "Hidden",
                "Initialized",
                "Module",
                "ModuleExport",
                "Name",
                "PolicyEnforced",
                "PolicySet",
                "RegistryData",
                "SafeValue",
                "SimpleExport",
                "Type",
                "Unchanged",
                "Validation",
                "Value"
            )
            $actualProperties = ($global:dbatoolsciOutput[0].PSObject.Properties.Name | Sort-Object)
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Dataplat\.Dbatools\.Configuration\.Config"
        }
    }
}