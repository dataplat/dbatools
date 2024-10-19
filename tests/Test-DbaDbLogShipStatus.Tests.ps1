param($ModuleName = 'dbatools')

Describe "Test-DbaDbLogShipStatus Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandName = 'Test-DbaDbLogShipStatus'
            $CommandUnderTest = Get-Command $CommandName
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Simple as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Simple
        }
        It "Should have Primary as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Primary
        }
        It "Should have Secondary as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Secondary
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Test-DbaDbLogShipStatus Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $env:skipIntegrationTests = $false

        try {
            . "$PSScriptRoot\constants.ps1"
        } catch {
            $env:skipIntegrationTests = $true
        }
    }

    BeforeAll {
        if (-not $env:skipIntegrationTests) {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $env:skipExpressEdition = $server.Edition -notmatch 'Express'
        }
    }

    Context "When testing SQL Server Express edition" {
        It "Warns if SQL instance edition is not supported" -Skip:$env:skipIntegrationTests {
            $null = Test-DbaDbLogShipStatus -SqlInstance $global:instance1 -WarningAction SilentlyContinue -WarningVariable editionwarn
            $editionwarn | Should -Match "Express"
        }
    }

    Context "When no log shipping is found" {
        It "Warns if no log shipping found" -Skip:$env:skipIntegrationTests {
            $null = Test-DbaDbLogShipStatus -SqlInstance $global:instance2 -Database 'master' -WarningAction SilentlyContinue -WarningVariable doesntexist
            $doesntexist | Should -Match "No information available"
        }
    }
}
