param($ModuleName = 'dbatools')

Describe "Get-DbaDbLogShipError Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Importing necessary module or setting up environment if needed
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = Get-Command Get-DbaDbLogShipError
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "Action",
            "DateTimeFrom",
            "DateTimeTo",
            "Primary",
            "Secondary",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandName | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaDbLogShipError Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        # Setup code for integration tests
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Return values" {
        It "Get the log shipping errors" {
            $Results = Get-DbaDbLogShipError -SqlInstance $global:instance2
            $Results.Count | Should -Be 0
        }
    }
}
