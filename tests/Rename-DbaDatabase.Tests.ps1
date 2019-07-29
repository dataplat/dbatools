$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'AllDatabases', 'DatabaseName', 'FileGroupName', 'LogicalName', 'FileName', 'ReplaceBefore', 'Force', 'Move', 'SetOffline', 'Preview', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_rename1'
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_filemove'
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_logicname'
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_filegroupname'
        $FileGroupName = @"
        ALTER DATABASE dbatoolsci_filegroupname
        ADD FILEGROUP Dbatoolsci_filegroupname
"@
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $FileGroupName
        $date = (Get-Date).ToString('yyyyMMdd')
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database "test_dbatoolsci_rename2_$($date)", "Dbatoolsci_filemove", "dbatoolsci_logicname", "dbatoolsci_filegroupname" -Confirm:$false
    }

    Context "Should preview a rename of a database" {
        $variables = @{SqlInstance = $script:instance2
            Database               = 'dbatoolsci_rename1'
            DatabaseName           = 'dbatoolsci_rename2'
            Preview                = $true
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
        $variables = @{SqlInstance = $script:instance2
            Database               = 'dbatoolsci_rename1'
            DatabaseName           = 'dbatoolsci_rename2'
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
        $variables = @{SqlInstance = $script:instance2
            Database               = 'dbatoolsci_rename2'
            DatabaseName           = 'test_<DBN>'
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
        $variables = @{SqlInstance = $script:instance2
            Database               = 'test_dbatoolsci_rename2'
            DatabaseName           = '<DBN>_<DATE>'
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

    Context "Should preview renaming database files" {
        $variables = @{SqlInstance = $script:instance2
            Database               = "dbatoolsci_filemove"
            FileName               = "<DBN>_<FGN>_<FNN>"
            Preview                = $true
        }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a Preview of renaming the database file name" {
            $results.FileNameRenames | Should BeLike "*dbatoolsci_filemove.mdf --> *"
        }
        It "Should have a Preview of previous database file name" {
            $results.FNN.Keys | Should Not Be $Null
        }
        It "Should have a Status of Partial" {
            $results.Status | Should Be "Partial"
        }
    }

    Context "Should rename database files and move them" {
        $variables = @{SqlInstance = $script:instance2
            Database               = "dbatoolsci_filemove"
            FileName               = "<DBN>_<FGN>_<FNN>"
            Move                   = $true
        }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileNameRenames | Should BeLike "*dbatoolsci_filemove.mdf --> *"
        }
        It "Should have the previous database name" {
            $results.FNN.Keys | Should Not Be $Null
        }
        It "Should have a Status of FULL" {
            $results.Status | Should Be "Full"
        }
    }

    Context "Should rename database files and forces the move" {
        $variables = @{SqlInstance = $script:instance2
            Database               = "dbatoolsci_filemove"
            FileName               = "<FNN>_<FT>"
            ReplaceBefore          = $true
            Force                  = $true
        }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileNameRenames | Should BeLike "*_ROWS.mdf*"
        }
        It "Should have the previous database name" {
            $results.FNN.Keys | Should Not Be $Null
        }
        It "Should have a Status of Partial" {
            $results.Status | Should Be "Partial"
        }
    }

    Context "Should rename database files and set the database offline" {
        $variables = @{SqlInstance = $script:instance2
            Database               = "dbatoolsci_filemove"
            FileName               = "<FNN>_<LGN>_<DATE>"
            SetOffline             = $true
        }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileNameRenames | Should BeLike "*___log_LOG.ldf --> *"
        }
        It "Should have the previous database name" {
            $results.FNN.Keys | Should Not Be $Null
        }
        It "Should have the pending database name" {
            $results.PendingRenames | Should Not Be $Null
        }
        It "Should have a Status of Partial" {
            $results.Status | Should Be "Partial"
        }
    }

    Context "Should rename the logical name" {
        $variables = @{SqlInstance = $script:instance2
            Database               = "dbatoolsci_logicname"
            LogicalName            = "<LGN>_<DATE>_<DBN>"
        }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.LogicalNameRenames | Should BeLike "dbatoolsci_logicname --> *"
        }
        It "Should have the previous database name" {
            $results.LGN.Keys | Should BE @('dbatoolsci_logicname', 'dbatoolsci_logicname_log')
        }
        It "Should have a Status of Full" {
            $results.Status | Should Be "Full"
        }
    }

    Context "Should rename the filegroupname name" {
        $variables = @{SqlInstance = $script:instance2
            Database               = "dbatoolsci_filegroupname"
            FileGroupName          = "<FGN>_<DATE>_<DBN>"
        }

        $results = Rename-DbaDatabase @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileGroupsRenames | Should BeLike "Dbatoolsci_filegroupname --> *"
        }
        It "Should have the previous database name" {
            $results.FGN.Keys | Should BE @('Dbatoolsci_filegroupname')
        }
    }
}