#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbUser",
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
                "IncludeSystem",
                "User",
                "Login",
                "SecurePassword",
                "ExternalProvider",
                "DefaultSchema",
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

        $dbname = "dbatoolscidb_$(Get-Random)"
        $userName = "dbatoolscidb_UserWithLogin"
        $userNameWithPassword = "dbatoolscidb_UserWithPassword"
        $userNameWithoutLogin = "dbatoolscidb_UserWithoutLogin"

        $password = "MyV3ry`$ecur3P@ssw0rd"
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $userName -Password $securePassword -Force
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname
        $dbContainmentSpValue = (Get-DbaSpConfigure -SqlInstance $TestConfig.instance2 -Name ContainmentEnabled).ConfiguredValue
        $null = Set-DbaSpConfigure -SqlInstance $TestConfig.instance2 -Name ContainmentEnabled -Value 1
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "ALTER DATABASE [$dbname] SET CONTAINMENT = PARTIAL WITH NO_WAIT"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $userName -Confirm:$false
        $null = Set-DbaSpConfigure -SqlInstance $TestConfig.instance2 -Name ContainmentEnabled -Value $dbContainmentSpValue
    }
    Context "Test error handling" {
        It "Tries to create the user with an invalid default schema" {
            $results = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $userName -DefaultSchema invalidSchemaName -WarningVariable warningMessage -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $warningMessage | Should -BeLike "*Schema * does not exist in database*"
        }
    }
    Context "Should create the user with login" {
        It "Creates the user and get it" {
            New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $userName -DefaultSchema guest
            $newDbUser = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname | Where-Object Name -eq $userName
            $newDbUser.Name | Should -Be $userName
            $newDbUser.DefaultSchema | Should -Be "guest"
        }
    }
    Context "Should create the user with password" {
        It "Creates the contained sql user and get it." {
            New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Username $userNameWithPassword -Password $securePassword -DefaultSchema guest
            $newDbUser = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname | Where-Object Name -eq $userNameWithPassword
            $newDbUser.Name | Should -Be $userNameWithPassword
            $newDbUser.DefaultSchema | Should -Be "guest"
        }
    }
    Context "Should create the user without login" {
        It "Creates the user and get it. Login property is empty" {
            New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -User $userNameWithoutLogin -DefaultSchema guest
            $results = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname | Where-Object Name -eq $userNameWithoutLogin
            $results.Name | Should -Be $userNameWithoutLogin
            $results.DefaultSchema | Should -Be "guest"
            $results.Login | Should -BeNullOrEmpty
        }
    }
    Context "Should run with multiple databases" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbs = "dbatoolscidb0_$(Get-Random)", "dbatoolscidb1_$(Get-Random)", "dbatoolscidb3_$(Get-Random)"
            $loginName = "dbatoolscidb_Login$(Get-Random)"

            $password = "MyV3ry`$ecur3P@ssw0rd"
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $loginName -Password $securePassword -Force
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbs
            $accessibleDbCount = (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -OnlyAccessible).count

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbs -Confirm:$false
            $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $loginName -Confirm:$false
        }
        It "Should add login to all databases provided" {
            $results = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Login $loginName -Database $dbs -Force -EnableException
            $results.Count | Should -Be 3
            $results.Name | Should -Be $loginName, $loginName, $loginName
            $results.DefaultSchema | Should -Be "dbo", "dbo", "dbo"
        }

        It "Should add user to all user databases" {
            $results = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Login $loginName -Force -EnableException
            $results.Count | Should -Be $accessibleDbCount
            $results.Name | Get-Unique | Should -Be $loginName
        }
    }
}