#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbOrphanUser",
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
                "User",
                "Force",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $dbname = "dbatoolsci_$random"
        $login1 = "dbatoolssci_user1_$random"
        $login2 = "dbatoolssci_user2_$random"
        $schema = "dbatoolssci_Schema_$random"
        $securePassword = ConvertTo-SecureString "MyV3ry`$ecur3P@ssw0rd" -AsPlainText -Force
        $plaintext = "BigOlPassword!"

        $null = New-DbaDatabase -SqlInstance $server -Name $dbname -Owner sa

        $loginWindows = "db$random"
        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName
        $splatInvoke = @{
            ComputerName = $computerName
            ScriptBlock  = { New-LocalUser -Name $args[0] -Password $args[1] -Disabled:$false }
            ArgumentList = $loginWindows, $securePassword
        }
        Invoke-Command2 @splatInvoke

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    BeforeEach {
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login2 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "$computerName\$loginWindows" -Force

        $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Login $login1 -Username $login1
        $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Login $login2 -Username $login2
        $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Login "$computerName\$loginWindows" -Username "$computerName\$loginWindows" -Force
        $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database msdb -Login $login1 -Username $login1 -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database msdb -Login $login2 -Username $login2 -IncludeSystem
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login2
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "$computerName\$loginWindows"
    }
    AfterEach {
        $users = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb
        if ($users.Name -contains $login1) {
            $null = Remove-DbaDbUser $TestConfig.InstanceSingle -Database $dbname, msdb -User $login1
        }
        if ($users.Name -contains $login2) {
            $null = Remove-DbaDbUser $TestConfig.InstanceSingle -Database $dbname, msdb -User $login2
        }
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ErrorAction SilentlyContinue
        $splatInvoke = @{
            ComputerName = $computerName
            ScriptBlock  = { Remove-LocalUser -Name $args[0] -ErrorAction SilentlyContinue }
            ArgumentList = $loginWindows
        }
        Invoke-Command2 @splatInvoke

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "Removes Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb

        $results0.Name -contains $login1 | Should -Be $true
        $results0.Name -contains $login2 | Should -Be $true
        $results0.Count | Should -BeGreaterThan $results1.Count
    }

    It "Removes selected Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -User $login1
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb

        $results0.Count | Should -BeGreaterThan $results1.Count
        $results1.Name -contains $login1 | Should -Be $false
        $results1.Name -contains $login2 | Should -Be $true
    }

    It "Removes Orphan Users for Database" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name -contains $login1 | Should -Be $true
        $results1.Name -contains $login2 | Should -Be $true
        $results1.Database -contains "msdb" | Should -Be $false
        $results1.Database -contains $dbname | Should -Be $true

    }

    It "Removes Orphan Users except for excluded databases" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name -contains $login1 | Should -Be $true
        $results1.Name -contains $login2 | Should -Be $true
        $results1.Database -contains "msdb" | Should -Be $true
        $results1.Database -contains $dbname | Should -Be $false
    }

    It "Removes Orphan Users with unmapped logins if force specified" {
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login2 -Password $securePassword -Force

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -User $login1 -Force
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -User $login2 -WarningAction SilentlyContinue
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb

        $results1.Name -contains $login1 | Should -Be $false
        $results1.Name -contains $login2 | Should -Be $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login2

    }

    It "Removes Orphan Logins that own Schemas without objects " {
        $sql = "CREATE SCHEMA $schema AUTHORIZATION $login2"
        $server.Query($sql, $dbname)

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb -User $login1, $login2 -Force -WarningAction SilentlyContinue
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname, msdb

        $results1.Name -contains $login1 | Should -Be $false
        $results1.Name -contains $login2 | Should -Be $false

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

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -User $login1 -WarningAction SilentlyContinue
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -User $login2 -Force
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname

        $results1.Name -contains $login1 | Should -Be $true
        $results1.Name -contains $login2 | Should -Be $false

        $sql = "DROP TABLE $schema.test1;DROP TABLE [$login2].test2;DROP SCHEMA $schema;DROP SCHEMA [$login2];"
        $server.Query($sql, $dbname)
    }

    It "Removes the orphaned windows login" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -User "$($TestConfig.InstanceSingle)\$loginWindows"
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        $results1.Name -contains $loginWindows | Should -Be $false
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a scenario where schema operations occur (which generates output)
            $testLogin = "dbatoolssci_outputtest_$random"
            $testSchema = "dbatoolssci_outputschema_$random"

            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $testLogin -Password $securePassword -Force -EnableException
            $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Login $testLogin -Username $testLogin -EnableException

            # Create a schema owned by the test user
            $sql = "CREATE SCHEMA $testSchema AUTHORIZATION $testLogin"
            $server.Query($sql, $dbname)

            # Make the user orphaned by removing the login
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $testLogin -EnableException

            # Remove the orphan user with Force (to handle schema ownership)
            $result = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database $dbname -User $testLogin -Force -EnableException
        }

        AfterAll {
            # Cleanup - drop the schema if it still exists
            try {
                $sql = "IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = '$testSchema') DROP SCHEMA $testSchema"
                $server.Query($sql, $dbname)
            } catch {
                # Ignore cleanup errors
            }
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DatabaseName',
                'SchemaName',
                'Action',
                'SchemaOwnerBefore',
                'SchemaOwnerAfter'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns schema operation details when schemas are modified" {
            $result | Should -Not -BeNullOrEmpty
            $result.DatabaseName | Should -Be $dbname
            $result.SchemaName | Should -Be $testSchema
            $result.Action | Should -Be "ALTER OWNER"
            $result.SchemaOwnerAfter | Should -Be "dbo"
        }
    }
}