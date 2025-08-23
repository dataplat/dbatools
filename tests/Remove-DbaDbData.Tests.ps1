#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbData",
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
                "InputObject",
                "Path",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname1 -Owner sa
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbname1 -Query "

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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname1

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        BeforeAll {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbname1 -Query "
                insert into dept values ('hr');
                insert into emp values (1);"
        }

        It "Removes Data for a specified database" {
            Remove-DbaDbData -SqlInstance $TestConfig.instance2 -Database $dbname1
            (Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbname1 -Query "Select count(*) as rwCnt from dept").rwCnt | Should -Be 0
        }

        It "Foreign Keys are recreated" {
            $fkeys = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname1
            $fkeys.Name | Should -Be "FK_dept"
        }

        It "Foreign Keys are trusted" {
            $fkeys = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname1
            $fkeys.IsChecked | Should -Be $true
        }

        It "Views are recreated" {
            (Get-DbaDbView -SqlInstance $TestConfig.instance2 -Database $dbname1 -ExcludeSystemView).Name | Should -Be "vw_emp"
        }
    }

    Context "Functionality - Pipe database" {
        BeforeAll {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbname1 -Query "
                insert into dept values ('hr');
                insert into emp values (1);"
        }

        It "Removes Data for a specified database" {
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname1 | Remove-DbaDbData
            (Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbname1 -Query "Select count(*) as rwCnt from dept").rwCnt | Should -Be 0
        }

        It "Foreign Keys are recreated" {
            $fkeys = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname1
            $fkeys.Name | Should -Be "FK_dept"
        }

        It "Foreign Keys are trusted" {
            $fkeys = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname1
            $fkeys.IsChecked | Should -Be $true
        }

        It "Views are recreated" {
            (Get-DbaDbView -SqlInstance $TestConfig.instance2 -Database $dbname1 -ExcludeSystemView).Name | Should -Be "vw_emp"
        }
    }

    Context "Functionality - Pipe server" {
        BeforeAll {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbname1 -Query "
                insert into dept values ('hr');
                insert into emp values (1);"
        }

        It "Removes Data for a specified database" {
            Connect-DbaInstance -SqlInstance $TestConfig.instance2 | Remove-DbaDbData -Database $dbname1
            (Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbname1 -Query "Select count(*) as rwCnt from dept").rwCnt | Should -Be 0
        }

        It "Foreign Keys are recreated" {
            $fkeys = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname1
            $fkeys.Name | Should -Be "FK_dept"
        }

        It "Foreign Keys are trusted" {
            $fkeys = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname1
            $fkeys.IsChecked | Should -Be $true
        }

        It "Views are recreated" {
            (Get-DbaDbView -SqlInstance $TestConfig.instance2 -Database $dbname1 -ExcludeSystemView).Name | Should -Be "vw_emp"
        }
    }
}