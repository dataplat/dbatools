function New-DbaLogin {
    <#
    .SYNOPSIS
    Creates a new SQL Server login

    .DESCRIPTION
    Creates a new SQL Server login with provided specifications

    .PARAMETER SqlInstance
    The target SQL Server(s)

    .PARAMETER SqlCredential
    Allows you to login to SQL Server using alternative credentials

    .PARAMETER Login
    The Login name(s)

    .PARAMETER Password
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

    .PARAMETER PasswordExpiration
    Enforces password expiration policy. Requires PasswordPolicy to be enabled. Can be $true or $false(default)

    .PARAMETER PasswordPolicy
    Enforces password complexity policy. Can be $true or $false(default)

    .PARAMETER Disabled
    Create the login in a disabled state

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
    Tags: Login
    Author: Kirill Kravtsov (@nvarscar)
    dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
    Copyright (C) 2016 Chrissy LeMaire
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/New-DbaLogin

    .EXAMPLE
    New-DbaLogin -SqlInstance Server1,Server2 -Login Newlogin

    You will be prompted to securely enter the password for a login [Newlogin]. The login would be created on servers Server1 and Server2 with default parameters.

    .EXAMPLE
    $securePassword = Read-Host "Input password" -AsSecureString
    New-DbaLogin -SqlInstance Server1\sql1 -Login Newlogin -Password $securePassword -PasswordPolicy -PasswordExpiration

    Creates a login on Server1\sql1 with a predefined password. The login will have password and expiration policies enforced onto it.

    .EXAMPLE
    Get-DbaLogin -SqlInstance sql1 -Login Oldlogin | New-DbaLogin -SqlInstance sql1 -LoginRenameHashtable @{Oldlogin = 'Newlogin'} -Force -NewSid -Disabled:$false

    Copies a login [Oldlogin] to the same instance sql1 with the same parameters (including password). New login will have a new sid, a new name [Newlogin] and will not be disabled. Existing login [Newlogin] will be removed prior to creation.

    .EXAMPLE
    Get-DbaLogin -SqlInstance sql1 -Login Login1,Login2 | New-DbaLogin -SqlInstance sql2 -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled

    Copies logins [Login1] and [Login2] from instance sql1 to instance sql2, but enforces password and expiration policies for the new logins. New logins will also have a default database set to [tempdb] and will be created in a disabled state.
#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Password")]
    param (
        [parameter(Mandatory, Position = 1)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Name", "LoginName")]
        [parameter(ParameterSetName = "Password", Position = 2)]
        [parameter(ParameterSetName = "PasswordHash")]
        [parameter(ParameterSetName = "MapToCertificate")]
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [string[]]$Login,
        [parameter(ValueFromPipeline = $true)]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [parameter(ParameterSetName = "MapToCertificate")]
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [object[]]$InputObject,
        [Alias("Rename")]
        [hashtable]$LoginRenameHashtable,
        [parameter(ParameterSetName = "Password", Position = 3)]
        [Security.SecureString]$Password,
        [Alias("Hash", "PasswordHash")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$HashedPassword,
        [parameter(ParameterSetName = "MapToCertificate")]
        [string]$MapToCertificate,
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [string]$MapToAsymmetricKey,
        [string]$MapToCredential,
        [object]$Sid,
        [Alias("DefaulDB")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$DefaultDatabase,
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$Language,
        [Alias("Expiration", "CheckExpiration")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [switch]$PasswordExpiration,
        [Alias("Policy", "CheckPolicy")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [switch]$PasswordPolicy,
        [Alias("Disable")]
        [switch]$Disabled,
        [switch]$NewSid,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
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

        $loginCollection = @()
        if ($InputObject) {
            $loginCollection += $InputObject
            if ($Login) {
                Stop-Function -Message "Parameter -Login is not supported when processing objects from -InputObject. If you need to rename the logins, please use -LoginRenameHashtable." -Category InvalidArgument -EnableException $EnableException
                Return
            }
        }
        else {
            $loginCollection += $Login
            $Login | ForEach-Object {
                if ($_.IndexOf('\') -eq -1 -and $PsCmdlet.ParameterSetName -like "Password*" -and !($Password -or $HashedPassword)) {
                    $passwordNotSpecified = $true
                }
            }
        }
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($loginItem in $loginCollection) {
                #check if $loginItem is an SMO Login object
                if ($loginItem.GetType().Name -eq 'Login') {
                    #Get all the necessary fields
                    $loginName = $loginItem.Name
                    $loginType = $loginItem.LoginType
                    $currentSid = $loginItem.Sid
                    $currentDefaultDatabase = $loginItem.DefaultDatabase
                    $currentLanguage = $loginItem.Language
                    $currentPasswordExpiration = $loginItem.PasswordExpiration
                    $currentPasswordPolicyEnforced = $loginItem.PasswordPolicyEnforced
                    $currentDisabled = $loginItem.IsDisabled

                    #Get previous password
                    if ($loginType -eq 'SqlLogin' -and !($Password -or $HashedPassword)) {
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
                        }
                        catch {
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
                }
                else {
                    $loginName = $loginItem
                    $currentSid = $currentDefaultDatabase = $currentLanguage = $currentPasswordExpiration = $currentAsymmetricKey = $currentCertificate = $currentCredential = $currentDisabled = $currentPasswordPolicyEnforced = $null

                    if ($PsCmdlet.ParameterSetName -eq "MapToCertificate") { $loginType = 'Certificate' }
                    elseif ($PsCmdlet.ParameterSetName -eq "MapToAsymmetricKey") { $loginType = 'AsymmetricKey' }
                    elseif ($loginItem.IndexOf('\') -eq -1) {    $loginType = 'SqlLogin' }
                    else { $loginType = 'WindowsUser' }
                }

                if (($server.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($loginType -eq 'SqlLogin')) {
                    Write-Message -Level Warning -Message "$instance does not have Mixed Mode enabled. [$loginName] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login." -EnableException $EnableException
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
                if ($PSBoundParameters.Keys -contains 'PasswordExpiration') {
                    $currentPasswordExpiration = $PasswordExpiration
                }
                if ($PSBoundParameters.Keys -contains 'PasswordPolicy') {
                    $currentPasswordPolicyEnforced = $PasswordPolicy
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

                #Apply renaming if necessary
                if ($LoginRenameHashtable.Keys -contains $loginName) {
                    $loginName = $LoginRenameHashtable[$loginName]
                }

                #Requesting password if required
                if ($loginItem.GetType().Name -ne 'Login' -and $loginType -eq 'SqlLogin' -and !($Password -or $HashedPassword)) {
                    $Password = Read-Host -AsSecureString -Prompt "Enter a new password for the SQL Server login(s)"
                }

                #verify if login exists on the server
                if ($existingLogin = $server.Logins[$loginName]) {
                    if ($force) {
                        if ($Pscmdlet.ShouldProcess($existingLogin, "Dropping existing login $loginName on $instance because -Force was used")) {
                            try {
                                $existingLogin.Drop()
                            }
                            catch {
                                Stop-Function -Message "Could not remove existing login $loginName on $instance, skipping." -Target $loginName -Continue
                            }
                        }
                    }
                    else {
                        Stop-Function -Message "Login $loginName already exists on $instance and -Force was not specified" -Target $loginName -Continue
                    }
                }


                if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating login $loginName on $instance")) {
                    try {
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
                            if ($currentPasswordExpiration) {
                                $withParams += ", CHECK_EXPIRATION = ON"
                                $newLogin.PasswordExpirationEnabled = $true
                            }
                            else {
                                $withParams += ", CHECK_EXPIRATION = OFF"
                                $newLogin.PasswordExpirationEnabled = $false
                            }

                            #CHECK_POLICY: default - ON
                            if ($currentPasswordPolicyEnforced) {
                                $withParams += ", CHECK_POLICY = ON"
                                $newLogin.PasswordPolicyEnforced = $true
                            }
                            else {
                                $withParams += ", CHECK_POLICY = OFF"
                                $newLogin.PasswordPolicyEnforced = $false
                            }

                            #Generate hashed password if necessary
                            if ($Password) {
                                $currentHashedPassword = Get-PasswordHash $Password $server.versionMajor
                            }
                            elseif ($HashedPassword) {
                                $currentHashedPassword = $HashedPassword
                            }
                        }
                        elseif ($loginType -eq 'AsymmetricKey') {
                            $newLogin.AsymmetricKey = $currentAsymmetricKey
                        }
                        elseif ($loginType -eq 'Certificate') {
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
                            }
                            elseif ($loginType -eq "SqlLogin") {
                                $newLogin.Create($currentHashedPassword, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
                            }
                            $newLogin.Refresh()

                            #Adding credential
                            if ($currentCredential) {
                                try {
                                    $newLogin.AddCredential($currentCredential)
                                }
                                catch {
                                    $newLogin.Drop()
                                    Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                            Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
                        }
                        catch {
                            Write-Message -Level Verbose -Message "Failed to create $loginName on $instance using SMO, trying T-SQL."
                            try {
                                if ($loginType -eq 'AsymmetricKey') { $sql = "CREATE LOGIN [$loginName] FROM ASYMMETRIC KEY [$currentAsymmetricKey]" }
                                elseif ($loginType -eq 'Certificate') { $sql = "CREATE LOGIN [$loginName] FROM CERTIFICATE [$currentCertificate]" }
                                elseif ($loginType -eq "SqlLogin") { $sql = "CREATE LOGIN [$loginName] WITH PASSWORD = $currentHashedPassword HASHED" + $withParams }
                                else { $sql = "CREATE LOGIN [$loginName] FROM WINDOWS" + $withParams }

                                $null = $server.Query($sql)
                                $newLogin = $server.logins[$loginName]
                                Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
                            }
                            catch {
                                Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                            }
                        }

                        #Process the Disabled property
                        if ($currentDisabled) {
                            try {
                                $newLogin.Disable()
                                Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance."
                            }
                            catch {
                                Write-Message -Level Verbose -Message "Failed to disable $loginName on $instance using SMO, trying T-SQL."
                                try {
                                    $sql = "ALTER LOGIN [$loginName] DISABLE"
                                    $null = $server.Query($sql)
                                    Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance."
                                }
                                catch {
                                    Stop-Function -Message "Failed to disable $loginName on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                        }
                        #Display results
                        Get-DbaLogin -SqlInstance $server -Login $loginName
                    }
                    catch {
                        Stop-Function -Message "Failed to create login $loginName on $instance." -Target $credential -InnerErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}