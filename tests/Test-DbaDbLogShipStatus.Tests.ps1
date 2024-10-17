param($ModuleName = 'dbatools')

Describe "Test-DbaDbLogShipStatus Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandName = 'Test-DbaDbLogShipStatus'
            $CommandUnderTest = Get-Command $CommandName
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[]
        }
        It "Should have Simple as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Simple -Type switch
        }
        It "Should have Primary as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Primary -Type switch
        }
        It "Should have Secondary as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Secondary -Type switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
        }
    }
}

Describe "Test-DbaDbLogShipStatus Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $script:skipIntegrationTests = $false
        $script:instance1 = $null
        $script:instance2 = $null

        try {
            . "$PSScriptRoot\constants.ps1"
            $script:instance1 = $script:instance1
            $script:instance2 = $script:instance2
        } catch {
            $script:skipIntegrationTests = $true
        }
    }

    BeforeAll {
        if (-not $script:skipIntegrationTests) {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $script:skipExpressEdition = $server.Edition -notmatch 'Express'
        }
    }

    Context "When testing SQL Server Express edition" {
        It "Warns if SQL instance edition is not supported" -Skip:$script:skipIntegrationTests {
            $null = Test-DbaDbLogShipStatus -SqlInstance $script:instance1 -WarningAction SilentlyContinue -WarningVariable editionwarn
            $editionwarn | Should -Match "Express"
        }
    }

    Context "When no log shipping is found" {
        It "Warns if no log shipping found" -Skip:$script:skipIntegrationTests {
            $null = Test-DbaDbLogShipStatus -SqlInstance $script:instance2 -Database 'master' -WarningAction SilentlyContinue -WarningVariable doesntexist
            $doesntexist | Should -Match "No information available"
        }
    }
}
