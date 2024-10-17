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
        It "Should have Options as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Options -Type String[] -Mandatory:$false
        }
        It "Should have NoDefaults as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoDefaults -Type Switch -Mandatory:$false
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
