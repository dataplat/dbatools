param($ModuleName = 'dbatools')

Describe "Remove-DbaDbData" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbData
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[]
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $dbname1 = "dbatoolsci_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname1 -Owner sa
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query "
            create table dept (
                deptid int identity(1,1) primary key,
                deptname varchar(10)
            );

            create table emp (
                empid int identity(1,1) primary key,
                deptid int,
                CONSTRAINT FK_dept FOREIGN key (deptid) REFERENCES dept (deptid)
                );

            GO

            Create View vw_emp as
            Select empid from emp;
            "
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -Confirm:$false
        }

        Context "Functionality" {
            BeforeEach {
                Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query "
                    insert into dept values ('hr');
                    insert into emp values (1);"
            }

            It 'Removes Data for a specified database' {
                Remove-DbaDbData -SqlInstance $script:instance2 -Database $dbname1 -Confirm:$false
                $result = Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query 'Select count(*) as rwCnt from dept'
                $result.rwCnt | Should -Be 0
            }

            It 'Foreign Keys are recreated' {
                $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
                $fkeys.Name | Should -Be 'FK_dept'
            }

            It 'Foreign Keys are trusted' {
                $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
                $fkeys.IsChecked | Should -Be $true
            }

            It 'Views are recreated' {
                $views = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView
                $views.Name | Should -Be 'vw_emp'
            }
        }

        Context "Functionality - Pipe database" {
            BeforeEach {
                Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query "
                    insert into dept values ('hr');
                    insert into emp values (1);"
            }

            It 'Removes Data for a specified database' {
                Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 | Remove-DbaDbData -Confirm:$false
                $result = Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query 'Select count(*) as rwCnt from dept'
                $result.rwCnt | Should -Be 0
            }

            It 'Foreign Keys are recreated' {
                $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
                $fkeys.Name | Should -Be 'FK_dept'
            }

            It 'Foreign Keys are trusted' {
                $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
                $fkeys.IsChecked | Should -Be $true
            }

            It 'Views are recreated' {
                $views = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView
                $views.Name | Should -Be 'vw_emp'
            }
        }

        Context "Functionality - Pipe server" {
            BeforeEach {
                Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query "
                    insert into dept values ('hr');
                    insert into emp values (1);"
            }

            It 'Removes Data for a specified database' {
                Connect-DbaInstance -SqlInstance $script:instance2 | Remove-DbaDbData -Database $dbname1 -Confirm:$false
                $result = Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query 'Select count(*) as rwCnt from dept'
                $result.rwCnt | Should -Be 0
            }

            It 'Foreign Keys are recreated' {
                $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
                $fkeys.Name | Should -Be 'FK_dept'
            }

            It 'Foreign Keys are trusted' {
                $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
                $fkeys.IsChecked | Should -Be $true
            }

            It 'Views are recreated' {
                $views = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView
                $views.Name | Should -Be 'vw_emp'
            }
        }
    }
}
