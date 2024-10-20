param($ModuleName = 'dbatools')

Describe "Get-DbaPbmCategory" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmCategory
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Category",
            "InputObject",
            "ExcludeSystemObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaPbmCategory -SqlInstance $global:instance2
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -Category" {
        BeforeAll {
            $results = Get-DbaPbmCategory -SqlInstance $global:instance2 -Category 'Availability database errors'
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -ExcludeSystemObject" {
        BeforeAll {
            $results = Get-DbaPbmCategory -SqlInstance $global:instance2 -ExcludeSystemObject
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
