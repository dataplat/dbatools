param($ModuleName = 'dbatools')

Describe "Rename-DbaDatabase" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_rename1'
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_filemove'
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_logicname'
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_filegroupname'
        $FileGroupName = @"
        ALTER DATABASE dbatoolsci_filegroupname
        ADD FILEGROUP Dbatoolsci_filegroupname
"@
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $FileGroupName
        $date = (Get-Date).ToString('yyyyMMdd')
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database "test_dbatoolsci_rename2_$($date)", "Dbatoolsci_filemove", "dbatoolsci_logicname", "dbatoolsci_filegroupname" -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Rename-DbaDatabase
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have AllDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllDatabases -Type Switch
        }
        It "Should have DatabaseName as a parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseName -Type String
        }
        It "Should have FileGroupName as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroupName -Type String
        }
        It "Should have LogicalName as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogicalName -Type String
        }
        It "Should have FileName as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileName -Type String
        }
        It "Should have ReplaceBefore as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReplaceBefore -Type Switch
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have Move as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Move -Type Switch
        }
        It "Should have SetOffline as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SetOffline -Type Switch
        }
        It "Should have Preview as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Preview -Type Switch
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Should preview a rename of a database" {
        BeforeAll {
            $variables = @{
                SqlInstance  = $global:instance2
                Database     = 'dbatoolsci_rename1'
                DatabaseName = 'dbatoolsci_rename2'
                Preview      = $true
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a preview DatabaseRenames" {
            $results.DatabaseRenames | Should -Be 'dbatoolsci_rename1 --> dbatoolsci_rename2'
        }
    }

    Context "Should rename a database" {
        BeforeAll {
            $variables = @{
                SqlInstance  = $global:instance2
                Database     = 'dbatoolsci_rename1'
                DatabaseName = 'dbatoolsci_rename2'
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $results.DatabaseRenames | Should -Be 'dbatoolsci_rename1 --> dbatoolsci_rename2'
        }
        It "Should have renamed the database" {
            $results.Database | Should -Be '[dbatoolsci_rename2]'
        }
        It "Should have the previous database name" {
            $results.DBN.Keys | Should -Be 'dbatoolsci_rename1'
        }
    }

    Context "Should rename a database with a prefix" {
        BeforeAll {
            $variables = @{
                SqlInstance  = $global:instance2
                Database     = 'dbatoolsci_rename2'
                DatabaseName = 'test_<DBN>'
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $results.DatabaseRenames | Should -Be 'dbatoolsci_rename2 --> test_dbatoolsci_rename2'
        }
        It "Should have renamed the database" {
            $results.Database | Should -Be '[test_dbatoolsci_rename2]'
        }
        It "Should have the previous database name" {
            $results.DBN.Keys | Should -Be 'dbatoolsci_rename2'
        }
    }

    Context "Should rename a database with a date" {
        BeforeAll {
            $variables = @{
                SqlInstance  = $global:instance2
                Database     = 'test_dbatoolsci_rename2'
                DatabaseName = '<DBN>_<DATE>'
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $results.DatabaseRenames | Should -Be "test_dbatoolsci_rename2 --> test_dbatoolsci_rename2_$($date)"
        }
        It "Should have renamed the database" {
            $results.Database | Should -Be "[test_dbatoolsci_rename2_$($date)]"
        }
        It "Should have the previous database name" {
            $results.DBN.Keys | Should -Be 'test_dbatoolsci_rename2'
        }
    }

    Context "Should preview renaming database files" {
        BeforeAll {
            $variables = @{
                SqlInstance = $global:instance2
                Database    = "dbatoolsci_filemove"
                FileName    = "<DBN>_<FGN>_<FNN>"
                Preview     = $true
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a Preview of renaming the database file name" {
            $results.FileNameRenames | Should -BeLike "*dbatoolsci_filemove.mdf --> *"
        }
        It "Should have a Preview of previous database file name" {
            $results.FNN.Keys | Should -Not -BeNullOrEmpty
        }
        It "Should have a Status of Partial" {
            $results.Status | Should -Be "Partial"
        }
    }

    Context "Should rename database files and move them" {
        BeforeAll {
            $variables = @{
                SqlInstance = $global:instance2
                Database    = "dbatoolsci_filemove"
                FileName    = "<DBN>_<FGN>_<FNN>"
                Move        = $true
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileNameRenames | Should -BeLike "*dbatoolsci_filemove.mdf --> *"
        }
        It "Should have the previous database name" {
            $results.FNN.Keys | Should -Not -BeNullOrEmpty
        }
        It "Should have a Status of FULL" {
            $results.Status | Should -Be "Full"
        }
    }

    Context "Should rename database files and forces the move" {
        BeforeAll {
            $variables = @{
                SqlInstance   = $global:instance2
                Database      = "dbatoolsci_filemove"
                FileName      = "<FNN>_<FT>"
                ReplaceBefore = $true
                Force         = $true
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileNameRenames | Should -BeLike "*_ROWS.mdf*"
        }
        It "Should have the previous database name" {
            $results.FNN.Keys | Should -Not -BeNullOrEmpty
        }
        It "Should have a Status of Partial" {
            $results.Status | Should -Be "Partial"
        }
    }

    Context "Should rename database files and set the database offline" {
        BeforeAll {
            $variables = @{
                SqlInstance = $global:instance2
                Database    = "dbatoolsci_filemove"
                FileName    = "<FNN>_<LGN>_<DATE>"
                SetOffline  = $true
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileNameRenames | Should -BeLike "*___log_LOG.ldf --> *"
        }
        It "Should have the previous database name" {
            $results.FNN.Keys | Should -Not -BeNullOrEmpty
        }
        It "Should have the pending database name" {
            $results.PendingRenames | Should -Not -BeNullOrEmpty
        }
        It "Should have a Status of Partial" {
            $results.Status | Should -Be "Partial"
        }
    }

    Context "Should rename the logical name" {
        BeforeAll {
            $variables = @{
                SqlInstance = $global:instance2
                Database    = "dbatoolsci_logicname"
                LogicalName = "<LGN>_<DATE>_<DBN>"
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.LogicalNameRenames | Should -BeLike "dbatoolsci_logicname --> *"
        }
        It "Should have the previous database name" {
            $results.LGN.Keys | Should -Be @('dbatoolsci_logicname', 'dbatoolsci_logicname_log')
        }
        It "Should have a Status of Full" {
            $results.Status | Should -Be "Full"
        }
    }

    Context "Should rename the filegroupname name" {
        BeforeAll {
            $variables = @{
                SqlInstance   = $global:instance2
                Database      = "dbatoolsci_filegroupname"
                FileGroupName = "<FGN>_<DATE>_<DBN>"
            }
            $results = Rename-DbaDatabase @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $results.FileGroupsRenames | Should -BeLike "Dbatoolsci_filegroupname --> *"
        }
        It "Should have the previous database name" {
            $results.FGN.Keys | Should -Be @('Dbatoolsci_filegroupname')
        }
    }
}
