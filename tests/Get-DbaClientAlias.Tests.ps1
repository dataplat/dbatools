param($ModuleName = 'dbatools')

Describe "Get-DbaClientAlias" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaClientAlias
        }

        $params = @(
            "ComputerName",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
