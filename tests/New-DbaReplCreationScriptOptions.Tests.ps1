param($ModuleName = 'dbatools')

Describe "New-DbaReplCreationScriptOptions" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaReplCreationScriptOptions
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "Options",
                "NoDefaults"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
