function Test-DbaWindowsLogin {
    <#
    .SYNOPSIS
        Test-DbaWindowsLogin finds any logins on SQL instance that are AD logins with either disabled AD user accounts or ones that no longer exist

    .DESCRIPTION
        The purpose of this function is to find SQL Server logins that are used by active directory users that are either disabled or removed from the domain. It allows you to keep your logins accurate and up to date by removing accounts that are no longer needed.

    .PARAMETER SqlInstance
        The SQL Server instance you're checking logins on. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        Specifies a list of logins to include in the results. Options for this list are auto-populated from the server.

    .PARAMETER ExcludeLogin
        Specifies a list of logins to exclude from the results. Options for this list are auto-populated from the server.

    .PARAMETER FilterBy
        Specifies the object types to return. By default, both Logins and Groups are returned. Valid options for this parameter are 'GroupsOnly' and 'LoginsOnly'.

    .PARAMETER IgnoreDomains
        Specifies a list of Active Directory domains to ignore. By default, all domains in the forest as well as all trusted domains are traversed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Security
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/ | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaWindowsLogin

    .EXAMPLE
        PS C:\> Test-DbaWindowsLogin -SqlInstance Dev01

        Tests all logins in the current Active Directory domain that are either disabled or do not exist on the SQL Server instance Dev01

    .EXAMPLE
        PS C:\> Test-DbaWindowsLogin -SqlInstance Dev01 -FilterBy GroupsOnly | Select-Object -Property *

        Tests all Active Directory groups that have logins on Dev01, and shows all information for those logins

    .EXAMPLE
        PS C:\> Test-DbaWindowsLogin -SqlInstance Dev01 -IgnoreDomains testdomain

        Tests all Domain logins excluding any that are from the testdomain

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [ValidateSet("LoginsOnly", "GroupsOnly", "None")]
        [string]$FilterBy = "None",
        [string[]]$IgnoreDomains,
        [switch]$EnableException
    )

    begin {
        if ($IgnoreDomains) {
            $IgnoreDomainsNormalized = $IgnoreDomains.ToUpper()
            Write-Message -Message ("Excluding logins for domains " + ($IgnoreDomains -join ',')) -Level Verbose
        }

        $mappingRaw = @{
            'SCRIPT'                                 = 1
            'ACCOUNTDISABLE'                         = 2
            'HOMEDIR_REQUIRED'                       = 8
            'LOCKOUT'                                = 16
            'PASSWD_NOTREQD'                         = 32
            'PASSWD_CANT_CHANGE'                     = 64
            'ENCRYPTED_TEXT_PASSWORD_ALLOWED'        = 128
            'TEMP_DUPLICATE_ACCOUNT'                 = 256
            'NORMAL_ACCOUNT'                         = 512
            'INTERDOMAIN_TRUST_ACCOUNT'              = 2048
            'WORKSTATION_TRUST_ACCOUNT'              = 4096
            'SERVER_TRUST_ACCOUNT'                   = 8192
            'DONT_EXPIRE_PASSWD'                     = 65536
            'MNS_LOGON_ACCOUNT'                      = 131072
            'SMARTCARD_REQUIRED'                     = 262144
            'TRUSTED_FOR_DELEGATION'                 = 524288
            'NOT_DELEGATED'                          = 1048576
            'USE_DES_KEY_ONLY'                       = 2097152
            'DONT_REQUIRE_PREAUTH'                   = 4194304
            'PASSWORD_EXPIRED'                       = 8388608
            'TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION' = 16777216
            'NO_AUTH_DATA_REQUIRED'                  = 33554432
            'PARTIAL_SECRETS_ACCOUNT'                = 67108864
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                Write-Message -Message "Connected to: $instance." -Level Verbose
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            # we can only validate AD logins
            $allWindowsLoginsGroups = $server.Logins | Where-Object { $_.LoginType -in ('WindowsUser', 'WindowsGroup') }

            # we cannot validate local users
            $allWindowsLoginsGroups = $allWindowsLoginsGroups | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name.StartsWith($server.ComputerName) -eq $false -and $_.Name.StartsWith("BUILTIN") -eq $false }
            if ($Login) {
                $allWindowsLoginsGroups = $allWindowsLoginsGroups | Where-Object Name -In $Login
            }
            if ($ExcludeLogin) {
                $allWindowsLoginsGroups = $allWindowsLoginsGroups | Where-Object Name -NotIn $ExcludeLogin
            }
            switch ($FilterBy) {
                "LoginsOnly" {
                    Write-Message -Message "Search restricted to logins." -Level Verbose
                    $windowsLogins = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsUser'
                }
                "GroupsOnly" {
                    Write-Message -Message "Search restricted to groups." -Level Verbose
                    $windowsGroups = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsGroup'
                }
                "None" {
                    Write-Message -Message "Search both logins and groups." -Level Verbose
                    $windowsLogins = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsUser'
                    $windowsGroups = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsGroup'
                }
            }
            foreach ($login in $windowsLogins) {
                $adLogin = $login.Name
                $loginSid = $login.Sid -join ''
                $domain, $username = $adLogin.Split("\")
                if ($domain.ToUpper() -in $IgnoreDomainsNormalized) {
                    Write-Message -Message "Skipping Login $adLogin." -Level Verbose
                    continue
                }
                Write-Message -Message "Parsing Login $adLogin." -Level Verbose
                $exists = $false
                try {
                    $u = Get-DbaADObject -ADObject $adLogin -Type User -EnableException
                    if ($null -eq $u -and $adLogin -like '*$') {
                        Write-Message -Message "Parsing Login as computer" -Level Verbose
                        $u = Get-DbaADObject -ADObject $adLogin -Type Computer -EnableException
                        $adType = 'Computer'
                    } else {
                        $adType = 'User'
                    }
                    $foundUser = $u.GetUnderlyingObject()
                    $foundSid = $foundUser.ObjectSid.Value -join ''
                    if ($foundUser) {
                        $exists = $true
                    }
                    if ($foundSid -ne $loginSid) {
                        Write-Message -Message "SID mismatch detected for $adLogin." -Level Warning
                        Write-Message -Message "SID mismatch detected for $adLogin (MSSQL: $loginSid, AD: $foundSid)." -Level Debug
                        $exists = $false
                    }
                } catch {
                    Write-Message -Message "AD Searcher Error for $username." -Level Warning
                }

                $uac = $foundUser.Properties.UserAccountControl

                $additionalProps = @{
                    AccountNotDelegated               = $null
                    AllowReversiblePasswordEncryption = $null
                    CannotChangePassword              = $null
                    PasswordExpired                   = $null
                    LockedOut                         = $null
                    Enabled                           = $null
                    PasswordNeverExpires              = $null
                    PasswordNotRequired               = $null
                    SmartcardLogonRequired            = $null
                    TrustedForDelegation              = $null
                }
                if ($uac) {
                    $additionalProps = @{
                        AccountNotDelegated               = [bool]($uac.Value -band $mappingRaw['NOT_DELEGATED'])
                        AllowReversiblePasswordEncryption = [bool]($uac.Value -band $mappingRaw['ENCRYPTED_TEXT_PASSWORD_ALLOWED'])
                        CannotChangePassword              = [bool]($uac.Value -band $mappingRaw['PASSWD_CANT_CHANGE'])
                        PasswordExpired                   = [bool]($uac.Value -band $mappingRaw['PASSWORD_EXPIRED'])
                        LockedOut                         = [bool]($uac.Value -band $mappingRaw['LOCKOUT'])
                        Enabled                           = !($uac.Value -band $mappingRaw['ACCOUNTDISABLE'])
                        PasswordNeverExpires              = [bool]($uac.Value -band $mappingRaw['DONT_EXPIRE_PASSWD'])
                        PasswordNotRequired               = [bool]($uac.Value -band $mappingRaw['PASSWD_NOTREQD'])
                        SmartcardLogonRequired            = [bool]($uac.Value -band $mappingRaw['SMARTCARD_REQUIRED'])
                        TrustedForDelegation              = [bool]($uac.Value -band $mappingRaw['TRUSTED_FOR_DELEGATION'])
                        UserAccountControl                = $uac.Value
                    }
                }
                $rtn = [PSCustomObject]@{
                    Server                            = $server.DomainInstanceName
                    Domain                            = $domain
                    Login                             = $username
                    Type                              = $adType
                    Found                             = $exists
                    DisabledInSQLServer               = $login.IsDisabled
                    AccountNotDelegated               = $additionalProps.AccountNotDelegated
                    AllowReversiblePasswordEncryption = $additionalProps.AllowReversiblePasswordEncryption
                    CannotChangePassword              = $additionalProps.CannotChangePassword
                    PasswordExpired                   = $additionalProps.PasswordExpired
                    LockedOut                         = $additionalProps.LockedOut
                    Enabled                           = $additionalProps.Enabled
                    PasswordNeverExpires              = $additionalProps.PasswordNeverExpires
                    PasswordNotRequired               = $additionalProps.PasswordNotRequired
                    SmartcardLogonRequired            = $additionalProps.SmartcardLogonRequired
                    TrustedForDelegation              = $additionalProps.TrustedForDelegation
                    UserAccountControl                = $additionalProps.UserAccountControl
                }

                Select-DefaultView -InputObject $rtn -ExcludeProperty AccountNotDelegated, AllowReversiblePasswordEncryption, CannotChangePassword, PasswordNeverExpires, SmartcardLogonRequired, TrustedForDelegation, UserAccountControl

            }

            foreach ($login in $windowsGroups) {
                $adLogin = $login.Name
                $loginSid = $login.Sid -join ''
                $domain, $groupName = $adLogin.Split("\")
                if ($domain.ToUpper() -in $IgnoreDomainsNormalized) {
                    Write-Message -Message "Skipping Login $adLogin." -Level Verbose
                    continue
                }
                Write-Message -Message "Parsing Login $adLogin on $server." -Level Verbose
                $exists = $false
                try {
                    $u = Get-DbaADObject -ADObject $adLogin -Type Group -EnableException
                    $foundUser = $u.GetUnderlyingObject()
                    $foundSid = $foundUser.objectSid.Value -join ''
                    if ($foundUser) {
                        $exists = $true
                    }
                    if ($foundSid -ne $loginSid) {
                        Write-Message -Message "SID mismatch detected for $adLogin." -Level Warning
                        Write-Message -Message "SID mismatch detected for $adLogin (MSSQL: $loginSid, AD: $foundSid)." -Level Debug
                        $exists = $false
                    }
                } catch {
                    Write-Message -Message "AD Searcher Error for $groupName on $server" -Level Warning
                }
                $rtn = [PSCustomObject]@{
                    Server                            = $server.DomainInstanceName
                    Domain                            = $domain
                    Login                             = $groupName
                    Type                              = "Group"
                    Found                             = $exists
                    DisabledInSQLServer               = $login.IsDisabled
                    AccountNotDelegated               = $null
                    AllowReversiblePasswordEncryption = $null
                    CannotChangePassword              = $null
                    PasswordExpired                   = $null
                    LockedOut                         = $null
                    Enabled                           = $null
                    PasswordNeverExpires              = $null
                    PasswordNotRequired               = $null
                    SmartcardLogonRequired            = $null
                    TrustedForDelegation              = $null
                    UserAccountControl                = $null
                }

                Select-DefaultView -InputObject $rtn -ExcludeProperty AccountNotDelegated, AllowReversiblePasswordEncryption, CannotChangePassword, PasswordNeverExpires, SmartcardLogonRequired, TrustedForDelegation, UserAccountControl

            }
        }
    }
}