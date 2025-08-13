#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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
}

Describe $CommandName -Tag IntegrationTests {

    Context "Count system databases on localhost" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -ExcludeUser
        }

        It "reports the right number of databases" {
            $results.Status.Count | Should -BeExactly 4
        }
    }

    Context "Check that tempdb database is in Simple recovery mode" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
        }

        It "tempdb's recovery mode is Simple" {
            $results.RecoveryModel | Should -Be "Simple"
        }
    }

    Context "Check that master database is accessible" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master
        }

        It "master is accessible" {
            $results.IsAccessible | Should -Be $true
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
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname1, $dbname2 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Results return if no backup" {
        BeforeAll {
            $resultsWithBackup = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname1 -NoFullBackup
            $resultsNoBackup = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname2 -NoFullBackup
        }

        It "Should not report as database has full backup" {
            @($resultsWithBackup).Count | Should -BeExactly 0
        }

        It "Should report 1 database with no full backup" {
            @($resultsNoBackup).Count | Should -BeExactly 1
        }
    }
}

Describe $CommandName -Tag UnitTests {
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
            function Invoke-QueryRawDatabases { }
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
            Get-DbaDatabase -SqlInstance Dummy -ExcludeSystem -ExcludeUser -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        It "Validates that Stop Function Mock has been called" {
            Should -Invoke -CommandName "Stop-Function" -ModuleName "dbatools" -Times 1 -Exactly
        }
        It "Validates that Test-FunctionInterrupt Mock has been called" {
            Should -Invoke -CommandName "Test-FunctionInterrupt" -ModuleName "dbatools" -Times 1 -Exactly
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
            function Invoke-QueryDBlastUsed { }
            Mock Invoke-QueryDBlastUsed -MockWith {
                [object]
                @{
                    dbname     = "db1"
                    last_read  = (Get-Date).AddHours(-1)
                    last_write = (Get-Date).AddHours(-1)
                }
            } -ModuleName dbatools
            function Invoke-QueryRawDatabases { }
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
            $testResult = Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed
            $testResult.LastRead | Should -Not -BeNullOrEmpty
            $testResult.LastWrite | Should -Not -BeNullOrEmpty
        }
        It "Validates that Connect-DbaInstance Mock has been called" {
            Should -Invoke -CommandName "Connect-DbaInstance" -ModuleName "dbatools" -Times 1 -Exactly
        }
        It "Validates that Invoke-QueryDBlastUsed Mock has been called" {
            Should -Invoke -CommandName "Invoke-QueryDBlastUsed" -ModuleName "dbatools" -Times 1 -Exactly
        }
    }
}