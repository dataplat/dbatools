#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Rename-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "AllDatabases",
                "DatabaseName",
                "FileGroupName",
                "LogicalName",
                "FileName",
                "ReplaceBefore",
                "Force",
                "Move",
                "SetOffline",
                "Preview",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_rename1"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_filemove"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_logicname"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_filegroupname"
        $fileGroupQuery = @"
        ALTER DATABASE dbatoolsci_filegroupname
        ADD FILEGROUP Dbatoolsci_filegroupname
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $fileGroupQuery
        $global:testDate = (Get-Date).ToString("yyyyMMdd")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "test_dbatoolsci_rename2_$($global:testDate)", "Dbatoolsci_filemove", "dbatoolsci_logicname", "dbatoolsci_filegroupname" -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "Should preview a rename of a database" {
        BeforeAll {
            $splatPreview = @{
                SqlInstance  = $TestConfig.instance2
                Database     = "dbatoolsci_rename1"
                DatabaseName = "dbatoolsci_rename2"
                Preview      = $true
            }

            $previewResults = Rename-DbaDatabase @splatPreview
        }

        It "Should have Results" {
            $previewResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a preview DatabaseRenames" {
            $previewResults.DatabaseRenames | Should -Be "dbatoolsci_rename1 --> dbatoolsci_rename2"
        }
    }

    Context "Should rename a database" {
        BeforeAll {
            $splatRename = @{
                SqlInstance  = $TestConfig.instance2
                Database     = "dbatoolsci_rename1"
                DatabaseName = "dbatoolsci_rename2"
            }

            $renameResults = Rename-DbaDatabase @splatRename
        }

        It "Should have Results" {
            $renameResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $renameResults.DatabaseRenames | Should -Be "dbatoolsci_rename1 --> dbatoolsci_rename2"
        }
        It "Should have renamed the database" {
            $renameResults.Database | Should -Be "[dbatoolsci_rename2]"
        }
        It "Should have the previous database name" {
            $renameResults.DBN.Keys | Should -Be "dbatoolsci_rename1"
        }
    }

    Context "Should rename a database with a prefix" {
        BeforeAll {
            $splatPrefix = @{
                SqlInstance  = $TestConfig.instance2
                Database     = "dbatoolsci_rename2"
                DatabaseName = "test_<DBN>"
            }

            $prefixResults = Rename-DbaDatabase @splatPrefix
        }

        It "Should have Results" {
            $prefixResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $prefixResults.DatabaseRenames | Should -Be "dbatoolsci_rename2 --> test_dbatoolsci_rename2"
        }
        It "Should have renamed the database" {
            $prefixResults.Database | Should -Be "[test_dbatoolsci_rename2]"
        }
        It "Should have the previous database name" {
            $prefixResults.DBN.Keys | Should -Be "dbatoolsci_rename2"
        }
    }

    Context "Should rename a database with a date" {
        BeforeAll {
            $splatDate = @{
                SqlInstance  = $TestConfig.instance2
                Database     = "test_dbatoolsci_rename2"
                DatabaseName = "<DBN>_<DATE>"
            }

            $dateResults = Rename-DbaDatabase @splatDate
        }

        It "Should have Results" {
            $dateResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a DatabaseRenames" {
            $dateResults.DatabaseRenames | Should -Be "test_dbatoolsci_rename2 --> test_dbatoolsci_rename2_$($global:testDate)"
        }
        It "Should have renamed the database" {
            $dateResults.Database | Should -Be "[test_dbatoolsci_rename2_$($global:testDate)]"
        }
        It "Should have the previous database name" {
            $dateResults.DBN.Keys | Should -Be "test_dbatoolsci_rename2"
        }
    }

    Context "Should preview renaming database files" {
        BeforeAll {
            $splatFilePreview = @{
                SqlInstance = $TestConfig.instance2
                Database    = "dbatoolsci_filemove"
                FileName    = "<DBN>_<FGN>_<FNN>"
                Preview     = $true
            }

            $filePreviewResults = Rename-DbaDatabase @splatFilePreview
        }

        It "Should have Results" {
            $filePreviewResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Preview of renaming the database file name" {
            $filePreviewResults.FileNameRenames | Should -BeLike "*dbatoolsci_filemove.mdf --> *"
        }
        It "Should have a Preview of previous database file name" {
            $filePreviewResults.FNN.Keys | Should -Not -Be $null
        }
        It "Should have a Status of Partial" {
            $filePreviewResults.Status | Should -Be "Partial"
        }
    }

    Context "Should rename database files and move them" {
        BeforeAll {
            $splatFileMove = @{
                SqlInstance = $TestConfig.instance2
                Database    = "dbatoolsci_filemove"
                FileName    = "<DBN>_<FGN>_<FNN>"
                Move        = $true
            }

            $fileMoveResults = Rename-DbaDatabase @splatFileMove
        }

        It "Should have Results" {
            $fileMoveResults | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $fileMoveResults.FileNameRenames | Should -BeLike "*dbatoolsci_filemove.mdf --> *"
        }
        It "Should have the previous database name" {
            $fileMoveResults.FNN.Keys | Should -Not -Be $null
        }
        It "Should have a Status of FULL" {
            $fileMoveResults.Status | Should -Be "Full"
        }
    }

    Context "Should rename database files and forces the move" {
        BeforeAll {
            $splatFileForce = @{
                SqlInstance   = $TestConfig.instance2
                Database      = "dbatoolsci_filemove"
                FileName      = "<FNN>_<FT>"
                ReplaceBefore = $true
                Force         = $true
            }

            $fileForceResults = Rename-DbaDatabase @splatFileForce
        }

        It "Should have Results" {
            $fileForceResults | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $fileForceResults.FileNameRenames | Should -BeLike "*_ROWS.mdf*"
        }
        It "Should have the previous database name" {
            $fileForceResults.FNN.Keys | Should -Not -Be $null
        }
        It "Should have a Status of Partial" {
            $fileForceResults.Status | Should -Be "Partial"
        }
    }

    Context "Should rename database files and set the database offline" {
        BeforeAll {
            $splatFileOffline = @{
                SqlInstance = $TestConfig.instance2
                Database    = "dbatoolsci_filemove"
                FileName    = "<FNN>_<LGN>_<DATE>"
                SetOffline  = $true
            }

            $fileOfflineResults = Rename-DbaDatabase @splatFileOffline
        }

        It "Should have Results" {
            $fileOfflineResults | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $fileOfflineResults.FileNameRenames | Should -BeLike "*___log_LOG.ldf --> *"
        }
        It "Should have the previous database name" {
            $fileOfflineResults.FNN.Keys | Should -Not -Be $null
        }
        It "Should have the pending database name" {
            $fileOfflineResults.PendingRenames | Should -Not -Be $null
        }
        It "Should have a Status of Partial" {
            $fileOfflineResults.Status | Should -Be "Partial"
        }
    }

    Context "Should rename the logical name" {
        BeforeAll {
            $splatLogical = @{
                SqlInstance = $TestConfig.instance2
                Database    = "dbatoolsci_logicname"
                LogicalName = "<LGN>_<DATE>_<DBN>"
            }

            $logicalResults = Rename-DbaDatabase @splatLogical
        }

        It "Should have Results" {
            $logicalResults | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $logicalResults.LogicalNameRenames | Should -BeLike "dbatoolsci_logicname --> *"
        }
        It "Should have the previous database name" {
            $logicalResults.LGN.Keys | Should -Be @("dbatoolsci_logicname", "dbatoolsci_logicname_log")
        }
        It "Should have a Status of Full" {
            $logicalResults.Status | Should -Be "Full"
        }
    }

    Context "Should rename the filegroupname name" {
        BeforeAll {
            $splatFileGroup = @{
                SqlInstance   = $TestConfig.instance2
                Database      = "dbatoolsci_filegroupname"
                FileGroupName = "<FGN>_<DATE>_<DBN>"
            }

            $fileGroupResults = Rename-DbaDatabase @splatFileGroup
        }

        It "Should have Results" {
            $fileGroupResults | Should -Not -BeNullOrEmpty
        }
        It "Should have renamed the database files" {
            $fileGroupResults.FileGroupsRenames | Should -BeLike "Dbatoolsci_filegroupname --> *"
        }
        It "Should have the previous database name" {
            $fileGroupResults.FGN.Keys | Should -Be @("Dbatoolsci_filegroupname")
        }
    }
}