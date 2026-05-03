#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "InputObject",
                "LoginRenameHashtable",
                "SecurePassword",
                "HashedPassword",
                "MapToCertificate",
                "MapToAsymmetricKey",
                "MapToCredential",
                "Sid",
                "DefaultDatabase",
                "Language",
                "PasswordExpirationEnabled",
                "PasswordPolicyEnforced",
                "PasswordMustChange",
                "Disabled",
                "DenyWindowsLogin",
                "NewSid",
                "ExternalProvider",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "External provider fallback" {
            BeforeEach {
                $script:queryStatements = @()

                $script:createdLogin = [PSCustomObject]@{
                    Name               = $null
                    DenyWindowsLogin   = $null
                    MustChangePassword = $false
                }

                $script:pendingLogin = [PSCustomObject]@{
                    Name                      = "pending"
                    LoginType                 = $null
                    DefaultDatabase           = $null
                    Language                  = $null
                    PasswordExpirationEnabled = $null
                    PasswordPolicyEnforced    = $null
                    DenyWindowsLogin          = $null
                    MustChangePassword        = $false
                    AsymmetricKey             = $null
                    Certificate               = $null
                    Sid                       = $null
                }
                Add-Member -InputObject $script:pendingLogin -Name Set_Sid -MemberType ScriptMethod -Value {
                    param($sid)
                    $this.Sid = $sid
                } -Force
                Add-Member -InputObject $script:pendingLogin -Name Create -MemberType ScriptMethod -Value {
                    throw "SMO create failed for test"
                } -Force
                Add-Member -InputObject $script:pendingLogin -Name Refresh -MemberType ScriptMethod -Value { } -Force
                Add-Member -InputObject $script:pendingLogin -Name AddCredential -MemberType ScriptMethod -Value {
                    param($credential)
                    $this.Credential = $credential
                } -Force
                Add-Member -InputObject $script:pendingLogin -Name Drop -MemberType ScriptMethod -Value { } -Force
                Add-Member -InputObject $script:pendingLogin -Name Disable -MemberType ScriptMethod -Value { } -Force
                Add-Member -InputObject $script:pendingLogin -Name Alter -MemberType ScriptMethod -Value { } -Force
                Add-Member -InputObject $script:pendingLogin -Name ChangePassword -MemberType ScriptMethod -Value {
                    param($securePassword, $mustChange)
                    $this.MustChangePassword = $mustChange
                } -Force

                $script:mockLogins = @{ }
                Add-Member -InputObject $script:mockLogins -Name Refresh -MemberType ScriptMethod -Value { } -Force

                $script:mockServer = [DbaInstanceParameter]"sql2022"
                Add-Member -InputObject $script:mockServer -Name IsAzure -MemberType NoteProperty -Value $false -Force
                Add-Member -InputObject $script:mockServer -Name LoginMode -MemberType NoteProperty -Value ([Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -Force
                Add-Member -InputObject $script:mockServer -Name DatabaseEngineType -MemberType NoteProperty -Value "Standalone" -Force
                Add-Member -InputObject $script:mockServer -Name DatabaseEngineEdition -MemberType NoteProperty -Value "Enterprise" -Force
                Add-Member -InputObject $script:mockServer -Name VersionMajor -MemberType NoteProperty -Value 16 -Force
                Add-Member -InputObject $script:mockServer -Name Logins -MemberType NoteProperty -Value $script:mockLogins -Force
                Add-Member -InputObject $script:mockServer -Name Query -MemberType ScriptMethod -Value {
                    param($sql)
                    $script:queryStatements += $sql
                    if ($sql -match "^CREATE LOGIN \[(?<LoginName>.+)\] FROM EXTERNAL PROVIDER$") {
                        $script:createdLogin.Name = $Matches.LoginName
                        $this.Logins[$Matches.LoginName] = $script:createdLogin
                    }
                } -Force

                Mock Test-FunctionInterrupt { $false } -ModuleName dbatools
                Mock Connect-DbaInstance { $script:mockServer } -ModuleName dbatools
                Mock Add-TeppCacheItem { } -ModuleName dbatools
                Mock Get-DbaLogin {
                    [PSCustomObject]@{
                        Name      = $Login
                        LoginType = "ExternalUser"
                    }
                } -ModuleName dbatools
                Mock Stop-Function {
                    throw $Message
                } -ModuleName dbatools
                Mock New-Object {
                    $script:pendingLogin
                } -ModuleName dbatools
            }

            It "Should use ALTER LOGIN for external provider defaults after T-SQL fallback" {
                $null = New-DbaLogin -SqlInstance "sql2022" -Login "entra-user" -ExternalProvider -DefaultDatabase "tempdb" -Language "Deutsch"

                $script:queryStatements.Count | Should -Be 2
                $script:queryStatements[0] | Should -Be "CREATE LOGIN [entra-user] FROM EXTERNAL PROVIDER"
                $script:queryStatements[0] | Should -Not -Match "WITH"
                $script:queryStatements[1] | Should -Be "ALTER LOGIN [entra-user] WITH DEFAULT_DATABASE = [tempdb], DEFAULT_LANGUAGE = [Deutsch]"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $credLogin = "credologino"
        $certificateName = "dbatoolsPesterlogincertificate"
        $securePassword = ConvertTo-SecureString 'MyV3ry$ecur3P@ssw0rd' -AsPlainText -Force
        $sid = "0xDBA700131337C0D30123456789ABCDEF"
        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $servers = @($server1, $server2)
        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceMulti1 -Property ComputerName
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
        } catch { <#nbd #> }

        if ($IsWindows -ne $false) {
            $splatInvoke = @{
                ComputerName = $computerName
                ScriptBlock  = { New-LocalUser -Name $args[0] -Password $args[1] -Disabled:$false }
                ArgumentList = $credLogin, $securePassword
            }
            Invoke-Command2 @splatInvoke
        }

        #create credential
        $null = New-DbaCredential -SqlInstance $server1 -Name $credLogin -CredentialIdentity $credLogin -Password $securePassword -Force

        try {
            #create certificate
            if ($crt = $server1.Databases["master"].Certificates[$certificateName]) {
                $crt.Drop()
            }
        } catch { <#nbd #> }
        $null = New-DbaDbCertificate $server1 -Name $certificateName -Password $null

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

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

            $server1.Credentials[$credLogin].Drop()
            $server1.Databases["master"].Certificates[$certificateName].Drop()
        } catch { <#nbd #> }

        $splatInvoke = @{
            ComputerName = $computerName
            ScriptBlock  = { Remove-LocalUser -Name $args[0] -ErrorAction SilentlyContinue }
            ArgumentList = $credLogin
        }
        Invoke-Command2 @splatInvoke

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Create new logins" {
        It "Should be created successfully - Hashed password" {
            $results = New-DbaLogin -SqlInstance $server1 -Login tester -HashedPassword (Get-PasswordHash $securePassword $server1.VersionMajor) -Force
            $results.Name | Should -Be "tester"
            $results.DefaultDatabase | Should -Be "master"
            $results.IsDisabled | Should -Be $false
            $results.PasswordExpirationEnabled | Should -Be $false
            $results.PasswordPolicyEnforced | Should -Be $false
            $results.MustChangePassword | Should -Be $false
            $results.LoginType | Should -Be "SqlLogin"
        }
        It "Should be created successfully - password, credential and a custom sid " {
            $results = New-DbaLogin -SqlInstance $server1 -Login claudio -Password $securePassword -Sid $sid -MapToCredential $credLogin
            $results.Name | Should -Be "claudio"
            $results.EnumCredentials() | Should -Be $credLogin
            $results.DefaultDatabase | Should -Be "master"
            $results.IsDisabled | Should -Be $false
            $results.PasswordExpirationEnabled | Should -Be $false
            $results.PasswordPolicyEnforced | Should -Be $false
            $results.MustChangePassword | Should -Be $false
            $results.Sid | Should -Be (Convert-HexStringToByte $sid)
            $results.LoginType | Should -Be "SqlLogin"
        }
        It "Should be created successfully - password and all the flags (exclude -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login port -Password $securePassword -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "port"
            $results.Language | Should -Be "Nederlands"
            $results.EnumCredentials() | Should -Be $null
            $results.DefaultDatabase | Should -Be "tempdb"
            $results.IsDisabled | Should -Be $true
            $results.PasswordExpirationEnabled | Should -Be $true
            $results.PasswordPolicyEnforced | Should -Be $true
            $results.MustChangePassword | Should -Be $false
            $results.LoginType | Should -Be "SqlLogin"
            $results.DenyWindowsLogin | Should -Be $true
        }
        It "Should be created successfully - password and all the flags (include -PasswordMustChange)" {
            $results = New-DbaLogin -SqlInstance $server1 -Login withMustChange -Password $securePassword -PasswordPolicy -PasswordExpiration -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "withMustChange"
            $results.Language | Should -Be "Nederlands"
            $results.EnumCredentials() | Should -Be $null
            $results.DefaultDatabase | Should -Be "tempdb"
            $results.IsDisabled | Should -Be $true
            $results.PasswordExpirationEnabled | Should -Be $true
            $results.PasswordPolicyEnforced | Should -Be $true
            $results.MustChangePassword | Should -Be $true
            $results.LoginType | Should -Be "SqlLogin"
            $results.DenyWindowsLogin | Should -Be $true
        }
        It "Should be created successfully - password and just -PasswordMustChange" {
            $results = New-DbaLogin -SqlInstance $server1 -Login MustChange -Password $securePassword -PasswordMustChange -DefaultDatabase tempdb -Disabled -Language Nederlands -DenyWindowsLogin
            $results.Name | Should -Be "MustChange"
            $results.Language | Should -Be "Nederlands"
            $results.EnumCredentials() | Should -Be $null
            $results.DefaultDatabase | Should -Be "tempdb"
            $results.IsDisabled | Should -Be $true
            $results.PasswordExpirationEnabled | Should -Be $true
            $results.PasswordPolicyEnforced | Should -Be $true
            $results.MustChangePassword | Should -Be $true
            $results.LoginType | Should -Be "SqlLogin"
            $results.DenyWindowsLogin | Should -Be $true
        }
        if ($IsWindows -ne $false) {
            It "Should be created successfully - Windows login" {
                $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin
                $results.Name | Should -Be "$winLogin"
                $results.DefaultDatabase | Should -Be "master"
                $results.IsDisabled | Should -Be $false
                $results.LoginType | Should -Be "WindowsUser"
            }
        }
        It "Should be created successfully - certificate" {
            $results = New-DbaLogin -SqlInstance $server1 -Login certifico -MapToCertificate $certificateName
            $results.Name | Should -Be "certifico"
            $results.DefaultDatabase | Should -Be "master"
            $results.IsDisabled | Should -Be $false
            $results.LoginType | Should -Be "Certificate"
        }

        It "Should be copied successfully" {
            $results = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server2 -Disabled:$false -Force
            $results.Name | Should -Be "tester"

            $splatCopyLogins = @{
                SqlInstance          = $server2
                Force                = $true
                PasswordPolicy       = $true
                PasswordExpiration   = $true
                DefaultDatabase      = "tempdb"
                Disabled             = $true
                Language             = "Nederlands"
                NewSid               = $true
                LoginRenameHashtable = @{claudio = "port"; port = "claudio" }
                MapToCredential      = $null
            }
            $results = Get-DbaLogin -SqlInstance $server1 -Login claudio, port | New-DbaLogin @splatCopyLogins
            $results.Name | Should -Be @("port", "claudio")

            $splatRename = @{
                SqlInstance          = $server1
                LoginRenameHashtable = @{tester = "port" }
                Force                = $true
                NewSid               = $true
            }
            $results = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin @splatRename
            $results.Name | Should -Be "port"
        }

        It "Should retain its same properties" {
            $login1 = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login tester
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login tester

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
            $login1 = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login claudio
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login claudio

            $login2 | Should -Not -BeNullOrEmpty

            # Compare values
            $login1.Language | Should -Not -Be $login2.Language
            $login1.EnumCredentials() | Should -Not -Be $login2.EnumCredentials()
            $login1.DefaultDatabase | Should -Not -Be $login2.DefaultDatabase
            $login1.IsDisabled | Should -Not -Be $login2.IsDisabled
            $login1.PasswordExpirationEnabled | Should -Not -Be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should -Not -Be $login2.PasswordPolicyEnforced
            $login1.Sid | Should -Not -Be $login2.Sid
        }
        if ($IsWindows -ne $false) {
            It "Should create a disabled account with deny Windows login" {
                $results = New-DbaLogin -SqlInstance $server1 -Login $winLogin -Disabled -DenyWindowsLogin -Force
                $results.Name | Should -Be "$winLogin"
                $results.DefaultDatabase | Should -Be "master"
                $results.IsDisabled | Should -Be $true
                $results.DenyWindowsLogin | Should -Be $true
                $results.LoginType | Should -Be "WindowsUser"
            }
        }
    }

    if ($TestConfig.InstanceMulti1 -and (Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1).LoginMode -eq "Mixed") {
        Context "Connect with a new login" {
            It "Should login with newly created Sql Login, get instance name and kill the process" {
                $cred = New-Object System.Management.Automation.PSCredential ("tester", $securePassword)
                $s = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $cred
                $s.Name | Should -Be $TestConfig.InstanceMulti1
                Stop-DbaProcess -SqlInstance $TestConfig.InstanceMulti1 -Login tester
            }
        }
    }

    Context "No overwrite" {
        It "Should not attempt overwrite" {
            $null = Get-DbaLogin -SqlInstance $server1 -Login tester | New-DbaLogin -SqlInstance $server2 -WarningAction SilentlyContinue -WarningVariable warning 3>&1
            $warning | Should -Match "Login tester already exists"
        }
    }
}