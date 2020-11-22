function New-DbaLogin {
    <#
    .SYNOPSIS
        Creates a new SQL Server login

    .DESCRIPTION
        Creates a new SQL Server login with provided specifications

    .PARAMETER SqlInstance
        The target SQL Server(s)

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        The Login name(s)

    .PARAMETER SecurePassword
        Secure string used to authenticate the Login

    .PARAMETER HashedPassword
        Hashed password string used to authenticate the Login

    .PARAMETER InputObject
        Takes the parameters required from a Login object that has been piped into the command

    .PARAMETER LoginRenameHashtable
        Pass a hash table into this parameter to change login names when piping objects into the procedure

    .PARAMETER MapToCertificate
        Map the login to a certificate

    .PARAMETER MapToAsymmetricKey
        Map the login to an asymmetric key

    .PARAMETER MapToCredential
        Map the login to a credential

    .PARAMETER Sid
        Provide an explicit Sid that should be used when creating the account. Can be [byte[]] or hex [string] ('0xFFFF...')

    .PARAMETER DefaultDatabase
        Default database for the login

    .PARAMETER Language
        Login's default language

    .PARAMETER PasswordExpirationEnabled
        Enforces password expiration policy. Requires PasswordPolicyEnforced to be enabled. Can be $true or $false(default)

    .PARAMETER PasswordPolicyEnforced
        Enforces password complexity policy. Can be $true or $false(default)

    .PARAMETER PasswordMustChange
        Enforces user must change password at next login.
        When specified will enforce PasswordExpirationEnabled and PasswordPolicyEnforced as they are required for the must change.

    .PARAMETER Disabled
        Create the login in a disabled state

    .PARAMETER DenyWindowsLogin
        Create the login and deny Windows login ability

    .PARAMETER NewSid
        Ignore sids from the piped login object to generate new sids on the server. Useful when copying login onto the same server

    .PARAMETER Force
        If login exists, drop and recreate

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Security
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaLogin

    .EXAMPLE
        PS C:\> New-DbaLogin -SqlInstance Server1,Server2 -Login Newlogin

        You will be prompted to securely enter the password for a login [Newlogin]. The login would be created on servers Server1 and Server2 with default parameters.

    .EXAMPLE
        PS C:\> $securePassword = Read-Host "Input password" -AsSecureString
        PS C:\> New-DbaLogin -SqlInstance Server1\sql1 -Login Newlogin -SecurePassword $securePassword -PasswordPolicyEnforced -PasswordExpirationEnabled

        Creates a login on Server1\sql1 with a predefined password. The login will have password and expiration policies enforced onto it.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql1 -Login Oldlogin | New-DbaLogin -SqlInstance sql1 -LoginRenameHashtable @{Oldlogin = 'Newlogin'} -Force -NewSid -Disabled:$false

        Copies a login [Oldlogin] to the same instance sql1 with the same parameters (including password). New login will have a new sid, a new name [Newlogin] and will not be disabled. Existing login [Newlogin] will be removed prior to creation.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql1 -Login Login1,Login2 | New-DbaLogin -SqlInstance sql2 -PasswordPolicyEnforced -PasswordExpirationEnabled -DefaultDatabase tempdb -Disabled

        Copies logins [Login1] and [Login2] from instance sql1 to instance sql2, but enforces password and expiration policies for the new logins. New logins will also have a default database set to [tempdb] and will be created in a disabled state.

    .EXAMPLE
        PS C:\> New-DbaLogin -SqlInstance sql1 -Login domain\user

        Creates a new Windows Authentication backed login on sql1. The login will be part of the public server role.

    .EXAMPLE
        PS C:\> New-DbaLogin -SqlInstance sql1 -Login domain\user1, domain\user2 -DenyWindowsLogin

        Creates two new Windows Authentication backed login on sql1. The logins would be denied from logging in.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Password", ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameters Password and MapToCredential")]
    param (
        [parameter(Mandatory, Position = 1)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Name", "LoginName")]
        [parameter(ParameterSetName = "Password", Position = 2)]
        [parameter(ParameterSetName = "PasswordHash")]
        [parameter(ParameterSetName = "MapToCertificate")]
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [string[]]$Login,
        [parameter(ValueFromPipeline)]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [parameter(ParameterSetName = "MapToCertificate")]
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [object[]]$InputObject,
        [Alias("Rename")]
        [hashtable]$LoginRenameHashtable,
        [parameter(ParameterSetName = "Password", Position = 3)]
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [Alias("Hash", "PasswordHash")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$HashedPassword,
        [parameter(ParameterSetName = "MapToCertificate")]
        [string]$MapToCertificate,
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [string]$MapToAsymmetricKey,
        [string]$MapToCredential,
        [object]$Sid,
        [Alias("DefaultDB")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$DefaultDatabase,
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$Language,
        [Alias("Expiration", "CheckExpiration")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [switch]$PasswordExpirationEnabled,
        [Alias("Policy", "CheckPolicy")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [switch]$PasswordPolicyEnforced,
        [Alias("MustChange")]
        [parameter(ParameterSetName = "Password")]
        [switch]$PasswordMustChange,
        [Alias("Disable")]
        [switch]$Disabled,
        [switch]$DenyWindowsLogin,
        [switch]$NewSid,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Sid) {
            if ($Sid.GetType().Name -ne 'Byte[]') {
                foreach ($symbol in $Sid.TrimStart("0x").ToCharArray()) {
                    if ($symbol -notin "0123456789ABCDEF".ToCharArray()) {
                        Stop-Function -Message "Sid has invalid character '$symbol', cannot proceed." -Category InvalidArgument -EnableException $EnableException
                        return
                    }
                }
                $Sid = Convert-HexStringToByte $Sid
            }
        }

        if ($HashedPassword) {
            if ($HashedPassword.GetType().Name -eq 'Byte[]') {
                $HashedPassword = Convert-ByteToHexString $HashedPassword
            }
        }
    }

    process {
        #At least one of those should be specified
        if (!($Login -or $InputObject)) {
            Stop-Function -Message "No logins have been specified." -Category InvalidArgument -EnableException $EnableException
            Return
        }

        if ($PasswordMustChange -and (-not $SecurePassword)) {
            Stop-Function -Message "You need to specified -SecurePassword when using -PasswordMustChange parameter." -Category InvalidArgument -EnableException $EnableException
            Return
        }

        $loginCollection = @()
        if ($InputObject) {
            $loginCollection += $InputObject
            if ($Login) {
                Stop-Function -Message "Parameter -Login is not supported when processing objects from -InputObject. If you need to rename the logins, please use -LoginRenameHashtable." -Category InvalidArgument -EnableException $EnableException
                Return
            }
        } else {
            $loginCollection += $Login
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($loginItem in $loginCollection) {
                $usedTsql = $false
                #check if $loginItem is an SMO Login object
                if ($loginItem.GetType().Name -eq 'Login') {
                    #Get all the necessary fields
                    $loginName = $loginItem.Name
                    $loginType = $loginItem.LoginType
                    $currentSid = $loginItem.Sid
                    $currentDefaultDatabase = $loginItem.DefaultDatabase
                    $currentLanguage = $loginItem.Language
                    $currentPasswordExpirationEnabled = $loginItem.PasswordExpirationEnabled
                    $currentPasswordPolicyEnforced = $loginItem.PasswordPolicyEnforced
                    $currentPasswordMustChange = $loginItem.MustChangePassword
                    $currentDisabled = $loginItem.IsDisabled
                    $currentDenyWindowsLogin = $loginItem.DenyWindowsLogin
                    #Get previous password
                    if ($loginType -eq 'SqlLogin' -and !($SecurePassword -or $HashedPassword)) {
                        $sourceServer = $loginItem.Parent
                        switch ($sourceServer.versionMajor) {
                            0 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$loginName'" }
                            8 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM dbo.syslogins WHERE name='$loginName'" }
                            9 { $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins where name='$loginName'" }
                            default {
                                $sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash')
                                    AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass
                                    FROM sys.server_principals
                                    WHERE principal_id = $($loginItem.id)"
                            }
                        }

                        try {
                            $hashedPass = $sourceServer.ConnectionContext.ExecuteScalar($sql)
                        } catch {
                            $hashedPassDt = $sourceServer.Databases['master'].ExecuteWithResults($sql)
                            $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
                        }

                        if ($hashedPass.GetType().Name -ne "String") {
                            $hashedPass = Convert-ByteToHexString $hashedPass
                        }
                        $currentHashedPassword = $hashedPass
                    }

                    #Get cryptography and attached credentials
                    if ($loginType -eq 'AsymmetricKey') {
                        $currentAsymmetricKey = $loginItem.AsymmetricKey
                    }
                    if ($loginType -eq 'Certificate') {
                        $currentCertificate = $loginItem.Certificate
                    }
                    #This method or property is accessible only while working with SQL Server 2008 or later.
                    if ($sourceServer.versionMajor -gt 9) {
                        if ($loginItem.EnumCredentials()) {
                            $currentCredential = $loginItem.EnumCredentials()
                        }
                    }
                } else {
                    $loginName = $loginItem
                    $currentSid = $currentDefaultDatabase = $currentLanguage = $currentPasswordExpirationEnabled = $currentAsymmetricKey = $currentCertificate = $currentCredential = $currentDisabled = $currentPasswordPolicyEnforced = $currentDenyWindowsLogin = $null

                    if ($PsCmdlet.ParameterSetName -eq "MapToCertificate") { $loginType = 'Certificate' }
                    elseif ($PsCmdlet.ParameterSetName -eq "MapToAsymmetricKey") { $loginType = 'AsymmetricKey' }
                    elseif ($loginItem.IndexOf('\') -eq -1) { $loginType = 'SqlLogin' }
                    else { $loginType = 'WindowsUser' }
                }

                if ((-not $server.IsAzure) -and ($server.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($loginType -eq 'SqlLogin')) {
                    Write-Message -Level Warning -Message "$instance does not have Mixed Mode enabled. [$loginName] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
                }

                if ($Sid) {
                    $currentSid = $Sid
                }
                if ($DefaultDatabase) {
                    $currentDefaultDatabase = $DefaultDatabase
                }
                if ($Language) {
                    $currentLanguage = $Language
                }
                if ($PSBoundParameters.Keys -contains 'PasswordExpirationEnabled') {
                    $currentPasswordExpirationEnabled = $PasswordExpirationEnabled
                }
                if ($PSBoundParameters.Keys -contains 'PasswordPolicyEnforced') {
                    $currentPasswordPolicyEnforced = $PasswordPolicyEnforced
                }
                if ($PSBoundParameters.Keys -contains 'PasswordMustChange') {
                    $currentPasswordMustChange = $PasswordMustChange
                    # Enforce Expiration and Policy properties as they are needed when we want to use "Must Change" property
                    Write-Message -Level Verbose -Message "Forcing 'Expiration' and 'Policy' properties to 'ON' because MustChange was specified."
                    $currentPasswordExpirationEnabled = $true
                    $currentPasswordPolicyEnforced = $true
                }
                if ($PSBoundParameters.Keys -contains 'MapToAsymmetricKey') {
                    $currentAsymmetricKey = $MapToAsymmetricKey
                }
                if ($PSBoundParameters.Keys -contains 'MapToCertificate') {
                    $currentCertificate = $MapToCertificate
                }
                if ($PSBoundParameters.Keys -contains 'MapToCredential') {
                    $currentCredential = $MapToCredential
                }
                if ($PSBoundParameters.Keys -contains 'Disabled') {
                    $currentDisabled = $Disabled
                }
                if (Test-Bound -Parameter DenyWindowsLogin) {
                    $currentDenyWindowsLogin = $DenyWindowsLogin
                }

                #Apply renaming if necessary
                if ($LoginRenameHashtable.Keys -contains $loginName) {
                    $loginName = $LoginRenameHashtable[$loginName]
                }

                #Requesting password if required
                if ($loginItem.GetType().Name -ne 'Login' -and $loginType -eq 'SqlLogin' -and !($SecurePassword -or $HashedPassword)) {
                    $SecurePassword = Read-Host -AsSecureString -Prompt "Enter a new password for the SQL Server login(s)"
                }

                #verify if login exists on the server
                if (($existingLogin = $server.Logins[$loginName])) {
                    if ($force) {
                        if ($Pscmdlet.ShouldProcess($existingLogin, "Dropping existing login $loginName on $instance because -Force was used")) {
                            try {
                                $existingLogin.Drop()
                            } catch {
                                Stop-Function -Message "Could not remove existing login $loginName on $instance, skipping." -Target $loginName -Continue
                            }
                        }
                    } else {
                        Stop-Function -Message "Login $loginName already exists on $instance and -Force was not specified" -Target $loginName -Continue
                    }
                }


                if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating login $loginName on $instance")) {
                    try {
                        $loginName = $loginName.Replace('[', '').Replace(']', '')
                        $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $loginName)
                        $newLogin.LoginType = $loginType

                        $withParams = ""

                        if ($loginType -eq 'SqlLogin' -and $currentSid -and !$NewSid) {
                            Write-Message -Level Verbose -Message "Setting $loginName SID"
                            $withParams += ", SID = " + (Convert-ByteToHexString $currentSid)
                            $newLogin.Set_Sid($currentSid)
                        }

                        if ($loginType -in ("WindowsUser", "WindowsGroup", "SqlLogin")) {
                            if ($currentDefaultDatabase) {
                                Write-Message -Level Verbose -Message "Setting $loginName default database to $currentDefaultDatabase"
                                $withParams += ", DEFAULT_DATABASE = [$currentDefaultDatabase]"
                                $newLogin.DefaultDatabase = $currentDefaultDatabase
                            }

                            if ($currentLanguage) {
                                Write-Message -Level Verbose -Message "Setting $loginName language to $currentLanguage"
                                $withParams += ", DEFAULT_LANGUAGE = [$currentLanguage]"
                                $newLogin.Language = $currentLanguage
                            }

                            #CHECK_EXPIRATION: default - OFF
                            if ($currentPasswordExpirationEnabled) {
                                $withParams += ", CHECK_EXPIRATION = ON"
                                $newLogin.PasswordExpirationEnabled = $true
                            } elseif ($loginType -eq 'SqlLogin') {
                                $withParams += ", CHECK_EXPIRATION = OFF"
                                $newLogin.PasswordExpirationEnabled = $false
                            }

                            #CHECK_POLICY: default - ON
                            if ($currentPasswordPolicyEnforced) {
                                $withParams += ", CHECK_POLICY = ON"
                                $newLogin.PasswordPolicyEnforced = $true
                            } elseif ($loginType -eq 'SqlLogin') {
                                $withParams += ", CHECK_POLICY = OFF"
                                $newLogin.PasswordPolicyEnforced = $false
                            }

                            # DENY CONNECT SQL
                            if ($currentDenyWindowsLogin) {
                                Write-Message -Level VeryVerbose -Message "Setting $loginName DenyWindowsLogin to $currentDenyWindowsLogin"
                                $newLogin.DenyWindowsLogin = $currentDenyWindowsLogin
                            }

                            #Generate hashed password if necessary
                            if ($SecurePassword) {
                                $currentHashedPassword = Get-PasswordHash $SecurePassword $server.versionMajor
                            } elseif ($HashedPassword) {
                                $currentHashedPassword = $HashedPassword
                            }
                        } elseif ($loginType -eq 'AsymmetricKey') {
                            $newLogin.AsymmetricKey = $currentAsymmetricKey
                        } elseif ($loginType -eq 'Certificate') {
                            $newLogin.Certificate = $currentCertificate
                        }

                        #Add credential
                        if ($currentCredential) {
                            $withParams += ", CREDENTIAL = [$currentCredential]"
                        }

                        Write-Message -Level Verbose -Message "Adding as login type $loginType"

                        # Attempt to add login using SMO, then T-SQL
                        try {
                            if ($loginType -in ("WindowsUser", "WindowsGroup", "AsymmetricKey", "Certificate")) {
                                if ($withParams) { $withParams = " WITH " + $withParams.TrimStart(',') }
                                $newLogin.Create()
                            } elseif ($loginType -eq "SqlLogin") {
                                $newLogin.Create($currentHashedPassword, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
                            }
                            $newLogin.Refresh()

                            #Adding credential
                            if ($currentCredential) {
                                try {
                                    $newLogin.AddCredential($currentCredential)
                                } catch {
                                    $newLogin.Drop()
                                    Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                            Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
                        } catch {
                            Write-Message -Level Verbose -Message "Failed to create $loginName on $instance using SMO, trying T-SQL."
                            try {
                                if ($loginType -eq 'AsymmetricKey') { $sql = "CREATE LOGIN [$loginName] FROM ASYMMETRIC KEY [$currentAsymmetricKey]" }
                                elseif ($loginType -eq 'Certificate') { $sql = "CREATE LOGIN [$loginName] FROM CERTIFICATE [$currentCertificate]" }
                                elseif ($loginType -eq 'SqlLogin' -and $server.DatabaseEngineType -eq 'SqlAzureDatabase') {
                                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword) # Azure SQL doesn't support HASHED so we have to dump out the plain text password :(
                                    $unsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                                    $sql = "CREATE LOGIN [$loginName] WITH PASSWORD = '$unsecurePassword'"
                                } elseif ($loginType -eq 'SqlLogin' ) { $sql = "CREATE LOGIN [$loginName] WITH PASSWORD = $currentHashedPassword HASHED" + $withParams }
                                else { $sql = "CREATE LOGIN [$loginName] FROM WINDOWS" + $withParams }
                                $null = $server.Query($sql)
                                $newLogin = $server.logins[$loginName]
                                Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
                                $usedTsql = $true
                            } catch {
                                Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                            }
                        }

                        #Process the Disabled property
                        if ($currentDisabled) {
                            try {
                                $newLogin.Disable()
                                Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance."
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to disable $loginName on $instance using SMO, trying T-SQL."
                                try {
                                    $sql = "ALTER LOGIN [$loginName] DISABLE"
                                    $null = $server.Query($sql)
                                    Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance."
                                    $usedTsql = $true
                                } catch {
                                    Stop-Function -Message "Failed to disable $loginName on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                        }
                        #Process the DenyWindowsLogin property
                        if ($currentDenyWindowsLogin -ne $newLogin.DenyWindowsLogin) {
                            try {
                                $newLogin.DenyWindowsLogin = $currentDenyWindowsLogin
                                $newLogin.Alter()
                                Write-Message -Level Verbose -Message "Login $loginName has been denied from logging in on $instance."
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to deny from logging in $loginName on $instance using SMO, trying T-SQL."
                                try {
                                    $sql = "DENY CONNECT SQL TO [{0}]" -f $newLogin.Name
                                    $null = $server.Query($sql)
                                    Write-Message -Level Verbose -Message "Login $loginName has been denied from logging in on $instance."
                                    $usedTsql = $true
                                } catch {
                                    Stop-Function -Message "Failed to set deny windows login priviledge $loginName on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                        }

                        #Process the MustChangePassword property
                        if ($currentPasswordMustChange -ne $newLogin.MustChangePassword) {
                            try {
                                $newLogin.ChangePassword($SecurePassword, $true, $true)
                                Write-Message -Level Verbose -Message "Login $loginName has been marked as must change password."

                                # We need to refresh login after ChangePassword. Otherwise, MustChangePassword will appear as False
                                $server.Logins[$loginName].Refresh()
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to marked as must change password in $loginName on $instance using SMO."
                            }
                        }

                        #Display results
                        # If we ever used T-SQL, the smo is some times not up to date and should be refreshed
                        if ($usedTsql) {
                            $server.Logins.Refresh()
                        }

                        Get-DbaLogin -SqlInstance $server -Login $loginName

                    } catch {
                        Stop-Function -Message "Failed to create login $loginName on $instance." -Target $credential -InnerErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}
