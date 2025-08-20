$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeUser', 'ExcludeSystem', 'Owner', 'Encrypted', 'Status', 'Access', 'RecoveryModel', 'NoFullBackup', 'NoFullBackupSince', 'NoLogBackup', 'NoLogBackupSince', 'EnableException', 'IncludeLastUsed', 'OnlyAccessible'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {

    Context "Count system databases on localhost" {
        $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -ExcludeUser
        It "reports the right number of databases" {
            $results.Count | Should Be 4
        }
    }

    Context "Check that tempdb database is in Simple recovery mode" {
        $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
        It "tempdb's recovery mode is Simple" {
            $results.RecoveryModel | Should Be "Simple"
        }
    }

    Context "Check that master database is accessible" {
        $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master
        It "master is accessible" {
            $results.IsAccessible | Should Be $true
        }
    }

}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
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
        $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname1 -NoFullBackup
        It "Should not report as database has full backup" {
            ($results).Count | Should Be 0
        }
        $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname2 -NoFullBackup
        It "Should report 1 database with no full backup" {
            ($results).Count | Should Be 1
        }
    }
}

Describe "$commandname Unit Tests" -Tags "UnitTests", Get-DBADatabase {
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
            (Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed).LastRead -ne $null | Should Be $true
            (Get-DbaDatabase -SqlInstance SQLServerName -IncludeLastUsed).LastWrite -ne $null | Should Be $true
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