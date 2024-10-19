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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SessionOnly",
                "Scope",
                "Register"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
