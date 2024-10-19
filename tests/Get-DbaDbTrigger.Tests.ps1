param($ModuleName = 'dbatools')

Describe "Get-DbaDbTrigger Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbTrigger
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
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Get-DbaDbTrigger Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $trigger = @"
CREATE TRIGGER dbatoolsci_safety
    ON DATABASE
    FOR DROP_SYNONYM
    AS
    IF (@@ROWCOUNT = 0)
    RETURN;
    RAISERROR ('You must disable Trigger "dbatoolsci_safety" to drop synonyms!',10, 1)
    ROLLBACK
"@
        $server.Query("$trigger")
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $trigger = "DROP TRIGGER dbatoolsci_safety ON DATABASE;"
        $server.Query("$trigger")
    }

    Context "Gets Database Trigger" {
        BeforeAll {
            $results = Get-DbaDbTrigger -SqlInstance $global:instance2 | Where-Object {$_.name -eq "dbatoolsci_safety"}
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }

        It "Should have text of Trigger" {
            $results.text | Should -BeLike '*FOR DROP_SYNONYM*'
        }
    }

    Context "Gets Database Trigger when using -Database" {
        BeforeAll {
            $results = Get-DbaDbTrigger -SqlInstance $global:instance2 -Database Master
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }

        It "Should have text of Trigger" {
            $results.text | Should -BeLike '*FOR DROP_SYNONYM*'
        }
    }

    Context "Gets no Database Trigger when using -ExcludeDatabase" {
        BeforeAll {
            $results = Get-DbaDbTrigger -SqlInstance $global:instance2 -ExcludeDatabase Master
        }

        It "Gets no results" {
            $results | Should -BeNullOrEmpty
        }
    }
}
