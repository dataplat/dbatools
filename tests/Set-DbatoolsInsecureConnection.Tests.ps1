param($ModuleName = 'dbatools')

Describe "Set-DbatoolsInsecureConnection" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbatoolsInsecureConnection
        }
        It "Should have SessionOnly as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter SessionOnly -Type Switch -Not -Mandatory
        }
        It "Should have Scope as a non-mandatory ConfigScope parameter" {
            $CommandUnderTest | Should -HaveParameter Scope -Type ConfigScope -Not -Mandatory
        }
        It "Should have Register as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Register -Type Switch -Not -Mandatory
        }
        It "Should have Verbose as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
        }
        It "Should have Debug as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
        }
        It "Should have ErrorAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Should have WarningVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Should have InformationVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Should have OutVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Should have OutBuffer as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Should have PipelineVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Set defaults just for this session
            Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $false -Register
            Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $true -Register
        }

        It "Should set the default connection settings to trust all server certificates and not require encrypted connections" {
            $trustcert = Get-DbatoolsConfigValue -FullName sql.connection.trustcert
            $encrypt = Get-DbatoolsConfigValue -FullName sql.connection.encrypt
            $trustcert | Should -BeFalse
            $encrypt | Should -BeTrue

            $null = Set-DbatoolsInsecureConnection
            Get-DbatoolsConfigValue -FullName sql.connection.trustcert | Should -BeTrue
            Get-DbatoolsConfigValue -FullName sql.connection.encrypt | Should -BeFalse
        }
    }
}
