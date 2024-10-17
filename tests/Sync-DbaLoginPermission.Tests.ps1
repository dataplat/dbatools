param($ModuleName = 'dbatools')

Describe "Sync-DbaLoginPermission" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $tempguid = [guid]::newguid();
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$DBUserName] FOR LOGIN [$DBUserName]
    WITH DEFAULT_SCHEMA = dbo;
GRANT VIEW ANY DEFINITION to [$DBUserName];
"@
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $CreateTestUser -Database master

        #This is used later in the test
        $CreateTestLogin = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
"@
    }

    AfterAll {
        $DropTestUser = "DROP LOGIN [$DBUserName]"
        Invoke-DbaQuery -SqlInstance $script:instance2, $script:instance3 -Query $DropTestUser -Database master
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Sync-DbaLoginPermission
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have ExcludeLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLogin -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Verifying command output" {
        It "Should not have the user permissions of $DBUserName" {
            $permissionsBefore = Get-DbaUserPermission -SqlInstance $script:instance3 -Database master | Where-Object {$_.member -eq $DBUserName}
            $permissionsBefore | Should -BeNullOrEmpty
        }

        It "Should execute against active nodes" {
            #Creates the user on
            Invoke-DbaQuery -SqlInstance $script:instance3 -Query $CreateTestLogin
            $results = Sync-DbaLoginPermission -Source $script:instance2 -Destination $script:instance3 -Login $DBUserName -ExcludeLogin 'NotaLogin' -WarningVariable warn
            $results.Status | Should -Be 'Successful'
            $warn | Should -BeNullOrEmpty
        }

        It "Should have copied the user permissions of $DBUserName" {
            $permissionsAfter = Get-DbaUserPermission -SqlInstance $script:instance3 -Database master | Where-Object {$_.member -eq $DBUserName -and $_.permission -eq 'VIEW ANY DEFINITION' }
            $permissionsAfter.member | Should -Be $DBUserName
        }
    }
}
