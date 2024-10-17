param($ModuleName = 'dbatools')

Describe "New-DbaLogin" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Get-PasswordHash.ps1"
        . "$PSScriptRoot\..\private\functions\Convert-HexStringToByte.ps1"

        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $sid = '0xDBA700131337C0D30123456789ABCDEF'
        $server1 = Connect-DbaInstance -SqlInstance $env:instance1
        $server2 = Connect-DbaInstance -SqlInstance $env:instance2
        $servers = @($server1, $server2)
        $computerName = $server1.NetName
        $credLogin = 'credologino'
        $winLogin = "$computerName\$credLogin"
        $certificateName = 'dbatoolsPesterlogincertificate'
        $logins = "claudio", "port", "tester", "certifico", $winLogin, "withMustChange", "mustChange"

        # Cleanup
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

        if ($IsWindows) {
            # Create Windows login
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

        # Create credential
        $null = New-DbaCredential -SqlInstance $server1 -Name $credLogin -CredentialIdentity $credLogin -Password $securePassword -Force

        # Create master key if not exists
        if (!($mkey = Get-DbaDbMasterKey -SqlInstance $server1 -Database master)) {
            $null = New-DbaDbMasterKey -SqlInstance $server1 -Database master -Password $securePassword -Confirm:$false
        }

        # Create certificate
        if ($crt = $server1.Databases['master'].Certificates[$certificateName]) {
            $crt.Drop()
        }
        $null = New-DbaDbCertificate $server1 -Name $certificateName -Password $null -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = 'New-DbaLogin'
            $Command = Get-Command -Name $CommandName
        }
        It "Should have SqlInstance parameter" {
            $Command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $Command | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Login parameter" {
            $Command | Should -HaveParameter Login -Type String[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $Command | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have LoginRenameHashtable parameter" {
            $Command | Should -HaveParameter LoginRenameHashtable -Type Hashtable -Not -Mandatory
        }
        It "Should have SecurePassword parameter" {
            $Command | Should -HaveParameter SecurePassword -Type SecureString -Not -Mandatory
        }
        It "Should have HashedPassword parameter" {
            $Command | Should -HaveParameter HashedPassword -Type String -Not -Mandatory
        }
        It "Should have MapToCertificate parameter" {
            $Command | Should -HaveParameter MapToCertificate -Type String -Not -Mandatory
        }
        It "Should have MapToAsymmetricKey parameter" {
            $Command | Should -HaveParameter MapToAsymmetricKey -Type String -Not -Mandatory
        }
        It "Should have MapToCredential parameter" {
            $Command | Should -HaveParameter MapToCredential -Type String -Not -Mandatory
        }
        It "Should have Sid parameter" {
            $Command | Should -HaveParameter Sid -Type Object -Not -Mandatory
        }
        It "Should have DefaultDatabase parameter" {
            $Command | Should -HaveParameter DefaultDatabase -Type String -Not -Mandatory
        }
        It "Should have Language parameter" {
            $Command | Should -HaveParameter Language -Type String -Not -Mandatory
        }
        It "Should have PasswordExpirationEnabled parameter" {
            $Command | Should -HaveParameter PasswordExpirationEnabled -Type Switch -Not -Mandatory
        }
        It "Should have PasswordPolicyEnforced parameter" {
            $Command | Should -HaveParameter PasswordPolicyEnforced -Type Switch -Not -Mandatory
        }
        It "Should have PasswordMustChange parameter" {
            $Command | Should -HaveParameter PasswordMustChange -Type Switch -Not -Mandatory
        }
        It "Should have Disabled parameter" {
            $Command | Should -HaveParameter Disabled -Type Switch -Not -Mandatory
        }
        It "Should have DenyWindowsLogin parameter" {
            $Command | Should -HaveParameter DenyWindowsLogin -Type Switch -Not -Mandatory
        }
        It "Should have NewSid parameter" {
            $Command | Should -HaveParameter NewSid -Type Switch -Not -Mandatory
        }
        It "Should have ExternalProvider parameter" {
            $Command | Should -HaveParameter ExternalProvider -Type Switch -Not -Mandatory
        }
        It "Should have Force parameter" {
            $Command | Should -HaveParameter Force -Type Switch -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $Command | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Create new logins" {
        It "Should be created successfully - Hashed password" {
            $results = New-DbaLogin -SqlInstance $server1 -Login tester -HashedPassword (Get-PasswordHash $securePassword $server1.VersionMajor) -Force
            $results.Name | Should -Be "tester"
            $results.DefaultDatabase | Should -Be 'master'
            $results.IsDisabled | Should -Be $false
            $results.PasswordExpirationEnabled | Should -Be $false
            $results.PasswordPolicyEnforced | Should -Be $false
            $results.MustChangePassword | Should -Be $false
            $results.LoginType | Should -Be 'SqlLogin'
        }

        It "Should be created successfully - password, credential and a custom sid" {
            $results = New-DbaLogin -SqlInstance $server1 -Login claudio -Password $securePassword -Sid $sid -MapToCredential $credLogin
            $results.Name | Should -Be "claudio"
            $results.EnumCredentials() | Should -Be $credLogin
            $results.DefaultDatabase | Should -Be 'master'
            $results.IsDisabled | Should -Be $false
            $results.PasswordExpirationEnabled | Should -Be $false
            $results.PasswordPolicyEnforced | Should -Be $false
            $results.MustChangePassword | Should -Be $false
            $results.Sid | Should -Be (Convert-HexStringToByte $sid)
            $results.LoginType | Should -Be 'SqlLogin'
        }

        It "Should be created successfully - password and all the flags (exclude -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login port -Password $securePassword -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "port"
            $results.Language | Should -Be 'Nederlands'
            $results.EnumCredentials() | Should -Be $null
            $results.DefaultDatabase | Should -Be 'tempdb'
            $results.IsDisabled | Should -Be $true
            $results.PasswordExpirationEnabled | Should -Be $true
            $results.PasswordPolicyEnforced | Should -Be $true
            $results.MustChangePassword | Should -Be $false
            $results.LoginType | Should -Be 'SqlLogin'
            $results.DenyWindowsLogin | Should -Be $true
        }

        It "Should be created successfully - password and all the flags (include -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login withMustChange -Password $securePassword -PasswordPolicy -PasswordExpiration -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "withMustChange"
            $results.Language | Should -Be 'Nederlands'
            $results.EnumCredentials() | Should -Be $null
            $results.DefaultDatabase | Should -Be 'tempdb'
            $results.IsDisabled | Should -Be $true
            $results.PasswordExpirationEnabled | Should -Be $true
            $results.PasswordPolicyEnforced | Should -Be $true
            $results.MustChangePassword | Should -Be $true
            $results.LoginType | Should -Be 'SqlLogin'
            $results.DenyWindowsLogin | Should -Be $true
        }

        It "Should be created successfully - password and just -PasswordMustChange" {
            $results = New-DbaLogin -SqlInstance $server1 -Login MustChange -Password $securePassword -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "MustChange"
            $results.Language | Should -Be 'Nederlands'
            $results.EnumCredentials() | Should -Be $null
            $results.DefaultDatabase | Should -Be 'tempdb'
            $results.IsDisabled | Should -Be $true
            $results.PasswordExpirationEnabled | Should -Be $true
            $results.PasswordPolicyEnforced | Should -Be $true
            $results.MustChangePassword | Should -Be $true
            $results.LoginType | Should -Be 'SqlLogin'
            $results.DenyWindowsLogin | Should -Be $true
        }

        It "Should be created successfully - Windows login" -Skip:($IsWindows -eq $false) {
            $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin
            $results.Name | Should -Be "$winLogin"
            $results.DefaultDatabase | Should -Be 'master'
            $results.IsDisabled | Should -Be $false
            $results.LoginType | Should -Be 'WindowsUser'
        }

        It "Should be created successfully - certificate" {
            $results = New-DbaLogin -SqlInstance $server1 -Login certifico -MapToCertificate $certificateName
            $results.Name | Should -Be "certifico"
            $results.DefaultDatabase | Should -Be 'master'
            $results.IsDisabled | Should -Be $false
            $results.LoginType | Should -Be 'Certificate'
        }

        It "Should be copied successfully" {
            $results = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server2 -Disabled:$false -Force
            $results.Name | Should -Be "tester"

            $results = Get-DbaLogin -SqlInstance $server1 -Login claudio, port | New-DbaLogin -SqlInstance $server2 -Force -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -NewSid -LoginRenameHashtable @{claudio = 'port'; port = 'claudio' } -MapToCredential $null
            $results.Name | Should -Be @("port", "claudio")

            $results = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server1 -LoginRenameHashtable @{tester = 'port' } -Force -NewSid
            $results.Name | Should -Be "port"
        }

        It "Should retain its same properties" {
            $login1 = Get-DbaLogin -SqlInstance $env:instance1 -login tester
            $login2 = Get-DbaLogin -SqlInstance $env:instance2 -login tester

            $login2 | Should -Not -BeNullOrEmpty

            # Compare values
            $login1.Name | Should -Be $login2.Name
            $login1.Language | Should -Be $login2.Language
            $login1.EnumCredentials() | Should -Be $login2.EnumCredentials()
            $login1.DefaultDatabase | Should -Be $login2.DefaultDatabase
            $login1.IsDisabled | Should -Be $login2.IsDisabled
            $login1.PasswordExpirationEnabled | Should -Be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should -Be $login2.PasswordPolicyEnforced
            $login1.MustChangePassword | Should -Be $login2.MustChangePassword
            $login1.Sid | Should -Be $login2.Sid
        }

        It "Should not have same properties because of the overrides" {
            $login1 = Get-DbaLogin -SqlInstance $env:instance1 -login claudio
            $login2 = Get-DbaLogin -SqlInstance $env:instance2 -login withMustChange

            $login2 | Should -Not -BeNullOrEmpty

            # Compare values
            $login1.Language | Should -Not -Be $login2.Language
            $login1.EnumCredentials() | Should -Not -Be $login2.EnumCredentials()
            $login1.DefaultDatabase | Should -Not -Be $login2.DefaultDatabase
            $login1.IsDisabled | Should -Not -Be $login2.IsDisabled
            $login1.PasswordExpirationEnabled | Should -Not -Be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should -Not -Be $login2.PasswordPolicyEnforced
            $login1.MustChangePassword | Should -Not -Be $login2.MustChangePassword
            $login1.Sid | Should -Not -Be $login2.Sid
        }

        It "Should create a disabled account with deny Windows login" -Skip:($IsWindows -eq $false) {
            $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin -Disabled -DenyWindowsLogin
            $results.Name | Should -Be "$winLogin"
            $results.DefaultDatabase | Should -Be 'master'
            $results.IsDisabled | Should -Be $true
            $results.DenyWindowsLogin | Should -Be $true
            $results.LoginType | Should -Be 'WindowsUser'
        }
    }

    Context "Connect with a new login" -Skip:((Connect-DbaInstance -SqlInstance $env:instance1).LoginMode -ne "Mixed") {
        It "Should login with newly created Sql Login, get instance name and kill the process" {
            $cred = New-Object System.Management.Automation.PSCredential ("tester", $securePassword)
            $s = Connect-DbaInstance -SqlInstance $env:instance1 -SqlCredential $cred
            $s.Name | Should -Be $env:instance1
            Stop-DbaProcess -SqlInstance $env:instance1 -Login tester
        }
    }

    Context "No overwrite" {
        It "Should not attempt overwrite" {
            $null = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server2 -WarningAction SilentlyContinue -WarningVariable warning
            $warning | Should -Match "Login tester already exists"
        }
    }

    AfterAll {
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

        if ($IsWindows) {
            $computer.Delete('User', $credLogin)
        }
        $server1.Credentials[$credLogin].Drop()
        $server1.Databases['master'].Certificates[$certificateName].Drop()
        if (!$mkey) {
            $null = Remove-DbaDbMasterKey -SqlInstance $env:instance1 -Database master -Confirm:$false
        }
    }
}
