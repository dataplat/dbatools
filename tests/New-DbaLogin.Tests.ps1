$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions', 'Get-PasswordHash.ps1'))
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions', 'Convert-HexStringToByte.ps1'))

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'InputObject', 'LoginRenameHashtable', 'SecurePassword', 'HashedPassword', 'MapToCertificate', 'MapToAsymmetricKey', 'MapToCredential', 'Sid', 'DefaultDatabase', 'Language', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced', 'PasswordMustChange', 'Disabled', 'DenyWindowsLogin', 'NewSid', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {

    $credLogin = 'credologino'
    $certificateName = 'DBAToolsPesterlogincertificate'
    $password = 'MyV3ry$ecur3P@ssw0rd'
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $sid = '0xDBA700131337C0D30123456789ABCDEF'
    $server1 = Connect-DbaInstance -SqlInstance $script:instance1
    $server2 = Connect-DbaInstance -SqlInstance $script:instance2
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
            $results.Name | Should -Be "tester"
            $results.DefaultDatabase | Should -Be 'master'
            $results.IsDisabled | Should -Be $false
            $results.PasswordExpirationEnabled | Should -Be $false
            $results.PasswordPolicyEnforced | Should -Be $false
            $results.MustChangePassword | Should -Be $false
            $results.LoginType | Should -Be 'SqlLogin'
        }
        It "Should be created successfully - password, credential and a custom sid " {
            $results = New-DbaLogin -SqlInstance $server1 -Login claudio -Password $securePassword -Sid $sid -MapToCredential $credLogin
            $results.Name | Should -Be "claudio"
            $results.EnumCredentials() | Should -Be $credLogin
            $results.DefaultDatabase | Should -Be 'master'
            $results.IsDisabled | Should -Be $false
            $results.PasswordExpirationEnabled | Should -Be $false
            $results.PasswordPolicyEnforced | Should -Be $false
            $results.MustChangePassword | Should -Be $false
            $results.Sid | Should be (Convert-HexStringToByte $sid)
            $results.LoginType | Should -Be 'SqlLogin'
        }
        It "Should be created successfully - password and all the flags (exclude -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login port -Password $securePassword -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "port"
            $results.Language | Should -Be 'Nederlands'
            $results.EnumCredentials() | Should -BeNullOrEmpty
            $results.DefaultDatabase | Should -Be 'tempdb'
            $results.IsDisabled | Should -BeTrue
            $results.PasswordExpirationEnabled | Should -BeTrue
            $results.PasswordPolicyEnforced | Should -BeTrue
            $results.MustChangePassword | Should -Be $false
            $results.LoginType | Should -Be 'SqlLogin'
            $results.DenyWindowsLogin | Should -BeTrue
        }
        It "Should be created successfully - password and all the flags (include -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login withMustChange -Password $securePassword -PasswordPolicy -PasswordExpiration -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "withMustChange"
            $results.Language | Should -Be 'Nederlands'
            $results.EnumCredentials() | Should -BeNullOrEmpty
            $results.DefaultDatabase | Should -Be 'tempdb'
            $results.IsDisabled | Should -BeTrue
            $results.PasswordExpirationEnabled | Should -BeTrue
            $results.PasswordPolicyEnforced | Should -BeTrue
            $results.MustChangePassword | Should -BeTrue
            $results.LoginType | Should -Be 'SqlLogin'
            $results.DenyWindowsLogin | Should -BeTrue
        }
        It "Should be created successfully - password and just -PasswordMustChange" {
            $results = New-DbaLogin -SqlInstance $server1 -Login MustChange -Password $securePassword -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "MustChange"
            $results.Language | Should -Be 'Nederlands'
            $results.EnumCredentials() | Should -BeNullOrEmpty
            $results.DefaultDatabase | Should -Be 'tempdb'
            $results.IsDisabled | Should -BeTrue
            $results.PasswordExpirationEnabled | Should -BeTrue
            $results.PasswordPolicyEnforced | Should -BeTrue
            $results.MustChangePassword | Should -BeTrue
            $results.LoginType | Should -Be 'SqlLogin'
            $results.DenyWindowsLogin | Should -BeTrue
        }
        if ($IsWindows -ne $false) {
            It "Should be created successfully - Windows login" {
                $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin
                $results.Name | Should -Be "$winLogin"
                $results.DefaultDatabase | Should -Be 'master'
                $results.IsDisabled | Should -Be $false
                $results.LoginType | Should -Be 'WindowsUser'
            }
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

            $login1 = Get-DbaLogin -SqlInstance $script:instance1 -Login tester
            $login2 = Get-DbaLogin -SqlInstance $script:instance2 -Login tester

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

            $login1 = Get-DbaLogin -SqlInstance $script:instance1 -Login claudio
            $login2 = Get-DbaLogin -SqlInstance $script:instance2 -Login withMustChange

            $login2 | Should -Not -BeNullOrEmpty

            # Compare values
            $login1.Language | Should -Not -Be $login2.Language
            $login1.EnumCredentials() | Should -Not -Be $login2.EnumCredentials()
            $login1.DefaultDatabase | Should -Not -Be $login2.DefaultDatabase
            $login1.IsDisabled | Should -Not be $login2.IsDisabled
            $login1.PasswordExpirationEnabled | Should -Not -Be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should -Not -Be $login2.PasswordPolicyEnforced
            $login1.MustChangePassword | Should -Not -Be $login2.MustChangePassword
            $login1.Sid | Should -Not -Be $login2.Sid
        }
        if ($IsWindows -ne $false) {
            It "Should create a disabled account with deny Windows login" {
                $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin -Disabled -DenyWindowsLogin
                $results.Name | Should -Be "$winLogin"
                $results.DefaultDatabase | Should -Be 'master'
                $results.IsDisabled | Should -BeTrue
                $results.DenyWindowsLogin | Should -BeTrue
                $results.LoginType | Should -Be 'WindowsUser'
            }
        }
    }

    if ((Connect-DbaInstance -SqlInstance $script:instance1).LoginMode -eq "Mixed") {
        Context "Connect with a new login" {
            It "Should login with newly created Sql Login, get instance name and kill the process" {
                $cred = New-Object System.Management.Automation.PSCredential ("tester", $securePassword)
                $s = Connect-DbaInstance -SqlInstance $script:instance1 -SqlCredential $cred
                $s.Name | Should Be $script:instance1
                Stop-DbaProcess -SqlInstance $script:instance1 -Login tester
            }
        }
    }

    Context "No overwrite" {
        $null = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server2 -WarningAction SilentlyContinue -WarningVariable warning 3>&1
        It "Should not attempt overwrite" {
            $warning | Should -Match "Login tester already exists"
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
        if (-not $mkey) {
            $null = Remove-DbaDbMasterKey -SqlInstance $script:instance1 -Database master -Confirm:$false
        }
    } catch { <#nbd#> }
}