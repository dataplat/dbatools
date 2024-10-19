param($ModuleName = 'dbatools')

Describe "Get-DbaClientAlias" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaClientAlias
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
