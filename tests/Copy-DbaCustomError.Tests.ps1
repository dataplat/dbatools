$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'CustomError', 'ExcludeCustomError', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -Database master
        $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16,@msgtext = N'The item named %s already exists in %s.',@lang = 'us_english';")
        $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'L''élément nommé %1! existe déjà dans %2!',@lang = 'French';")
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -Database master
        $server.Query("EXEC sp_dropmessage @msgnum = 60000, @lang = 'all';")
        $server = Connect-DbaInstance -SqlInstance $script:instance3 -Database master
        $server.Query("EXEC sp_dropmessage @msgnum = 60000, @lang = 'all';")
    }

    It "copies the sample custom errror" {
        $results = Copy-DbaCustomError -Source $script:instance2 -Destination $script:instance3 -CustomError 60000
        $results.Name -eq "60000:'us_english'", "60000:'Français'"
        $results.Status -eq 'Successful', 'Successful'
    }

    It "doesn't overwrite existing custom errors" {
        $results = Copy-DbaCustomError -Source $script:instance2 -Destination $script:instance3 -CustomError 60000
        $results.Name -eq "60000:'us_english'", "60000:'Français'"
        $results.Status -eq 'Skipped', 'Skipped'
    }

    It "the newly copied custom error exists" {
        $results = Get-DbaCustomError -SqlInstance $script:instance2
        $results.ID -contains 60000
    }
}