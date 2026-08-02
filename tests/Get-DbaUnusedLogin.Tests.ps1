#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaUnusedLogin",
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
                "Login",
                "ExcludeLogin",
                "ExcludeSystemLogin",
                "Database",
                "ExcludeDatabase",
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

        $random = Get-Random
        $loginPassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force

        # Between them these logins cover every reason the command has to keep or drop a login.
        $unusedLoginName = "dbatoolsci_unused_$random"
        $mappedLoginName = "dbatoolsci_mapped_$random"
        $roleLoginName = "dbatoolsci_role_$random"
        $ownerLoginName = "dbatoolsci_owner_$random"
        $pipeLoginName = "dbatoolsci_pipe_$random"

        $mappedDbName = "dbatoolsci_mappeddb_$random"
        $ownedDbName = "dbatoolsci_owneddb_$random"
        $offlineDbName = "dbatoolsci_offlinedb_$random"

        foreach ($newLogin in $unusedLoginName, $mappedLoginName, $roleLoginName, $ownerLoginName, $pipeLoginName) {
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $newLogin -SecurePassword $loginPassword
        }

        # A login with a database user is in use.
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $mappedDbName
        $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $mappedDbName -Login $mappedLoginName -User $mappedLoginName

        # A database owner has no explicit user, but dbo carries the SID of the owning login.
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $ownedDbName -Owner $ownerLoginName

        # A login in a server role is in use even with no database user anywhere.
        $null = Add-DbaServerRoleMember -SqlInstance $TestConfig.InstanceSingle -ServerRole dbcreator -Login $roleLoginName

        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $offlineDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Databases first: SQL Server refuses to drop a login that owns a database.
        $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -Online -Force -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $mappedDbName, $ownedDbName, $offlineDbName -ErrorAction SilentlyContinue
        # The pipeline test drops its own login, so this cleanup is deliberately best effort.
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $unusedLoginName, $mappedLoginName, $roleLoginName, $ownerLoginName, $pipeLoginName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    }

    Context "When looking for unused logins on an instance" {
        BeforeAll {
            $allResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle)
            $allResultNames = $allResults.Name
        }

        It "Returns a login that has no server role and no database user" {
            $allResultNames | Should -Contain $unusedLoginName
        }

        It "Does not return a login that is mapped to a database user" {
            $allResultNames | Should -Not -Contain $mappedLoginName
        }

        It "Does not return a login that belongs to a server role" {
            $allResultNames | Should -Not -Contain $roleLoginName
        }

        It "Does not return a login that owns a database" {
            $allResultNames | Should -Not -Contain $ownerLoginName
        }

        It "Does not return sa, which cannot be dropped" {
            $allResultNames | Should -Not -Contain "sa"
        }

        It "Does not return the ## logins that SQL Server creates for itself" {
            $allResultNames | Where-Object { $PSItem -like "##*" } | Should -BeNullOrEmpty
        }

        It "Returns SMO login objects so the results pipe into the other login commands" {
            $allResults[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Login
        }

        It "Stamps the connection context onto every result" {
            $unusedResult = $allResults | Where-Object Name -eq $unusedLoginName
            $unusedResult.ComputerName | Should -Not -BeNullOrEmpty
            $unusedResult.InstanceName | Should -Not -BeNullOrEmpty
            $unusedResult.SqlInstance | Should -Not -BeNullOrEmpty
            $unusedResult.SidString | Should -Match "^0x"
        }
    }

    Context "When filtering which logins are checked" {
        It "Returns only the requested login when Login is used" {
            $loginResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -Login $unusedLoginName)
            $loginResults.Name | Should -Be $unusedLoginName
        }

        It "Returns nothing when Login names a login that is in use" {
            $inUseResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -Login $mappedLoginName, $roleLoginName, $ownerLoginName)
            $inUseResults | Should -BeNullOrEmpty
        }

        It "Drops the requested login from the results when ExcludeLogin is used" {
            $excludedResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeLogin $unusedLoginName)
            $excludedResults.Name | Should -Not -Contain $unusedLoginName
        }

        It "Leaves out the built-in Windows principals when ExcludeSystemLogin is used" {
            $noSystemResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeSystemLogin)
            $noSystemResults.Name | Where-Object { $PSItem -like "NT AUTHORITY\*" -or $PSItem -like "NT SERVICE\*" -or $PSItem -like "BUILTIN\*" } | Should -BeNullOrEmpty
            $noSystemResults.Name | Should -Contain $unusedLoginName
        }
    }

    Context "When the search is narrowed to a subset of databases" {
        It "Reports a mapped login as unused once its database is excluded" {
            $excludedDbResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $mappedDbName)
            $excludedDbResults.Name | Should -Contain $mappedLoginName
        }

        It "Reports a mapped login as unused when Database names only other databases" {
            $otherDbResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -Database master -Login $mappedLoginName)
            $otherDbResults.Name | Should -Be $mappedLoginName
        }

        It "Warns about a database that does not exist, because a typo searches nothing and calls every login unused" {
            $typoDbName = "dbatoolsci_nosuchdb_$random"
            $null = Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -Database $typoDbName -WarningVariable typoWarning
            $typoWarning | Should -Match $typoDbName
        }
    }

    Context "When a database cannot be opened" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -Offline -Force
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $offlineResults = @(Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -Login $unusedLoginName -WarningVariable offlineWarning)
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -Online -Force -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns which databases were not searched, because a login mapped only there looks unused" {
            $offlineWarning | Should -Match $offlineDbName
        }

        It "Still returns the unused login and records the databases it could not check" {
            $offlineResults.Name | Should -Be $unusedLoginName
            $offlineResults.UncheckedDatabase | Should -Contain $offlineDbName
        }
    }

    Context "When the results are piped to another login command" {
        It "Removes the unused login it was handed" {
            $null = Get-DbaUnusedLogin -SqlInstance $TestConfig.InstanceSingle -Login $pipeLoginName | Remove-DbaLogin
            $remainingLogin = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $pipeLoginName
            $remainingLogin | Should -BeNullOrEmpty
        }
    }
}
