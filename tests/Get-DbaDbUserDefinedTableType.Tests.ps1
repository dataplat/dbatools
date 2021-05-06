$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Database', 'ExcludeDatabase'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $tabletypename = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE TYPE $tabletypename AS TABLE([column1] INT NULL)", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP TYPE $tabletypename", 'tempdb')
    }

    Context "Gets the Db User Defined Table Type" {
        $results = Get-DbaDbUserDefinedTableType -SqlInstance $script:instance2 -database tempdb
        It "Gets results" {
            $results | Should Not Be $Null
        }
        It "Should have a name of $tabletypename" {
            $results.name | Should Be "$tabletypename"
        }
        It "Should have an owner of dbo" {
            $results.owner | Should Be "dbo"
        }
    }
}