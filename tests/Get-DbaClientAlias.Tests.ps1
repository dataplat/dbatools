param($ModuleName = 'dbatools')

Describe "Get-DbaClientAlias" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaClientAlias
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            $newalias = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias -Verbose:$false
        }
        AfterAll {
            $newalias | Remove-DbaClientAlias
        }

        It "gets the alias" {
            $results = Get-DbaClientAlias
            $results.AliasName | Should -Contain 'dbatoolscialias'
        }
    }
}
