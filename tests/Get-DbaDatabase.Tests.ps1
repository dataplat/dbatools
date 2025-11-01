#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDatabase",
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
                "Pattern",
                "ExcludeUser",
                "ExcludeSystem",
                "Owner",
                "Encrypted",
                "Status",
                "Access",
                "RecoveryModel",
                "NoFullBackup",
                "NoFullBackupSince",
                "NoLogBackup",
                "NoLogBackupSince",
                "IncludeLastUsed",
                "OnlyAccessible",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Count system databases on localhost" {
        It "reports the right number of databases" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -ExcludeUser
            $results.Count | Should -Be 4
        }
    }

    Context "Check that tempdb database is in Simple recovery mode" {
        It "tempdb's recovery mode is Simple" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
            $results.RecoveryModel | Should -Be "Simple"
        }
    }

    Context "Check that master database is accessible" {
        It "master is accessible" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master
            $results.IsAccessible | Should -BeTrue
        }
    }

}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        $dbname1 = "dbatoolsci_Backup_$random"
        $dbname2 = "dbatoolsci_NoBackup_$random"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbname1 , $dbname2
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Type Full -FilePath nul -Database $dbname1
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname1, $dbname2 | Remove-DbaDatabase
    }

    Context "Results return if no backup" {
        It "Should not report as database has full backup" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname1 -NoFullBackup
            ($results).Count | Should -Be 0
        }
        It "Should report 1 database with no full backup" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname2 -NoFullBackup
            ($results).Count | Should -Be 1
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        $dbPrefix = "dbatoolsci_pattern"
        $dbname1 = "${dbPrefix}_test1_$random"
        $dbname2 = "${dbPrefix}_test2_$random"
        $dbname3 = "${dbPrefix}_prod1_$random"
        $dbname4 = "other_database_$random"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbname1, $dbname2, $dbname3, $dbname4
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname1, $dbname2, $dbname3, $dbname4 | Remove-DbaDatabase
    }

    Context "Pattern parameter filtering" {
        It "Should return databases matching pattern with regex" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Pattern "^${dbPrefix}_"
            $results.Name | Should -Contain $dbname1
            $results.Name | Should -Contain $dbname2
            $results.Name | Should -Contain $dbname3
            $results.Name | Should -Not -Contain $dbname4
        }

        It "Should return databases matching pattern with _test segment" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Pattern "^${dbPrefix}_test"
            $results.Name | Should -Contain $dbname1
            $results.Name | Should -Contain $dbname2
            $results.Name | Should -Not -Contain $dbname3
            $results.Name | Should -Not -Contain $dbname4
        }

        It "Should return databases matching multiple patterns" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Pattern "^${dbPrefix}_test", "^${dbPrefix}_prod"
            $results.Name | Should -Contain $dbname1
            $results.Name | Should -Contain $dbname2
            $results.Name | Should -Contain $dbname3
            $results.Name | Should -Not -Contain $dbname4
        }

        It "Should return no results for non-matching pattern" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Pattern "^nonexistent_"
            $results | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests -Skip {
    # Skip UnitTests because they need refactoring.

    BeforeAll {
        ## Ensure it is the module that is being coded that is in the session when running just this Pester test
        #  Remove-Module dbatools -Force -ErrorAction SilentlyContinue
        #  $Base = Split-Path -parent $PSCommandPath
        #  Import-Module $Base\..\dbatools.psd1
    }
    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function { } -ModuleName dbatools
            Mock Test-FunctionInterrupt { } -ModuleName dbatools
        }
        Mock Connect-DbaInstance -MockWith {
            [object]@{
                Name      = 'SQLServerName'
                Databases = @(
                    @{
                        Name           = 'db1'
                        Status         = 'Normal'
                        ReadOnly       = 'false'
                        IsSystemObject = 'false'
                        RecoveryModel  = 'Full'
                        Owner          = 'sa'
                    }
                ) #databases
            } #object
        } -ModuleName dbatools #mock connect-SqlInstance
        function Invoke-QueryRawDatabases { }
        Mock Invoke-QueryRawDatabases -MockWith {
            [object]@(
                @{
                    name  = 'db1'
                    state = 0
                    Owner = 'sa'
                }
            )
        } -ModuleName dbatools
        It "Should Call Stop-Function if NoUserDbs and NoSystemDbs are specified" {
            # TODO: What does this do???
            Get-DbaDatabase -SqlInstance Dummy -ExcludeSystem -ExcludeUser -ErrorAction SilentlyContinue | Should Be
        }
        It "Validates that Stop Function Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Stop-Function'
                'Times'       = 1
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams
        }
        It "Validates that Test-FunctionInterrupt Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Test-FunctionInterrupt'
                'Times'       = 1
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams
        }
    }
    Context "Output" {
        It "Should have Last Read and Last Write Property when IncludeLastUsed switch is added" {
            Mock Connect-DbaInstance -MockWith {
                [object]@{
                    Name      = 'SQLServerName'
                    Databases = @(
                        @{
                            Name           = 'db1'
                            Status         = 'Normal'
                            ReadOnly       = 'false'
                            IsSystemObject = 'false'
                            RecoveryModel  = 'Full'
                            Owner          = 'sa'
                            IsAccessible   = $true
                        }
                    )
                } #object
            } -ModuleName dbatools #mock connect-SqlInstance
            function Invoke-QueryDBlastUsed { }
            Mock Invoke-QueryDBlastUsed -MockWith {
                [object]
                @{
                    dbname     = 'db1'
                    last_read  = (Get-Date).AddHours(-1)
                    last_write = (Get-Date).AddHours( - 1)
                }
            } -ModuleName dbatools
            function Invoke-QueryRawDatabases { }
            Mock Invoke-QueryRawDatabases -MockWith {
                [object]@(
                    @{
                        name  = 'db1'
                        state = 0
                        Owner = 'sa'
                    }
                )
            } -ModuleName dbatools
            (Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed).LastRead -ne $null | Should -BeTrue
            (Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed).LastWrite -ne $null | Should -BeTrue
        }
        It "Validates that Connect-DbaInstance Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Connect-DbaInstance'
                'Times'       = 2
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams
        }
        It "Validates that Invoke-QueryDBlastUsed Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Invoke-QueryDBlastUsed'
                'Times'       = 2
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams
        }
    }
}