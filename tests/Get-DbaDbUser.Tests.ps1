$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemUser', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $tempguid = [guid]::newguid();
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$DBUserName] FOR LOGIN [$DBUserName]
    WITH DEFAULT_SCHEMA = dbo;
"@
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $CreateTestUser -Database master
    }
    AfterAll {
        $DropTestUser = "DROP User [$DBUserName];"
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $DropTestUser -Database master
    }

    Context "Partition Functions are correctly located" {
        $results1 = Get-DbaDbUser -SqlInstance $script:instance2 -Database master | Where-object {$_.name -eq "$DBUserName"} | Select-Object *
        $results2 = Get-DbaDbUser -SqlInstance $script:instance2

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
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
            $results1.HasDBAccess | Should -Be $true
        }

        It "Should not Throw an Error" {
            {Get-DbaDbUser -SqlInstance $script:instance2 -ExcludeDatabase master -ExcludeSystemUser } | Should -not -Throw
        }
    }
}