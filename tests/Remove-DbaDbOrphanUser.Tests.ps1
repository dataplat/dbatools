param($ModuleName = 'dbatools')

Describe "Remove-DbaDbOrphanUser Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbOrphanUser
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have User as a parameter" {
            $CommandUnderTest | Should -HaveParameter User -Type Object[]
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Remove-DbaDbOrphanUser Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $random = Get-Random
        $dbname = "dbatoolsci_$random"
        $login1 = "dbatoolssci_user1_$random"
        $login2 = "dbatoolssci_user2_$random"
        $schema = "dbatoolssci_Schema_$random"
        $securePassword = ConvertTo-SecureString 'MyV3ry$ecur3P@ssw0rd' -AsPlainText -Force
        $plaintext = 'BigOlPassword!'

        $null = New-DbaDatabase -SqlInstance $server -Name $dbname -Owner sa

        $loginWindows = "db$random"

        $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $loginWindows, $plaintext -ComputerName $global:instance2
    }

    BeforeEach {
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login "$($global:instance2)\$loginWindows" -Force

        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $login1 -Username $login1
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $login2 -Username $login2
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login "$($global:instance2)\$loginWindows" -Username "$($global:instance2)\$loginWindows"
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database msdb -Login $login1 -Username $login1 -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database msdb -Login $login2 -Username $login2 -IncludeSystem
        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login "$($global:instance2)\$loginWindows" -Confirm:$false
    }

    AfterEach {
        $users = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb
        if ($users.Name -contains $login1) {
            $null = Remove-DbaDbUser $global:instance2 -Database $dbname, msdb -User $login1
        }
        if ($users.Name -contains $login2) {
            $null = Remove-DbaDbUser $global:instance2 -Database $dbname, msdb -User $login2
        }
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
        $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $loginWindows -ComputerName $global:instance2
    }

    It "Removes Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb

        $results0.Name | Should -Contain $login1
        $results0.Name | Should -Contain $login2
        $results0.Count | Should -BeGreaterThan $results1.Count
    }

    It "Removes selected Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -User $login1
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb

        $results0.Count | Should -BeGreaterThan $results1.Count
        $results1.Name | Should -Not -Contain $login1
        $results1.Name | Should -Contain $login2
    }

    It "Removes Orphan Users for Database" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -Database msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name | Should -Contain $login1
        $results1.Name | Should -Contain $login2
        $results1.Database | Should -Not -Contain 'msdb'
        $results1.Database | Should -Contain $dbname
    }

    It "Removes Orphan Users except for excluded databases" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -ExcludeDatabase msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name | Should -Contain $login1
        $results1.Name | Should -Contain $login2
        $results1.Database | Should -Contain 'msdb'
        $results1.Database | Should -Not -Contain $dbname
    }

    It "Removes Orphan Users with unmapped logins if force specified" {
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Password $securePassword -Force

        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -User $login1 -Force
        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -User $login2
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb

        $results1.Name | Should -Not -Contain $login1
        $results1.Name | Should -Contain $login2

        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Confirm:$false
    }

    It "Removes Orphan Logins that own Schemas without objects" {
        $sql = "CREATE SCHEMA $schema AUTHORIZATION $login2"
        $server.Query($sql, $dbname)

        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -Database $dbname, msdb -User $login1, $login2 -Force
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname, msdb

        $results1.Name | Should -Not -Contain $login1
        $results1.Name | Should -Not -Contain $login2

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

        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -Database $dbname -User $login1
        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -Database $dbname -User $login2 -Force
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname

        $results1.Name | Should -Contain $login1
        $results1.Name | Should -Not -Contain $login2

        $sql = "DROP TABLE $schema.test1;DROP TABLE [$login2].test2;DROP SCHEMA $schema;DROP SCHEMA [$login2];"
        $server.Query($sql, $dbname)
    }

    It "Removes the orphaned windows login" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $global:instance2 -Database $dbname -User "$($global:instance2)\$loginWindows"
        $results1 = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname
        $results1.Name | Should -Not -Contain $loginWindows
    }
}
