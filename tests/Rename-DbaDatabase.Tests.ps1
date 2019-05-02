$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance','SqlCredential','Database','ExcludeDatabase','AllDatabases','DatabaseName','FileGroupName','LogicalName','FileName','ReplaceBefore','Force','Move','SetOffline','Preview','InputObject','EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = New-DbaDatabase -SqlInstance $script:instance3 -Name 'dbatoolsci_rename1'
        $date = (Get-Date).ToString('yyyyMMdd')
    }
    AfterAll {
        $database = Get-DbaDatabase -SqlInstance $script:instance3 -UserDbOnly | Where-Object {$_.name -like '*dbatoolsci*'}
        $null = Remove-DbaDatabase -SqlInstance $script:instance3 -database $($database.name) -Confirm:$false
    }

    Context "Should preview a rename of a database" {
        $variables = @{SqlInstance = $script:instance3
                    Database = 'dbatoolsci_rename1'
                    DatabaseName = 'dbatoolsci_rename2'
                    Preview = $true
                    }

            $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a preview DatabaseRenames" {
            $results.DatabaseRenames | Should Be 'dbatoolsci_rename1 --> dbatoolsci_rename2'
        }
    }

    Context "Should rename a database" {
        $variables = @{SqlInstance = $script:instance3
                    Database = 'dbatoolsci_rename1'
                    DatabaseName = 'dbatoolsci_rename2'
                    }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $results.DatabaseRenames | Should Be 'dbatoolsci_rename1 --> dbatoolsci_rename2'
        }
        It "Should have renamed the database" {
            $results.Database | Should Be '[dbatoolsci_rename2]'
        }
        It "Should have the previous database name" {
            $results.DBN.Keys | Should Be 'dbatoolsci_rename1'
        }
    }

    Context "Should rename a database with a prefix" {
        $variables = @{SqlInstance = $script:instance3
                    Database = 'dbatoolsci_rename2'
                    DatabaseName = 'test_<DBN>'
                    }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $results.DatabaseRenames | Should Be 'dbatoolsci_rename2 --> test_dbatoolsci_rename2'
        }
        It "Should have renamed the database" {
            $results.Database | Should Be '[test_dbatoolsci_rename2]'
        }
        It "Should have the previous database name" {
            $results.DBN.Keys | Should Be 'dbatoolsci_rename2'
        }
    }

    Context "Should rename a database with a date" {
        $variables = @{SqlInstance = $script:instance3
                    Database = 'test_dbatoolsci_rename2'
                    DatabaseName = '<DBN>_<DATE>'
                    }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $results.DatabaseRenames | Should Be "test_dbatoolsci_rename2 --> test_dbatoolsci_rename2_$($date)"
        }
        It "Should have renamed the database" {
            $results.Database | Should Be "[test_dbatoolsci_rename2_$($date)]"
        }
        It "Should have the previous database name" {
            $results.DBN.Keys | Should Be 'test_dbatoolsci_rename2'
        }
    }
}