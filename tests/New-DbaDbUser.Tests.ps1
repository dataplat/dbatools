$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeSystem', 'Login', 'Username', 'DefaultSchema', 'ExternalProvider', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolscidb_$(Get-Random)"
        $userName = "dbatoolscidb_UserWithLogin"
        $userNameWithoutLogin = "dbatoolscidb_UserWithoutLogin"

        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $null = New-DbaLogin -SqlInstance $script:instance2 -Login $userName -Password $securePassword -Force
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $script:instance2 -Login $userName -Confirm:$false
    }
    Context "Test error handling" {
        It "Tries to create the user with an invalid default schema" {
            $results = New-DbaDbUser -SqlInstance $script:instance2 -Database $dbname -Login $userName -DefaultSchema invalidSchemaName -WarningVariable warningMessage
            $results | Should -BeNullOrEmpty
            $warningMessage | Should -BeLike "*Invalid DefaultSchema*"
        }
    }
    Context "Should create the user with login" {
        It "Creates the user and get it" {
            New-DbaDbUser -SqlInstance $script:instance2 -Database $dbname -Login $userName -DefaultSchema guest
            $newDbUser = Get-DbaDbUser -SqlInstance $script:instance2 -Database $dbname | Where-Object Name -eq $userName
            $newDbUser.Name | Should Be $userName
            $newDbUser.DefaultSchema | Should -Be 'guest'
        }
    }
    Context "Should create the user without login" {
        It "Creates the user and get it. Login property is empty" {
            New-DbaDbUser -SqlInstance $script:instance2 -Database $dbname -User $userNameWithoutLogin -DefaultSchema guest
            $results = Get-DbaDbUser -SqlInstance $script:instance2 -Database $dbname | Where-Object Name -eq $userNameWithoutLogin
            $results.Name | Should Be $userNameWithoutLogin
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
            $null = New-DbaLogin -SqlInstance $script:instance2 -Login $loginName -Password $securePassword -Force
            $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbs
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbs -Confirm:$false
            $null = Remove-DbaLogin -SqlInstance $script:instance2 -Login $loginName -Confirm:$false
        }
        It "Should add login to all databases provided" {
            $results = New-DbaDbUser -SqlInstance $script:instance2 -Login $loginName -Database $dbs -Force -EnableException
            $results.Count | Should -Be 3
            $results.Name | Should -Be $loginName, $loginName, $loginName
            $results.DefaultSchema | Should -Be dbo, dbo, dbo
        }
    }
}