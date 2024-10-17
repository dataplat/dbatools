param($ModuleName = 'dbatools')

Describe "New-DbaClientAlias" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaClientAlias
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have ServerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerName -Type DbaInstanceParameter
        }
        It "Should have Alias as a parameter" {
            $CommandUnderTest | Should -HaveParameter Alias -Type String
        }
        It "Should have Protocol as a parameter" {
            $CommandUnderTest | Should -HaveParameter Protocol -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Functionality" -Tag "IntegrationTests" {
        It "adds the alias" {
            $results = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias-new -Verbose:$false
            $results.AliasName | Should -Be @('dbatoolscialias-new', 'dbatoolscialias-new')
            $results | Remove-DbaClientAlias
        }
    }
}
