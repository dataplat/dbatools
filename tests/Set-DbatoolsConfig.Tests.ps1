param($ModuleName = 'dbatools')

Describe "Set-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbatoolsConfig
        }
        It "Should have FullName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter FullName
        }
        It "Should have Module as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Module
        }
        It "Should have Name as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Value as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Value
        }
        It "Should have PersistedValue as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PersistedValue
        }
        It "Should have PersistedType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PersistedType
        }
        It "Should have Description as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Description
        }
        It "Should have Validation as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Validation
        }
        It "Should have Handler as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Handler
        }
        It "Should have Hidden as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Hidden
        }
        It "Should have Default as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Default
        }
        It "Should have Initialize as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Initialize
        }
        It "Should have SimpleExport as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SimpleExport
        }
        It "Should have ModuleExport as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleExport
        }
        It "Should have DisableValidation as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DisableValidation
        }
        It "Should have DisableHandler as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DisableHandler
        }
        It "Should have PassThru as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PassThru
        }
        It "Should have Register as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Register
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Set-DbatoolsConfig Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    It "impacts the connection timeout" {
        $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 60
        $results = New-DbaConnectionString -SqlInstance test -Database dbatools -ConnectTimeout ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
        $results | Should -Match 'Connect Timeout=60'
    }
}
