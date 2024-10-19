param($ModuleName = 'dbatools')

Describe "Get-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsConfig
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "FullName",
                "Name",
                "Module",
                "Force"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Returns proper information" {
            $results = Get-DbatoolsConfig -FullName sql.connection.timeout
            $results.Value | Should -BeOfType [System.Int32]
        }
    }
}
