$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $sql = "EXEC msdb.dbo.sp_addmessage 54321, 9, N'Dbatools is Awesome!';"
        $server.Query($sql)
    }
    Afterall {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $sql = "EXEC msdb.dbo.sp_dropmessage 54321;"
        $server.Query($sql)
    }

    Context "Gets the backup devices" {
        $results = Get-DbaCustomError -SqlInstance $script:instance1
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Should have the name Custom Error Text" {
            $results.Text | Should Be "Dbatools is Awesome!"
        }
        It "Should have a LanguageID" {
            $results.LanguageID | Should Be 1033
        }
        It "Should have a Custom Error ID" {
            $results.ID | Should Be 54321
        }
    }
}