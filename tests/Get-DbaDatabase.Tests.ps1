$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Count system databases on localhost" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -ExcludeAllUserDb
        It "reports the right number of databases" {
            $results.Count | Should Be 4
        }
    }

    Context "Check that temppb database is in Simple recovery mode" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        It "tempdb's recovery mode is Simple" {
            $results.RecoveryModel | Should Be "Simple"
        }
    }

    Context "Check that master database is accessible" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -Database master
        It "master is accessible" {
            $results.IsAccessible | Should Be $true
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
        Mock Connect-SQLInstance -MockWith {
            [object]@{
                Name      = 'SQLServerName';
                Databases = [object]@(
                    @{
                        Name           = 'db1'
                        Status         = 'Normal'
                        ReadOnly       = 'false'
                        IsSystemObject = 'false'
                        RecoveryModel  = 'Full'
                        Owner          = 'sa'
                    }
                ); #databases
            } #object
        } -ModuleName dbatools #mock connect-sqlserver
        function Invoke-QueryRawDatabases { }
        Mock Invoke-QueryRawDatabases -MockWith {
            [object]@(
                @{
                    name     = 'db1'
                    state = 0
                    Owner = 'sa'
                }
            )
        } -ModuleName dbatools
        It "Should Call Stop-Function if NoUserDbs and NoSystemDbs are specified" {
            Get-DbaDatabase -SqlInstance Dummy -ExcludeAllSystemDb -ExcludeAllUserDb -ErrorAction SilentlyContinue | Should Be
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
            Mock Connect-SQLInstance -MockWith {
                [object]@{
                    Name      = 'SQLServerName'
                    Databases = [object]@{
                            'db1' = @{
                                Name           = 'db1'
                                Status         = 'Normal'
                                ReadOnly       = 'false'
                                IsSystemObject = 'false'
                                RecoveryModel  = 'Full'
                                Owner          = 'sa'
                                IsAccessible   = $true
                            }
                    }
                } #object
            } -ModuleName dbatools #mock connect-sqlserver
            function Invoke-QueryDBlastUsed { }
            Mock Invoke-QueryDBlastUsed -MockWith {
                [object]
                @{
                    dbname     = 'db1'
                    last_read  = (Get-Date).AddHours(-1)
                    last_write = (Get-Date).AddHours(-1)
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
        It "Validates that Connect-SqlInstance Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Connect-SqlInstance'
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
