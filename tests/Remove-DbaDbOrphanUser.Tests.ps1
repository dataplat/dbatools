$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'User', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $random = Get-Random
        $dbname = "dbatoolsci_$random"
        $login1 = "dbatoolssci_user1_$random"
        $login2 = "dbatoolssci_user2_$random"
        $schema = "dbatoolssci_Schema_$random"
        $securePassword = ConvertTo-SecureString 'MyV3ry$ecur3P@ssw0rd' -AsPlainText -Force
        $plaintext = 'BigOlPassword!'

        $null = New-DbaDatabase -SqlInstance $server -Name $dbname -Owner sa

        $loginWindows = "db$random"

        $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $loginWindows, $plaintext -ComputerName $TestConfig.instance2
    }
    BeforeEach {
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login "$($TestConfig.instance2)\$loginWindows" -Force

        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $login1 -Username $login1
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $login2 -Username $login2
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login "$($TestConfig.instance2)\$loginWindows" -Username "$($TestConfig.instance2)\$loginWindows"
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database msdb -Login $login1 -Username $login1 -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database msdb -Login $login2 -Username $login2 -IncludeSystem
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login "$($TestConfig.instance2)\$loginWindows" -Confirm:$false
    }
    AfterEach {
        $users = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb
        if ($users.Name -contains $login1) {
            $null = Remove-DbaDbUser $TestConfig.instance2 -Database $dbname, msdb -User $login1
        }
        if ($users.Name -contains $login2) {
            $null = Remove-DbaDbUser $TestConfig.instance2 -Database $dbname, msdb -User $login2
        }
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -confirm:$false
        $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $loginWindows -ComputerName $TestConfig.instance2
    }

    It "Removes Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results0.Name -contains $login1 | Should Be $true
        $results0.Name -contains $login2 | Should Be $true
        $results0.Count | Should BeGreaterThan $results1.Count
    }

    It "Removes selected Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -User $login1
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results0.Count | Should BeGreaterThan $results1.Count
        $results1.Name -contains $login1 | Should Be $false
        $results1.Name -contains $login2 | Should Be $true
    }

    It "Removes Orphan Users for Database" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name -contains $login1 | Should Be $true
        $results1.Name -contains $login2 | Should Be $true
        $results1.Database -contains 'msdb' | Should Be $false
        $results1.Database -contains $dbname | Should Be $true

    }

    It "Removes Orphan Users except for excluded databases" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -ExcludeDatabase msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name -contains $login1 | Should Be $true
        $results1.Name -contains $login2 | Should Be $true
        $results1.Database -contains 'msdb' | Should Be $true
        $results1.Database -contains $dbname | Should Be $false
    }

    It "Removes Orphan Users with unmapped logins if force specified" {
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Password $securePassword -Force

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -User $login1 -Force
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -User $login2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results1.Name -contains $login1 | Should Be $false
        $results1.Name -contains $login2 | Should Be $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Confirm:$false

    }

    It "Removes Orphan Logins that own Schemas without objects " {
        $sql = "CREATE SCHEMA $schema AUTHORIZATION $login2"
        $server.Query($sql, $dbname)

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb -User $login1, $login2 -Force
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results1.Name -contains $login1 | Should Be $false
        $results1.Name -contains $login2 | Should Be $false

        $sql = "DROP SCHEMA $schema"
        $server.Query($sql, $dbname)
    }

    It "Removes Orphan Logins that own Schemas with objects only if force specified" {
        $sql = "CREATE SCHEMA $schema AUTHORIZATION $login1"
        $server.Query($sql, $dbname)
        $sql = "CREATE SCHEMA $login2 AUTHORIZATION $login2"
        $server.Query($sql, $dbname)
        $sql = "CREATE TABLE $schema.test1(Id int NULL)"
        $server.Query($sql, $dbname)
        $sql = "CREATE TABLE [$login2].test2(Id int NULL)"
        $server.Query($sql, $dbname)

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname -User $login1
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname -User $login2 -Force
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname

        $results1.Name -contains $login1 | Should Be $true
        $results1.Name -contains $login2 | Should Be $false

        $sql = "DROP TABLE $schema.test1;DROP TABLE [$login2].test2;DROP SCHEMA $schema;DROP SCHEMA [$login2];"
        $server.Query($sql, $dbname)
    }

    It "Removes the orphaned windows login" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname -User "$($TestConfig.instance2)\$loginWindows"
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname
        $results1.Name -contains $loginWindows | Should -Be $false
    }
}
