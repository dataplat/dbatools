param($ModuleName = 'dbatools')

Describe "Get-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDatabase
        }

        It "has all the required parameters" {
            $params = @(
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
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Count system databases on localhost" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 -ExcludeUser
        }
        It "reports the right number of databases" {
            $results.Count | Should -Be 4
        }
    }

    Context "Check that tempdb database is in Simple recovery mode" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
        }
        It "tempdb's recovery mode is Simple" {
            $results.RecoveryModel | Should -Be "Simple"
        }
    }

    Context "Check that master database is accessible" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database master
        }
        It "master is accessible" {
            $results.IsAccessible | Should -Be $true
        }
    }

    Context "Results return if no backup" {
        BeforeAll {
            $random = Get-Random
            $dbname1 = "dbatoolsci_Backup_$random"
            $dbname2 = "dbatoolsci_NoBackup_$random"
            $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname1, $dbname2
            $null = Backup-DbaDatabase -SqlInstance $global:instance1 -Type Full -FilePath nul -Database $dbname1
        }
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname1, $dbname2 | Remove-DbaDatabase -Confirm:$false
        }

        It "Should not report as database has full backup" {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname1 -NoFullBackup
            $results.Count | Should -Be 0
        }
        It "Should report 1 database with no full backup" {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname2 -NoFullBackup
            $results.Count | Should -Be 1
        }
    }

    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function { } -ModuleName $ModuleName
            Mock Test-FunctionInterrupt { } -ModuleName $ModuleName
            Mock Connect-DbaInstance -MockWith {
                [PSCustomObject]@{
                    Name      = 'SQLServerName'
                    Databases = @(
                        [PSCustomObject]@{
                            Name           = 'db1'
                            Status         = 'Normal'
                            ReadOnly       = 'false'
                            IsSystemObject = 'false'
                            RecoveryModel  = 'Full'
                            Owner          = 'sa'
                        }
                    )
                }
            } -ModuleName $ModuleName
            Mock Invoke-QueryRawDatabases -MockWith {
                [PSCustomObject]@(
                    @{
                        name  = 'db1'
                        state = 0
                        Owner = 'sa'
                    }
                )
            } -ModuleName $ModuleName
        }
        It "Should Call Stop-Function if NoUserDbs and NoSystemDbs are specified" {
            Get-DbaDatabase -SqlInstance Dummy -ExcludeSystem -ExcludeUser -ErrorAction SilentlyContinue
            Should -Invoke Stop-Function -Exactly 1 -Scope It -ModuleName $ModuleName
        }
        It "Validates that Test-FunctionInterrupt has been called" {
            Should -Invoke Test-FunctionInterrupt -Exactly 1 -Scope Context -ModuleName $ModuleName
        }
    }

    Context "Output" {
        BeforeAll {
            Mock Connect-DbaInstance -MockWith {
                [PSCustomObject]@{
                    Name      = 'SQLServerName'
                    Databases = @(
                        [PSCustomObject]@{
                            Name           = 'db1'
                            Status         = 'Normal'
                            ReadOnly       = 'false'
                            IsSystemObject = 'false'
                            RecoveryModel  = 'Full'
                            Owner          = 'sa'
                            IsAccessible   = $true
                        }
                    )
                }
            } -ModuleName $ModuleName
            Mock Invoke-QueryDBlastUsed -MockWith {
                [PSCustomObject]@{
                    dbname     = 'db1'
                    last_read  = (Get-Date).AddHours(-1)
                    last_write = (Get-Date).AddHours(-1)
                }
            } -ModuleName $ModuleName
            Mock Invoke-QueryRawDatabases -MockWith {
                [PSCustomObject]@(
                    @{
                        name  = 'db1'
                        state = 0
                        Owner = 'sa'
                    }
                )
            } -ModuleName $ModuleName
        }
        It "Should have Last Read and Last Write Property when IncludeLastUsed switch is added" {
            $result = Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed
            $result.LastRead | Should -Not -BeNullOrEmpty
            $result.LastWrite | Should -Not -BeNullOrEmpty
        }
        It "Validates that Connect-DbaInstance has been called" {
            Should -Invoke Connect-DbaInstance -Exactly 1 -Scope Context -ModuleName $ModuleName
        }
        It "Validates that Invoke-QueryDBlastUsed has been called" {
            Should -Invoke Invoke-QueryDBlastUsed -Exactly 1 -Scope Context -ModuleName $ModuleName
        }
    }
}
