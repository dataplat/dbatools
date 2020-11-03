$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'Path', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
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
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -confirm:$false
    }

    Context "Functionality" {
        BeforeAll {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query "
                insert into dept values ('hr');
                insert into emp values (1);"
        }

        It 'Removes Data for a specified database' {
            Remove-DbaDbData -SqlInstance $script:instance2 -Database $dbname1 -Confirm:$false
            (Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query 'Select count(*) as rwCnt from dept').rwCnt | Should Be 0
        }

        $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
        It 'Foreign Keys are recreated' {
            $fkeys.Name | Should Be 'FK_dept'
        }

        It 'Foreign Keys are trusted' {
            $fkeys.IsChecked | Should Be $true
        }

        It 'Views are recreated' {
            (Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView).Name | Should Be 'vw_emp'
        }
    }

    Context "Functionality - Pipe database" {
        BeforeAll {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query "
                insert into dept values ('hr');
                insert into emp values (1);"
        }

        It 'Removes Data for a specified database' {
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 | Remove-DbaDbData -Confirm:$false
            (Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query 'Select count(*) as rwCnt from dept').rwCnt | Should Be 0
        }

        $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
        It 'Foreign Keys are recreated' {
            $fkeys.Name | Should Be 'FK_dept'
        }

        It 'Foreign Keys are trusted' {
            $fkeys.IsChecked | Should Be $true
        }

        It 'Views are recreated' {
            (Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView).Name | Should Be 'vw_emp'
        }
    }

    Context "Functionality - Pipe server" {
        BeforeAll {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query "
                insert into dept values ('hr');
                insert into emp values (1);"
        }

        It 'Removes Data for a specified database' {
            Connect-DbaInstance -SqlInstance $script:instance2 | Remove-DbaDbData -Database $dbname1 -Confirm:$false
            (Invoke-DbaQuery -SqlInstance $script:instance2 -Database $dbname1 -Query 'Select count(*) as rwCnt from dept').rwCnt | Should Be 0
        }

        $fkeys = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname1
        It 'Foreign Keys are recreated' {
            $fkeys.Name | Should Be 'FK_dept'
        }

        It 'Foreign Keys are trusted' {
            $fkeys.IsChecked | Should Be $true
        }

        It 'Views are recreated' {
            (Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView).Name | Should Be 'vw_emp'
        }
    }
}
