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
        Invoke-DbaQuery -SqlInstance $global:instance2 -Query $CreateTestUser -Database master

        #This is used later in the test
        $CreateTestLogin = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
"@
    }

    AfterAll {
        $DropTestUser = "DROP LOGIN [$DBUserName]"
        Invoke-DbaQuery -SqlInstance $global:instance2, $global:instance3 -Query $DropTestUser -Database master
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Sync-DbaLoginPermission
        }
        It "has the required parameter: <_>" -ForEach $params {
            $params = @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Login",
                "ExcludeLogin",
                "EnableException"
            )
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Verifying command output" {
        It "Should not have the user permissions of $DBUserName" {
            $permissionsBefore = Get-DbaUserPermission -SqlInstance $global:instance3 -Database master | Where-Object {$_.member -eq $DBUserName}
            $permissionsBefore | Should -BeNullOrEmpty
        }

        It "Should execute against active nodes" {
            #Creates the user on
            Invoke-DbaQuery -SqlInstance $global:instance3 -Query $CreateTestLogin
            $results = Sync-DbaLoginPermission -Source $global:instance2 -Destination $global:instance3 -Login $DBUserName -ExcludeLogin 'NotaLogin' -WarningVariable warn
            $results.Status | Should -Be 'Successful'
            $warn | Should -BeNullOrEmpty
        }

        It "Should have copied the user permissions of $DBUserName" {
            $permissionsAfter = Get-DbaUserPermission -SqlInstance $global:instance3 -Database master | Where-Object {$_.member -eq $DBUserName -and $_.permission -eq 'VIEW ANY DEFINITION' }
            $permissionsAfter.member | Should -Be $DBUserName
        }
    }
}
