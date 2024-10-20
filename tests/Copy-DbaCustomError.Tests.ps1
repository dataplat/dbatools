param($ModuleName = 'dbatools')

Describe "Copy-DbaCustomError" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaCustomError
        }
        $knownParameters = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'CustomError',
            'ExcludeCustomError',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" {
            $command | Should -HaveParameter $knownParameters
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2 -Database master
            $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16,@msgtext = N'The item named %s already exists in %s.',@lang = 'us_english';")
            $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'L''élément nommé %1! existe déjà dans %2!',@lang = 'French';")
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2 -Database master
            $server.Query("EXEC sp_dropmessage @msgnum = 60000, @lang = 'all';")
            $server = Connect-DbaInstance -SqlInstance $global:instance3 -Database master
            $server.Query("EXEC sp_dropmessage @msgnum = 60000, @lang = 'all';")
        }

        It "copies the sample custom error" {
            $results = Copy-DbaCustomError -Source $global:instance2 -Destination $global:instance3 -CustomError 60000
            $results.Name | Should -Be @("60000:'us_english'", "60000:'Français'")
            $results.Status | Should -Be @('Successful', 'Successful')
        }

        It "doesn't overwrite existing custom errors" {
            $results = Copy-DbaCustomError -Source $global:instance2 -Destination $global:instance3 -CustomError 60000
            $results.Name | Should -Be @("60000:'us_english'", "60000:'Français'")
            $results.Status | Should -Be @('Skipped', 'Skipped')
        }

        It "the newly copied custom error exists" {
            $results = Get-DbaCustomError -SqlInstance $global:instance3
            $results.ID | Should -Contain 60000
        }
    }
}
