param($ModuleName = 'dbatools')

Describe "Test-DbaDbOwner Unit Tests" -Tag "UnitTests" {
    BeforeAll {
        # Import module or set up environment if needed
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbOwner
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have TargetLogin parameter" {
            $CommandUnderTest | Should -HaveParameter TargetLogin -Type String -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Functionality" {
        BeforeAll {
            # Mock Connect-SQLInstance
            Mock Connect-SQLInstance -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{
                    Name      = 'SQLServerName'
                    Databases = @(
                        @{
                            Name   = 'db1'
                            Status = 'Normal'
                            Owner  = 'sa'
                        }
                    )
                    Logins    = @(
                        @{
                            ID   = 1
                            Name = 'sa'
                        }
                    )
                }
            }
        }

        It "Should not throw when connecting to SQL Server" {
            { Test-DbaDbOwner -SqlInstance 'SQLServerName' } | Should -Not -Throw
        }

        It "Should return correct owner information for one database with no owner specified" {
            # Update mock for this specific test
            Mock Connect-SQLInstance -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{
                    DomainInstanceName = 'SQLServerName'
                    Databases          = @(
                        @{
                            Name   = 'db1'
                            Status = 'Normal'
                            Owner  = 'WrongOwner'
                        }
                    )
                    Logins             = @(
                        @{
                            ID   = 1
                            Name = 'sa'
                        }
                    )
                }
            }

            $Result = Test-DbaDbOwner -SqlInstance 'SQLServerName'
            $Result[0].SqlInstance | Should -Be 'SQLServerName'
            $Result[0].Database | Should -Be 'db1'
            $Result[0].DBState | Should -Be 'Normal'
            $Result[0].CurrentOwner | Should -Be 'WrongOwner'
            $Result[0].TargetOwner | Should -Be 'sa'
            $Result[0].OwnerMatch | Should -Be $false
        }

        It "Should handle non-existent target login" {
            Mock Stop-Function -ModuleName $ModuleName -MockWith { }

            $null = Test-DbaDbOwner -SqlInstance 'SQLServerName' -TargetLogin 'WrongLogin'
            Should -Invoke Stop-Function -ModuleName $ModuleName -Times 1 -Exactly
        }
    }
}

Describe "Test-DbaDbOwner Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $global:instance1 = "localhost"
        $dbname = "dbatoolsci_testdbowner"
        $server = Connect-DbaInstance -SqlInstance $global:instance1
        $null = $server.Query("CREATE DATABASE [$dbname]")
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
    }

    It "Should return the correct information including database, currentowner and targetowner" {
        $whoami = whoami
        $results = Test-DbaDbOwner -SqlInstance $global:instance1 -Database $dbname
        $results.Database | Should -Be $dbname
        $results.CurrentOwner | Should -Be $whoami
        $results.TargetOwner | Should -Be 'sa'
    }
}
