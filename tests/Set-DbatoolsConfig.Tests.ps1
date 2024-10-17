param($ModuleName = 'dbatools')

Describe "Set-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbatoolsConfig
        }
        It "Should have FullName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FullName -Type String -Not -Mandatory
        }
        It "Should have Module as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Module -Type String -Not -Mandatory
        }
        It "Should have Name as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
        }
        It "Should have Value as a non-mandatory Object parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type Object -Not -Mandatory
        }
        It "Should have PersistedValue as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter PersistedValue -Type String -Not -Mandatory
        }
        It "Should have PersistedType as a non-mandatory ConfigurationValueType parameter" {
            $CommandUnderTest | Should -HaveParameter PersistedType -Type ConfigurationValueType -Not -Mandatory
        }
        It "Should have Description as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Description -Type String -Not -Mandatory
        }
        It "Should have Validation as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Validation -Type String -Not -Mandatory
        }
        It "Should have Handler as a non-mandatory ScriptBlock parameter" {
            $CommandUnderTest | Should -HaveParameter Handler -Type ScriptBlock -Not -Mandatory
        }
        It "Should have Hidden as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Hidden -Type Switch -Not -Mandatory
        }
        It "Should have Default as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Default -Type Switch -Not -Mandatory
        }
        It "Should have Initialize as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Initialize -Type Switch -Not -Mandatory
        }
        It "Should have SimpleExport as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter SimpleExport -Type Switch -Not -Mandatory
        }
        It "Should have ModuleExport as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter ModuleExport -Type Switch -Not -Mandatory
        }
        It "Should have DisableValidation as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter DisableValidation -Type Switch -Not -Mandatory
        }
        It "Should have DisableHandler as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter DisableHandler -Type Switch -Not -Mandatory
        }
        It "Should have PassThru as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter PassThru -Type Switch -Not -Mandatory
        }
        It "Should have Register as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Register -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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
