$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Login', 'ExcludeLogin', 'ExcludeSystemLogins', 'SyncSaName', 'OutFile', 'InputObject', 'LoginRenameHashtable', 'KillActiveConnection', 'Force', 'ExcludePermissionSync', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

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

    $null = Invoke-DbaQuery -SqlInstance $script:instance1 -InputFile $script:appveyorlabrepo\sql2008-scripts\logins.sql

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
            $s = Connect-DbaInstance -SqlInstance $script:instance1 -SqlCredential $cred
            $s.Name | Should Be $script:instance1
        }
    }

    Context "No overwrite" {
        $results = Copy-DbaLogin -Source $script:instance1 -Destination $script:instance2 -Login tester
        It "Should say skipped" {
            $results.Status | Should be "Skipped"
            $results.Notes | Should be "Already exists on destination"
        }
    }

    Context "ExcludeSystemLogins Parameter" {
        $results = Copy-DbaLogin -Source $script:instance1 -Destination $script:instance2 -ExcludeSystemLogins
        It "Should say skipped" {
            $results.Status.Contains('Skipped') | Should Be $true
            $results.Notes.Contains('System login') | Should Be $true
        }
    }

    Context "Supports pipe" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login tester | Copy-DbaLogin -Destination $script:instance2 -Force
        It "migrates the one tester login" {
            $results.Name | Should be "tester"
            $results.Status | Should Be "Successful"
        }
    }
}