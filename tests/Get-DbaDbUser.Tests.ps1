param($ModuleName = 'dbatools')

Describe "Get-DbaDbUser Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbUser
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
        It "Should have ExcludeSystemUser as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemUser -Type SwitchParameter
        }
        It "Should have User as a parameter" {
            $CommandUnderTest | Should -HaveParameter User -Type String[]
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }
}

Describe "Get-DbaDbUser Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $tempguid = [guid]::newguid();
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $DBUserName2 = "dbatoolssci2_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$DBUserName] FOR LOGIN [$DBUserName]
    WITH DEFAULT_SCHEMA = dbo;
CREATE LOGIN [$DBUserName2]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$DBUserName2] FOR LOGIN [$DBUserName2]
    WITH DEFAULT_SCHEMA = dbo;
"@
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $CreateTestUser -Database master
    }

    AfterAll {
        $DropTestUser = @"
DROP USER [$DBUserName];
DROP USER [$DBUserName2];
DROP LOGIN [$DBUserName];
DROP LOGIN [$DBUserName2];
"@
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $DropTestUser -Database master
    }

    Context "Users are correctly located" {
        BeforeAll {
            $results1 = Get-DbaDbUser -SqlInstance $script:instance2 -Database master | Where-Object { $_.name -eq "$DBUserName" } | Select-Object *
            $results2 = Get-DbaDbUser -SqlInstance $script:instance2

            $resultsByUser = Get-DbaDbUser -SqlInstance $script:instance2 -Database master -User $DBUserName2
            $resultsByMultipleUser = Get-DbaDbUser -SqlInstance $script:instance2 -User $DBUserName, $DBUserName2

            $resultsByLogin = Get-DbaDbUser -SqlInstance $script:instance2 -Database master -Login $DBUserName2
            $resultsByMultipleLogin = Get-DbaDbUser -SqlInstance $script:instance2 -Login $DBUserName, $DBUserName2
        }

        It "Should execute and return results" {
            $results2 | Should -Not -BeNullOrEmpty
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -BeNullOrEmpty
        }

        It "Should have matching login and username of $DBUserName" {
            $results1.name | Should -Be "$DBUserName"
            $results1.login | Should -Be "$DBUserName"
        }

        It "Should have a login type of SqlLogin" {
            $results1.LoginType | Should -Be 'SqlLogin'
        }

        It "Should have DefaultSchema of dbo" {
            $results1.DefaultSchema | Should -Be "dbo"
        }

        It "Should have database access" {
            $results1.HasDBAccess | Should -BeTrue
        }

        It "Should not Throw an Error" {
            { Get-DbaDbUser -SqlInstance $script:instance2 -ExcludeDatabase master -ExcludeSystemUser } | Should -Not -Throw
        }

        It "Should return a specific user" {
            $resultsByUser.Name | Should -Be $DBUserName2
            $resultsByUser.Database | Should -Be master
        }

        It "Should return two specific users" {
            $resultsByMultipleUser.Name | Should -Be @($DBUserName, $DBUserName2)
            $resultsByMultipleUser.Database | Should -Be @('master', 'master')
        }

        It "Should return a specific user for the given login" {
            $resultsByLogin.Name | Should -Be $DBUserName2
            $resultsByLogin.Database | Should -Be master
        }

        It "Should return two specific users for the given logins" {
            $resultsByMultipleLogin.Name | Should -Be @($DBUserName, $DBUserName2)
            $resultsByMultipleLogin.Database | Should -Be @('master', 'master')
        }
    }
}
