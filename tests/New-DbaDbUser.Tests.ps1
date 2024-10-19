param($ModuleName = 'dbatools')

Describe "New-DbaDbUser" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolscidb_$(Get-Random)"
        $userName = "dbatoolscidb_UserWithLogin"
        $userNameWithPassword = "dbatoolscidb_UserWithPassword"
        $userNameWithoutLogin = "dbatoolscidb_UserWithoutLogin"

        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $userName -Password $securePassword -Force
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname
        $dbContainmentSpValue = (Get-DbaSpConfigure -SqlInstance $global:instance2 -Name ContainmentEnabled).ConfiguredValue
        $null = Set-DbaSpConfigure -SqlInstance $global:instance2 -Name ContainmentEnabled -Value 1
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "ALTER DATABASE [$dbname] SET CONTAINMENT = PARTIAL WITH NO_WAIT"
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $userName -Confirm:$false
        $null = Set-DbaSpConfigure -SqlInstance $global:instance2 -Name ContainmentEnabled -Value $dbContainmentSpValue
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbUser
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have IncludeSystem as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystem
        }
        It "Should have User as a parameter" {
            $CommandUnderTest | Should -HaveParameter User
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword
        }
        It "Should have ExternalProvider as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExternalProvider
        }
        It "Should have DefaultSchema as a parameter" {
            $CommandUnderTest | Should -HaveParameter DefaultSchema
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Test error handling" {
        It "Tries to create the user with an invalid default schema" {
            $warningMessage = $null
            $results = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $userName -DefaultSchema invalidSchemaName -WarningVariable warningMessage
            $results | Should -BeNullOrEmpty
            $warningMessage | Should -BeLike "*Schema * does not exist in database*"
        }
    }

    Context "Should create the user with login" {
        It "Creates the user and get it" {
            New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $userName -DefaultSchema guest
            $newDbUser = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname | Where-Object Name -eq $userName
            $newDbUser.Name | Should -Be $userName
            $newDbUser.DefaultSchema | Should -Be 'guest'
        }
    }

    Context "Should create the user with password" {
        It "Creates the contained sql user and get it." {
            New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Username $userNameWithPassword -Password $securePassword -DefaultSchema guest
            $newDbUser = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname | Where-Object Name -eq $userNameWithPassword
            $newDbUser.Name | Should -Be $userNameWithPassword
            $newDbUser.DefaultSchema | Should -Be 'guest'
        }
    }

    Context "Should create the user without login" {
        It "Creates the user and get it. Login property is empty" {
            New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -User $userNameWithoutLogin -DefaultSchema guest
            $results = Get-DbaDbUser -SqlInstance $global:instance2 -Database $dbname | Where-Object Name -eq $userNameWithoutLogin
            $results.Name | Should -Be $userNameWithoutLogin
            $results.DefaultSchema | Should -Be 'guest'
            $results.Login | Should -BeNullOrEmpty
        }
    }

    Context "Should run with multiple databases" {
        BeforeAll {
            $dbs = "dbatoolscidb0_$(Get-Random)", "dbatoolscidb1_$(Get-Random)", "dbatoolscidb3_$(Get-Random)"
            $loginName = "dbatoolscidb_Login$(Get-Random)"

            $password = 'MyV3ry$ecur3P@ssw0rd'
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $global:instance2 -Login $loginName -Password $securePassword -Force
            $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbs
            $accessibleDbCount = (Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem -OnlyAccessible).count
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbs -Confirm:$false
            $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $loginName -Confirm:$false
        }

        It "Should add login to all databases provided" {
            $results = New-DbaDbUser -SqlInstance $global:instance2 -Login $loginName -Database $dbs -Force -EnableException
            $results.Count | Should -Be 3
            $results.Name | Should -Be $loginName, $loginName, $loginName
            $results.DefaultSchema | Should -Be dbo, dbo, dbo
        }

        It "Should add user to all user databases" {
            $results = New-DbaDbUser -SqlInstance $global:instance2 -Login $loginName -Force -EnableException
            $results.Count | Should -Be $accessibleDbCount
            $results.Name | Get-Unique | Should -Be $loginName
        }
    }
}
