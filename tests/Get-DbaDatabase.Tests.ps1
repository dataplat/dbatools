#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

# Define mock functions globally for Pester v5
function Invoke-QueryRawDatabases { }
function Invoke-QueryDBlastUsed { }

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
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
                "EnableException",
                "IncludeLastUsed",
                "OnlyAccessible"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function { } -ModuleName dbatools
            Mock Test-FunctionInterrupt { } -ModuleName dbatools
            Mock Connect-DbaInstance -MockWith {
                [object]@{
                    Name      = "SQLServerName"
                    Databases = @(
                        @{
                            Name           = "db1"
                            Status         = "Normal"
                            ReadOnly       = "false"
                            IsSystemObject = "false"
                            RecoveryModel  = "Full"
                            Owner          = "sa"
                        }
                    ) #databases
                } #object
            } -ModuleName dbatools #mock connect-SqlInstance
            Mock Invoke-QueryRawDatabases -MockWith {
                [object]@(
                    @{
                        name  = "db1"
                        state = 0
                        Owner = "sa"
                    }
                )
            } -ModuleName dbatools
        }

        It "Should Call Stop-Function if NoUserDbs and NoSystemDbs are specified" {
            Get-DbaDatabase -SqlInstance Dummy -ExcludeSystem -ExcludeUser -ErrorAction SilentlyContinue | Should -Be
        }

        It "Validates that Stop Function Mock has been called" {
            $assertMockParams = @{
                CommandName = "Stop-Function"
                Times       = 1
                Exactly     = $true
                Module      = "dbatools"
            }
            Assert-MockCalled @assertMockParams
        }

        It "Validates that Test-FunctionInterrupt Mock has been called" {
            $assertMockParams = @{
                CommandName = "Test-FunctionInterrupt"
                Times       = 1
                Exactly     = $true
                Module      = "dbatools"
            }
            Assert-MockCalled @assertMockParams
        }
    }

    Context "Output" {
        BeforeAll {
            Mock Connect-DbaInstance -MockWith {
                [object]@{
                    Name      = "SQLServerName"
                    Databases = @(
                        @{
                            Name           = "db1"
                            Status         = "Normal"
                            ReadOnly       = "false"
                            IsSystemObject = "false"
                            RecoveryModel  = "Full"
                            Owner          = "sa"
                            IsAccessible   = $true
                        }
                    )
                } #object
            } -ModuleName dbatools #mock connect-SqlInstance
            Mock Invoke-QueryDBlastUsed -MockWith {
                [object]@{
                    dbname     = "db1"
                    last_read  = (Get-Date).AddHours(-1)
                    last_write = (Get-Date).AddHours(-1)
                }
            } -ModuleName dbatools
            Mock Invoke-QueryRawDatabases -MockWith {
                [object]@(
                    @{
                        name  = "db1"
                        state = 0
                        Owner = "sa"
                    }
                )
            } -ModuleName dbatools
        }

        It "Should have Last Read and Last Write Property when IncludeLastUsed switch is added" {
            (Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed).LastRead -ne $null | Should -Be $true
            (Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed).LastWrite -ne $null | Should -Be $true
        }

        It "Validates that Connect-DbaInstance Mock has been called" {
            $assertMockParams = @{
                CommandName = "Connect-DbaInstance"
                Times       = 2
                Exactly     = $true
                Module      = "dbatools"
            }
            Assert-MockCalled @assertMockParams
        }

        It "Validates that Invoke-QueryDBlastUsed Mock has been called" {
            $assertMockParams = @{
                CommandName = "Invoke-QueryDBlastUsed"
                Times       = 2
                Exactly     = $true
                Module      = "dbatools"
            }
            Assert-MockCalled @assertMockParams
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Count system databases on localhost" {
        BeforeAll {
            $systemDbResults = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -ExcludeUser
        }

        It "reports the right number of databases" {
            $systemDbResults.Count | Should -Be 4
        }
    }

    Context "Check that tempdb database is in Simple recovery mode" {
        BeforeAll {
            $tempDbResults = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
        }

        It "tempdb's recovery mode is Simple" {
            $tempDbResults.RecoveryModel | Should -Be "Simple"
        }
    }

    Context "Check that master database is accessible" {
        BeforeAll {
            $masterDbResults = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master
        }

        It "master is accessible" {
            $masterDbResults.IsAccessible | Should -Be $true
        }
    }

    Context "Results return if no backup" {
        BeforeAll {
            $random = Get-Random
            $backupDbName = "dbatoolsci_Backup_$random"
            $noBackupDbName = "dbatoolsci_NoBackup_$random"
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $backupDbName, $noBackupDbName
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Type Full -FilePath nul -Database $backupDbName

            $backupResults = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $backupDbName -NoFullBackup
            $noBackupResults = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $noBackupDbName -NoFullBackup
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $backupDbName, $noBackupDbName | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should not report as database has full backup" {
            $backupResults.Count | Should -Be 0
        }

        It "Should report 1 database with no full backup" {
            $noBackupResults.Count | Should -Be 1
        }
    }
}
