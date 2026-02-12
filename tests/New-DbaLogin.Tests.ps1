#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        }

        It "Should be created successfully - Hashed password" {
            $script:outputValidationResult = New-DbaLogin -SqlInstance $server1 -Login tester -HashedPassword (Get-PasswordHash $securePassword $server1.VersionMajor) -Force
            $script:outputValidationResult.Name | Should -Be "tester"
            $script:outputValidationResult.DefaultDatabase | Should -Be "master"
            $script:outputValidationResult.IsDisabled | Should -Be $false
            $script:outputValidationResult.PasswordExpirationEnabled | Should -Be $false
            $script:outputValidationResult.PasswordPolicyEnforced | Should -Be $false
            $script:outputValidationResult.MustChangePassword | Should -Be $false
            $script:outputValidationResult.LoginType | Should -Be "SqlLogin"
        }
        It "Should be created successfully - password, credential and a custom sid " {
            $splatNewLogin = @{
                SqlInstance        = $server1
                Login              = "claudio"
                Password           = $securePassword
                Sid                = $sid
                MapToCredential    = $credLogin
            }
            $results = New-DbaLogin @splatNewLogin
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
            $splatNewLogin = @{
                SqlInstance         = $server1
                Login               = "port"
                Password            = $securePassword
                PasswordPolicy      = $true
                PasswordExpiration  = $true
                DefaultDatabase     = "tempdb"
                Disabled            = $true
                Language            = "Nederlands"
                DenyWindowsLogin    = $true
            }
            $results = New-DbaLogin @splatNewLogin
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
            $splatNewLogin = @{
                SqlInstance         = $server1
                Login               = "withMustChange"
                Password            = $securePassword
                PasswordPolicy      = $true
                PasswordExpiration  = $true
                PasswordMustChange  = $true
                DefaultDatabase     = "tempdb"
                Disabled            = $true
                Language            = "Nederlands"
                DenyWindowsLogin    = $true
            }
            $results = New-DbaLogin @splatNewLogin
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
            $splatNewLogin = @{
                SqlInstance         = $server1
                Login               = "MustChange"
                Password            = $securePassword
                PasswordMustChange  = $true
                DefaultDatabase     = "tempdb"
                Disabled            = $true
                Language            = "Nederlands"
                DenyWindowsLogin    = $true
            }
            $results = New-DbaLogin @splatNewLogin
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

        Context "Output validation" {
            It "Returns output of the expected type" {
                $script:outputValidationResult | Should -Not -BeNullOrEmpty
                $script:outputValidationResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Login"
            }

            It "Has the expected default display properties" {
                $script:outputValidationResult | Should -Not -BeNullOrEmpty
                $defaultProps = $script:outputValidationResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "Name",
                    "LoginType",
                    "CreateDate",
                    "LastLogin",
                    "HasAccess",
                    "IsLocked",
                    "IsDisabled",
                    "MustChangePassword"
                )
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }
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

    if ((Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1).LoginMode -eq "Mixed") {
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