param($ModuleName = 'dbatools')

Describe "Update-DbaBuildReference" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Update-DbaBuildReference
        }
        $params = @(
            "LocalFile",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Functionality" {
        It "calls the internal function" {
            BeforeAll {
                function Get-DbaBuildReferenceIndexOnline { }
                Mock Get-DbaBuildReferenceIndexOnline -ModuleName $ModuleName
            }
            { Update-DbaBuildReference -EnableException } | Should -Not -Throw
            Should -Invoke Get-DbaBuildReferenceIndexOnline -ModuleName $ModuleName -Times 1 -Exactly
        }

        It "errors out when cannot download" {
            BeforeAll {
                Mock Get-DbaBuildReferenceIndexOnline -MockWith { throw "cannot download" } -ModuleName $ModuleName
            }
            { Update-DbaBuildReference -EnableException } | Should -Throw -ExpectedMessage "cannot download"
        }
    }
}
