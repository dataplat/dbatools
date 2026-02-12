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

        Context "Output validation" {
            BeforeAll {
                $script:outputResult = Set-DbatoolsInsecureConnection -SessionOnly
            }

            It "Returns output of the expected type" {
                $script:outputResult | Should -Not -BeNullOrEmpty
                $script:outputResult[0].psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Configuration.Config"
            }

            It "Returns two configuration objects for trustcert and encrypt" {
                @($script:outputResult).Count | Should -Be 2
                $script:outputResult.FullName | Should -Contain "sql.connection.trustcert"
                $script:outputResult.FullName | Should -Contain "sql.connection.encrypt"
            }
        }
    }
}