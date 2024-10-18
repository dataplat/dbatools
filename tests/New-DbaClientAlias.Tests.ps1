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
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Should have ServerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have Alias as a parameter" {
            $CommandUnderTest | Should -HaveParameter Alias -Type System.String
        }
        It "Should have Protocol as a parameter" {
            $CommandUnderTest | Should -HaveParameter Protocol -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
