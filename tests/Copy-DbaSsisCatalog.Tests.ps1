param($ModuleName = 'dbatools')

Describe "Copy-DbaSsisCatalog" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaSsisCatalog
        }
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Project parameter" {
            $CommandUnderTest | Should -HaveParameter Project -Type System.String
        }
        It "Should have Folder parameter" {
            $CommandUnderTest | Should -HaveParameter Folder -Type System.String
        }
        It "Should have Environment parameter" {
            $CommandUnderTest | Should -HaveParameter Environment -Type System.String
        }
        It "Should have CreateCatalogPassword parameter" {
            $CommandUnderTest | Should -HaveParameter CreateCatalogPassword -Type System.Security.SecureString
        }
        It "Should have EnableSqlClr parameter" {
            $CommandUnderTest | Should -HaveParameter EnableSqlClr -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
