$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Database', 'ExcludeDatabase', 'Type'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $tabletypename = ("dbatools_{0}" -f $(Get-Random))
        $tabletypename1 = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE TYPE $tabletypename AS TABLE([column1] INT NULL)", 'tempdb')
        $server.Query("CREATE TYPE $tabletypename1 AS TABLE([column1] INT NULL)", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP TYPE $tabletypename", 'tempdb')
        $null = $server.Query("DROP TYPE $tabletypename1", 'tempdb')
    }

    Context "Gets a Db User Defined Table Type" {
        $results = Get-DbaDbUserDefinedTableType -SqlInstance $TestConfig.instance2 -database tempdb -Type $tabletypename
        It "Gets results" {
            $results | Should Not Be $Null
        }
        It "Should have a name of $tabletypename" {
            $results.name | Should Be "$tabletypename"
        }
        It "Should have an owner of dbo" {
            $results.owner | Should Be "dbo"
        }
        It "Should have a count of 1" {
            $results.Count | Should Be 1
        }
    }

    Context "Gets all the Db User Defined Table Type" {
        $results = Get-DbaDbUserDefinedTableType -SqlInstance $TestConfig.instance2 -database tempdb
        It "Gets results" {
            $results | Should Not Be $Null
        }
        It "Should have a count of 2" {
            $results.Count | Should Be 2
        }

    }
}
