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

            $null = Set-DbatoolsInsecureConnection
            Get-DbatoolsConfigValue -FullName "sql.connection.trustcert" | Should -BeTrue
            Get-DbatoolsConfigValue -FullName "sql.connection.encrypt" | Should -BeFalse
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Reset to known state
            Set-DbatoolsConfig -FullName "sql.connection.trustcert" -Value $false -Register
            Set-DbatoolsConfig -FullName "sql.connection.encrypt" -Value $true -Register
            $result = Set-DbatoolsInsecureConnection -SessionOnly
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Dataplat.Dbatools.Configuration.Config]
        }

        It "Returns exactly two configuration objects" {
            $result | Should -HaveCount 2
        }

        It "Returns configuration objects for sql.connection.trustcert and sql.connection.encrypt" {
            $configNames = $result | ForEach-Object { "$($_.Module).$($_.Name)" }
            $configNames | Should -Contain "sql.connection.trustcert"
            $configNames | Should -Contain "sql.connection.encrypt"
        }

        It "Has the expected properties on each configuration object" {
            $expectedProps = @(
                'Module',
                'Name',
                'Value',
                'Description'
            )
            foreach ($config in $result) {
                $actualProps = $config.PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in configuration object"
                }
            }
        }

        It "Sets trustcert to true and encrypt to false" {
            $trustcertConfig = $result | Where-Object { $_.Name -eq "connection.trustcert" }
            $encryptConfig = $result | Where-Object { $_.Name -eq "connection.encrypt" }
            $trustcertConfig.Value | Should -BeTrue
            $encryptConfig.Value | Should -BeFalse
        }
    }
}