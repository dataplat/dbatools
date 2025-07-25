$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Get-PasswordHash.ps1"
. "$PSScriptRoot\..\private\functions\Convert-HexStringToByte.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'InputObject', 'LoginRenameHashtable', 'SecurePassword', 'HashedPassword', 'MapToCertificate', 'MapToAsymmetricKey', 'MapToCredential', 'Sid', 'DefaultDatabase', 'Language', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced', 'PasswordMustChange', 'Disabled', 'DenyWindowsLogin', 'NewSid', 'ExternalProvider', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {

    $credLogin = 'credologino'
    $certificateName = 'dbatoolsPesterlogincertificate'
    $password = 'MyV3ry$ecur3P@ssw0rd'
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $sid = '0xDBA700131337C0D30123456789ABCDEF'
    $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
    $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
    $servers = @($server1, $server2)
    $computerName = $server1.NetName
    $winLogin = "$computerName\$credLogin"
    $logins = "claudio", "port", "tester", "certifico", $winLogin, "withMustChange", "mustChange"

    #cleanup
    try {
        foreach ($instance in $servers) {
            foreach ($login in $logins) {
                if ($l = Get-DbaLogin -SqlInstance $instance -Login $login) {
                    $results = $instance.Query("IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '$login') EXEC sp_who '$login'")
                    foreach ($spid in $results.spid) {
                        $null = $instance.Query("kill $spid")
                    }
                    if ($c = $l.EnumCredentials()) {
                        $l.DropCredential($c)
                    }
                    $l.Drop()
                }
            }
        }
    } catch { <#nbd#> }

    if ($IsWindows -ne $false) {
        #create Windows login
        $computer = [ADSI]"WinNT://$computerName"
        try {
            $user = [ADSI]"WinNT://$computerName/$credLogin,user"
            if ($user.Name -eq $credLogin) {
                $computer.Delete('User', $credLogin)
            }
        } catch { <#User does not exist#> }

        $user = $computer.Create("user", $credLogin)
        $user.SetPassword($password)
        $user.SetInfo()
    }

    #create credential
    $null = New-DbaCredential -SqlInstance $server1 -Name $credLogin -CredentialIdentity $credLogin -Password $securePassword -Force

    #create master key if not exists
    if (!($mkey = Get-DbaDbMasterKey -SqlInstance $server1 -Database master)) {
        $null = New-DbaDbMasterKey -SqlInstance $server1 -Database master -Password $securePassword -Confirm:$false
    }

    try {
        #create certificate
        if ($crt = $server1.Databases['master'].Certificates[$certificateName]) {
            $crt.Drop()
        }
    } catch { <#nbd#> }
    $null = New-DbaDbCertificate $server1 -Name $certificateName -Password $null -Confirm:$false

    Context "Create new logins" {
        It "Should be created successfully - Hashed password" {
            $results = New-DbaLogin -SqlInstance $server1 -Login tester -HashedPassword (Get-PasswordHash $securePassword $server1.VersionMajor) -Force
            $results.Name | Should Be "tester"
            $results.DefaultDatabase | Should be 'master'
            $results.IsDisabled | Should be $false
            $results.PasswordExpirationEnabled | Should be $false
            $results.PasswordPolicyEnforced | Should be $false
            $results.MustChangePassword | Should be $false
            $results.LoginType | Should be 'SqlLogin'
        }
        It "Should be created successfully - password, credential and a custom sid " {
            $results = New-DbaLogin -SqlInstance $server1 -Login claudio -Password $securePassword -Sid $sid -MapToCredential $credLogin
            $results.Name | Should Be "claudio"
            $results.EnumCredentials() | Should be $credLogin
            $results.DefaultDatabase | Should be 'master'
            $results.IsDisabled | Should be $false
            $results.PasswordExpirationEnabled | Should be $false
            $results.PasswordPolicyEnforced | Should be $false
            $results.MustChangePassword | Should be $false
            $results.Sid | Should be (Convert-HexStringToByte $sid)
            $results.LoginType | Should be 'SqlLogin'
        }
        It "Should be created successfully - password and all the flags (exclude -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login port -Password $securePassword -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should Be "port"
            $results.Language | Should Be 'Nederlands'
            $results.EnumCredentials() | Should be $null
            $results.DefaultDatabase | Should be 'tempdb'
            $results.IsDisabled | Should be $true
            $results.PasswordExpirationEnabled | Should be $true
            $results.PasswordPolicyEnforced | Should be $true
            $results.MustChangePassword | Should be $false
            $results.LoginType | Should be 'SqlLogin'
            $results.DenyWindowsLogin | Should Be $true
        }
        It "Should be created successfully - password and all the flags (include -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login withMustChange -Password $securePassword -PasswordPolicy -PasswordExpiration -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should Be "withMustChange"
            $results.Language | Should Be 'Nederlands'
            $results.EnumCredentials() | Should be $null
            $results.DefaultDatabase | Should be 'tempdb'
            $results.IsDisabled | Should be $true
            $results.PasswordExpirationEnabled | Should be $true
            $results.PasswordPolicyEnforced | Should be $true
            $results.MustChangePassword | Should be $true
            $results.LoginType | Should be 'SqlLogin'
            $results.DenyWindowsLogin | Should Be $true
        }
        It "Should be created successfully - password and just -PasswordMustChange" {
            $results = New-DbaLogin -SqlInstance $server1 -Login MustChange -Password $securePassword -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should Be "MustChange"
            $results.Language | Should Be 'Nederlands'
            $results.EnumCredentials() | Should be $null
            $results.DefaultDatabase | Should be 'tempdb'
            $results.IsDisabled | Should be $true
            $results.PasswordExpirationEnabled | Should be $true
            $results.PasswordPolicyEnforced | Should be $true
            $results.MustChangePassword | Should be $true
            $results.LoginType | Should be 'SqlLogin'
            $results.DenyWindowsLogin | Should Be $true
        }
        if ($IsWindows -ne $false) {
            It "Should be created successfully - Windows login" {
                $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin
                $results.Name | Should Be "$winLogin"
                $results.DefaultDatabase | Should be 'master'
                $results.IsDisabled | Should be $false
                $results.LoginType | Should be 'WindowsUser'
            }
        }
        It "Should be created successfully - certificate" {
            $results = New-DbaLogin -SqlInstance $server1 -Login certifico -MapToCertificate $certificateName
            $results.Name | Should Be "certifico"
            $results.DefaultDatabase | Should be 'master'
            $results.IsDisabled | Should be $false
            $results.LoginType | Should be 'Certificate'
        }

        It "Should be copied successfully" {
            $results = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server2 -Disabled:$false -Force
            $results.Name | Should Be "tester"

            $results = Get-DbaLogin -SqlInstance $server1 -Login claudio, port | New-DbaLogin -SqlInstance $server2 -Force -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -NewSid -LoginRenameHashtable @{claudio = 'port'; port = 'claudio' } -MapToCredential $null
            $results.Name | Should Be @("port", "claudio")

            $results = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server1 -LoginRenameHashtable @{tester = 'port' } -Force -NewSid
            $results.Name | Should Be "port"
        }

        It "Should retain its same properties" {

            $login1 = Get-DbaLogin -SqlInstance $TestConfig.instance1 -login tester
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.instance2 -login tester

            $login2 | Should Not BeNullOrEmpty

            # Compare values
            $login1.Name | Should Be $login2.Name
            $login1.Language | Should Be $login2.Language
            $login1.EnumCredentials() | Should be $login2.EnumCredentials()
            $login1.DefaultDatabase | Should be $login2.DefaultDatabase
            $login1.IsDisabled | Should be $login2.IsDisabled
            $login1.PasswordExpirationEnabled | Should be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should be $login2.PasswordPolicyEnforced
            $login1.MustChangePassword | Should be $login2.MustChangePassword
            $login1.Sid | Should be $login2.Sid
        }

        It "Should not have same properties because of the overrides" {

            $login1 = Get-DbaLogin -SqlInstance $TestConfig.instance1 -login claudio
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.instance2 -login claudio

            $login2 | Should Not BeNullOrEmpty

            # Compare values
            $login1.Language | Should Not Be $login2.Language
            $login1.EnumCredentials() | Should Not Be $login2.EnumCredentials()
            $login1.DefaultDatabase | Should Not be $login2.DefaultDatabase
            $login1.IsDisabled | Should Not be $login2.IsDisabled
            $login1.PasswordExpirationEnabled | Should Not be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should Not be $login2.PasswordPolicyEnforced
            $login1.Sid | Should Not be $login2.Sid
        }
        if ($IsWindows -ne $false) {
            It "Should create a disabled account with deny Windows login" {
                $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin -Disabled -DenyWindowsLogin -Force
                $results.Name | Should Be "$winLogin"
                $results.DefaultDatabase | Should be 'master'
                $results.IsDisabled | Should be $true
                $results.DenyWindowsLogin | Should be $true
                $results.LoginType | Should be 'WindowsUser'
            }
        }
    }

    if ((Connect-DbaInstance -SqlInstance $TestConfig.instance1).LoginMode -eq "Mixed") {
        Context "Connect with a new login" {
            It "Should login with newly created Sql Login, get instance name and kill the process" {
                $cred = New-Object System.Management.Automation.PSCredential ("tester", $securePassword)
                $s = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -SqlCredential $cred
                $s.Name | Should Be $TestConfig.instance1
                Stop-DbaProcess -SqlInstance $TestConfig.instance1 -Login tester
            }
        }
    }

    Context "No overwrite" {
        $null = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server2 -WarningAction SilentlyContinue -WarningVariable warning 3>&1
        It "Should not attempt overwrite" {
            $warning | Should Match "Login tester already exists"
        }
    }

    try {
        foreach ($instance in $servers) {
            foreach ($login in $logins) {
                if ($l = Get-DbaLogin -SqlInstance $instance -Login $login) {
                    $results = $instance.Query("IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '$login') EXEC sp_who '$login'")
                    foreach ($spid in $results.spid) {
                        $null = $instance.Query("kill $spid")
                    }
                    if ($c = $l.EnumCredentials()) {
                        $l.DropCredential($c)
                    }
                    $l.Drop()
                }
            }
        }

        $computer.Delete('User', $credLogin)
        $server1.Credentials[$credLogin].Drop()
        $server1.Databases['master'].Certificates[$certificateName].Drop()
        if (!$mkey) {
            $null = Remove-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master -Confirm:$false
        }
    } catch { <#nbd#> }
}
