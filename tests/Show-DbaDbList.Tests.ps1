param($ModuleName = 'dbatools')

Describe "Show-DbaDbList" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Show-DbaDbList
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Title as a parameter" {
            $CommandUnderTest | Should -HaveParameter Title
        }
        It "Should have Header as a parameter" {
            $CommandUnderTest | Should -HaveParameter Header
        }
        It "Should have DefaultDb as a parameter" {
            $CommandUnderTest | Should -HaveParameter DefaultDb
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        Context "Connects and shows database list" -ForEach $global:instance1, $global:instance2 {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $_
            }

            It "Shows database list for server $_" {
                $result = Show-DbaDbList -SqlInstance $server
                $result | Should -Not -BeNullOrEmpty
                $result.GetType().Name | Should -Be 'String'
            }

            It "Shows database list with custom title" {
                $customTitle = "Custom Database List"
                $result = Show-DbaDbList -SqlInstance $server -Title $customTitle
                $result | Should -Match $customTitle
            }

            It "Shows database list with custom header" {
                $customHeader = "Custom Header"
                $result = Show-DbaDbList -SqlInstance $server -Header $customHeader
                $result | Should -Match $customHeader
            }

            It "Shows database list with default database highlighted" {
                $defaultDb = $server.Databases[0].Name
                $result = Show-DbaDbList -SqlInstance $server -DefaultDb $defaultDb
                $result | Should -Match $defaultDb
            }
        }
    }
}
