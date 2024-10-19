param($ModuleName = 'dbatools')

Describe "Test-DbaDbLogShipStatus Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandName = 'Test-DbaDbLogShipStatus'
            $CommandUnderTest = Get-Command $CommandName
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Simple",
                "Primary",
                "Secondary",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
