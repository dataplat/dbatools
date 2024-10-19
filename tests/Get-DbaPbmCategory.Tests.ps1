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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have ExcludeSystemObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
