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
            $CommandUnderTest | Should -HaveParameter Source
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Project parameter" {
            $CommandUnderTest | Should -HaveParameter Project
        }
        It "Should have Folder parameter" {
            $CommandUnderTest | Should -HaveParameter Folder
        }
        It "Should have Environment parameter" {
            $CommandUnderTest | Should -HaveParameter Environment
        }
        It "Should have CreateCatalogPassword parameter" {
            $CommandUnderTest | Should -HaveParameter CreateCatalogPassword
        }
        It "Should have EnableSqlClr parameter" {
            $CommandUnderTest | Should -HaveParameter EnableSqlClr
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
