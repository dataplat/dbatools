$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"
. "$PSScriptRoot\..\internal\functions\Get-PasswordHash.ps1"
. "$PSScriptRoot\..\internal\functions\Convert-HexStringToByte.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    $credLogin = 'credologino'
    $certificateName = 'DBAToolsPesterlogincertificate'
    $password = 'MyV3ry$ecur3P@ssw0rd'
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $sid = '0xDBA700131337C0D30123456789ABCDEF'
    $server1 = Connect-SqlInstance -SqlInstance $script:instance1
    $server2 = Connect-SqlInstance -SqlInstance $script:instance2
    $servers = @($server1, $server2)
    $computerName = $server1.NetName
    $winLogin = "$computerName\$credLogin"
    $logins = "claudio", "port", "tester", "certifico", $winLogin
    
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
    }
    catch {<#nbd#> }
    
    #create Windows login
    $computer = [ADSI]"WinNT://$computerName"
    try {
        $user = [ADSI]"WinNT://$computerName/$credLogin,user"
        if ($user.Name -eq $credLogin) {
            $computer.Delete('User', $credLogin)
        }
    }
    catch {<#User does not exist#>}

    $user = $computer.Create("user", $credLogin)
    $user.SetPassword($password)
    $user.SetInfo()

    #create credential
    $null = New-DbaCredential -SqlInstance $server1 -Name $credLogin -CredentialIdentity $credLogin -Password $securePassword -Force

    #create master key if not exists
    if (!($mkey = Get-DbaDatabaseMasterKey -SqlInstance $server1 -Database master)) {
        $null = New-DbaDatabaseMasterKey -SqlInstance $server1 -Database master -Password $securePassword -Confirm:$false
    }
    
    try {
        #create certificate
        if ($crt = $server1.Databases['master'].Certificates[$certificateName]) {
            $crt.Drop()
        }
    }
    catch {<#nbd#> }
    $null = New-DbaDbCertificate $server1 -Name $certificateName -Password $null

    Context "Create new logins" {
        It "Should be created successfully - Hashed password" {
            $results = New-DbaLogin -SqlInstance $server1 -Login tester -HashedPassword (Get-PasswordHash $securePassword $server1.VersionMajor) -Force
            $results.Name | Should Be "tester"
            $results.DefaultDatabase | Should be 'master'
            $results.IsDisabled | Should be $false
            $results.PasswordExpirationEnabled | Should be $false
            $results.PasswordPolicyEnforced | Should be $false
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
            $results.Sid | Should be (Convert-HexStringToByte $sid)
            $results.LoginType | Should be 'SqlLogin'
        }
        It "Should be created successfully - password and all the flags" {
            $results = New-DbaLogin -SqlInstance $server1 -Login port -Password $securePassword -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands
            $results.Name | Should Be "port"
            $results.Language | Should Be 'Nederlands'
            $results.EnumCredentials() | Should be $null
            $results.DefaultDatabase | Should be 'tempdb'
            $results.IsDisabled | Should be $true
            $results.PasswordExpirationEnabled | Should be $true
            $results.PasswordPolicyEnforced | Should be $true
            $results.LoginType | Should be 'SqlLogin'
        }
        It "Should be created successfully - Windows login" {
            $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin
            $results.Name | Should Be "$winLogin"
            $results.DefaultDatabase | Should be 'master'
            $results.IsDisabled | Should be $false
            $results.LoginType | Should be 'WindowsUser'
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

            $results = Get-DbaLogin -SqlInstance $server1 -Login claudio, port | New-DbaLogin -SqlInstance $server2 -Force -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -NewSid -LoginRenameHashtable @{claudio = 'port'; port = 'claudio'} -MapToCredential $null
            $results.Name | Should Be @("port", "claudio")

            $results = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server1 -LoginRenameHashtable @{tester = 'port'} -Force -NewSid
            $results.Name | Should Be "port"
        }

        It "Should retain its same properties" {

            $login1 = Get-Dbalogin -SqlInstance $script:instance1 -login tester
            $login2 = Get-Dbalogin -SqlInstance $script:instance2 -login tester

            $login2 | Should Not BeNullOrEmpty

            # Compare values
            $login1.Name | Should Be $login2.Name
            $login1.Language | Should Be $login2.Language
            $login1.EnumCredentials() | Should be $login2.EnumCredentials()
            $login1.DefaultDatabase | Should be $login2.DefaultDatabase
            $login1.IsDisabled | Should be $login2.IsDisabled
            $login1.PasswordExpirationEnabled | Should be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should be $login2.PasswordPolicyEnforced
            $login1.Sid | Should be $login2.Sid
        }

        It "Should not have same properties because of the overrides" {

            $login1 = Get-Dbalogin -SqlInstance $script:instance1 -login claudio
            $login2 = Get-Dbalogin -SqlInstance $script:instance2 -login port

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
    }
    
    if ((Connect-DbaInstance -SqlInstance $script:instance1).LoginMode -eq "Mixed") {
        Context "Connect with a new login" {
            It "Should login with newly created Sql Login, get instance name and kill the process" {
                $cred = New-Object System.Management.Automation.PSCredential ("tester", $securePassword)
                $s = Connect-DbaInstance -SqlInstance $script:instance1 -Credential $cred
                $s.Name | Should Be $script:instance1
                Stop-DbaProcess -SqlInstance $script:instance1 -Login tester
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
            $null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master -Confirm:$false
        }
    }
    catch {<#nbd#> }
}