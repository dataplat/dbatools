param($ModuleName = 'dbatools')

Describe "Get-DbatoolsPath" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsPath
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "Name",
                "SqlInstance",
                "SqlCredential"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}
