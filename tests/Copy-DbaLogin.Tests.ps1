$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    $logins = "claudio", "port", "tester"

    foreach ($instance in $instances) {
        foreach ($login in $logins) {
            if ($l = Get-DbaLogin -SqlInstance $instance -Login $login) {
                Get-DbaProcess -SqlInstance $instance -Login $login | Stop-DbaProcess
                $l.Drop()
            }
        }
    }

    $null = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -InputFile $script:appveyorlabrepo\sql2008-scripts\logins.sql

    Context "Copy login with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaLogin -Source $script:instance1 -Destination $script:instance2 -Login Tester
            $results.Status | Should Be "Successful"
        }

        It "Should retain its same properties" {

            $login1 = Get-Dbalogin -SqlInstance $script:instance1 -login Tester
            $login2 = Get-Dbalogin -SqlInstance $script:instance2 -login Tester

            $login2 | Should Not BeNullOrEmpty

            # Compare its value
            $login1.Name | Should Be $login2.Name
            $login1.Language | Should Be $login2.Language
            $login1.Credential | Should be $login2.Credential
            $login1.DefaultDatabase | Should be $login2.DefaultDatabase
            $login1.IsDisabled | Should be $login2.IsDisabled
            $login1.IsLocked | Should be $login2.IsLocked
            $login1.IsPasswordExpired | Should be $login2.IsPasswordExpired
            $login1.PasswordExpirationEnabled | Should be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should be $login2.PasswordPolicyEnforced
            $login1.Sid | Should be $login2.Sid
            $login1.Status | Should be $login2.Status
        }

        It "Should login with newly created Sql Login (also tests credential login) and gets name" {
            $password = ConvertTo-SecureString -Force -AsPlainText tester1
            $cred = New-Object System.Management.Automation.PSCredential ("tester", $password)
            $s = Connect-DbaInstance -SqlInstance $script:instance1 -Credential $cred
            $s.Name | Should Be $script:instance1
        }
    }

    Context "No overwrite" {
        $results = Copy-DbaLogin -Source $script:instance1 -Destination $script:instance2 -Login tester
        It "Should say skipped" {
            $results.Status | Should be "Skipped"
            $results.Notes | Should be "Already exists"
        }
    }
}
