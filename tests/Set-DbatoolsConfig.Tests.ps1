param($ModuleName = 'dbatools')

Describe "Set-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbatoolsConfig
        }
        It "Should have FullName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter FullName -Type System.String -Mandatory:$false
        }
        It "Should have Module as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Module -Type System.String -Mandatory:$false
        }
        It "Should have Name as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String -Mandatory:$false
        }
        It "Should have Value as a non-mandatory System.Object parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type System.Object -Mandatory:$false
        }
        It "Should have PersistedValue as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter PersistedValue -Type System.String -Mandatory:$false
        }
        It "Should have PersistedType as a non-mandatory Dataplat.Dbatools.Configuration.ConfigurationValueType parameter" {
            $CommandUnderTest | Should -HaveParameter PersistedType -Type Dataplat.Dbatools.Configuration.ConfigurationValueType -Mandatory:$false
        }
        It "Should have Description as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Description -Type System.String -Mandatory:$false
        }
        It "Should have Validation as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Validation -Type System.String -Mandatory:$false
        }
        It "Should have Handler as a non-mandatory System.Management.Automation.ScriptBlock parameter" {
            $CommandUnderTest | Should -HaveParameter Handler -Type System.Management.Automation.ScriptBlock -Mandatory:$false
        }
        It "Should have Hidden as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Hidden -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Default as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Default -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Initialize as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Initialize -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have SimpleExport as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter SimpleExport -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have ModuleExport as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleExport -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have DisableValidation as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableValidation -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have DisableHandler as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableHandler -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have PassThru as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter PassThru -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Register as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Register -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.Switch -Mandatory:$false
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
