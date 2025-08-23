function Test-DbaWindowsLogin {
    <#
    .SYNOPSIS
        Validates Windows logins and groups in SQL Server against Active Directory to identify orphaned, disabled, or problematic accounts

    .DESCRIPTION
        Queries SQL Server for all Windows-based logins and groups, then validates each against Active Directory to identify security issues and cleanup opportunities. The function checks whether AD accounts still exist, are enabled, and match their SQL Server SID to detect orphaned logins from domain migrations or account deletions. This helps DBAs maintain login security by identifying stale Windows authentication accounts that should be removed from SQL Server.

    .PARAMETER SqlInstance
        The SQL Server instance you're checking logins on. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        Specifies specific Windows logins to validate against Active Directory. Use this when you want to test only certain logins rather than all Windows accounts on the server.
        Accepts wildcards and multiple values. Helpful for focused security audits of high-privilege accounts or problem logins.

    .PARAMETER ExcludeLogin
        Excludes specific Windows logins from validation checks. Use this to skip service accounts or known system logins that you don't need to audit.
        Accepts wildcards and multiple values. Common exclusions include application service accounts and break-glass emergency accounts.

    .PARAMETER FilterBy
        Limits validation to either individual user accounts or Active Directory groups. Use 'LoginsOnly' when auditing user access or 'GroupsOnly' when reviewing group-based permissions.
        Default of 'None' validates both types. GroupsOnly is useful for reviewing role-based access control implementation.

    .PARAMETER IgnoreDomains
        Excludes logins from specific Active Directory domains from validation. Use this in multi-domain environments to focus on specific domains or skip legacy/untrusted domains.
        Helpful when you have old domain trusts or want to audit only production domains while excluding development or test domains.

    .PARAMETER InputObject
        Accepts login objects from Get-DbaLogin for targeted validation. Use this when you want to validate a specific subset of logins already retrieved by another command.
        Enables powerful filtering scenarios by piping pre-filtered login objects instead of processing all Windows logins on the server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com | Chrissy LeMaire (@cl)

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

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance Dev01 -Login DOMAIN\User | Test-DbaWindowsLogin

        Tests only the login returned by Get-DbaLogin

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [ValidateSet("LoginsOnly", "GroupsOnly", "None")]
        [string]$FilterBy = "None",
        [string[]]$IgnoreDomains,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
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

        $allWindowsLoginsGroups = @( )
    }
    process {
        if (-not (Test-Bound SqlInstance, InputObject -Max 1)) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $allWindowsLoginsGroups += $server.Logins | Where-Object { $_.LoginType -in ('WindowsUser', 'WindowsGroup') }
        }

        if ($InputObject) {
            $allWindowsLoginsGroups += $InputObject
        }
    }
    end {
        # we cannot validate local users
        $allWindowsLoginsGroups = $allWindowsLoginsGroups | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name.StartsWith($_.Parent.ComputerName) -eq $false -and $_.Name.StartsWith("BUILTIN") -eq $false }
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
        foreach ($winLogin in $windowsLogins) {
            $adLogin = $winLogin.Name
            $loginSid = $winLogin.Sid -join ''
            $domain, $username = $adLogin.Split("\")
            if ($domain.ToUpper() -in $IgnoreDomainsNormalized) {
                Write-Message -Message "Skipping Login $adLogin." -Level Verbose
                continue
            }
            Write-Message -Message "Parsing Login $adLogin." -Level Verbose
            $exists = $false
            $samAccountNameMismatch = $false
            try {
                $loginBinary = [byte[]]$winLogin.Sid
                $SID = New-Object Security.Principal.SecurityIdentifier($loginBinary, 0)
                $SIDForAD = $SID.Value
                Write-Message -Message "SID for AD is $SIDForAD" -Level Debug
                $u = Get-DbaADObject -ADObject "$domain\$SIDForAD" -Type User -IdentityType Sid -EnableException
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
                if ($u.SamAccountName -ne $username) {
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin." -Level Warning
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin (MSSQL: $username, AD: $($u.SamAccountName))." -Level Debug
                    $samAccountNameMismatch = $true
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
                Server                            = $winLogin.Parent.DomainInstanceName
                Domain                            = $domain
                Login                             = $username
                Type                              = $adType
                Found                             = $exists
                SamAccountNameMismatch            = $samAccountNameMismatch
                DisabledInSQLServer               = $winLogin.IsDisabled
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

        foreach ($winLogin in $windowsGroups) {
            $adLogin = $winLogin.Name
            $loginSid = $winLogin.Sid -join ''
            $domain, $groupName = $adLogin.Split("\")
            if ($domain.ToUpper() -in $IgnoreDomainsNormalized) {
                Write-Message -Message "Skipping Login $adLogin." -Level Verbose
                continue
            }
            Write-Message -Message "Parsing Login $adLogin on $($_.Parent)." -Level Verbose
            $exists = $false
            $samAccountNameMismatch = $false
            try {
                $loginBinary = [byte[]]$winLogin.Sid
                $SID = New-Object Security.Principal.SecurityIdentifier($loginBinary, 0)
                $SIDForAD = $SID.Value
                Write-Message -Message "SID for AD is $SIDForAD" -Level Debug
                $u = Get-DbaADObject -ADObject "$domain\$SIDForAD" -Type Group -IdentityType Sid -EnableException
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
                if ($u.SamAccountName -ne $groupName) {
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin." -Level Warning
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin (MSSQL: $groupName, AD: $($u.SamAccountName))." -Level Debug
                    $samAccountNameMismatch = $true
                }
            } catch {
                Write-Message -Message "AD Searcher Error for $groupName on $($_.Parent)" -Level Warning
            }
            $rtn = [PSCustomObject]@{
                Server                            = $winLogin.Parent.DomainInstanceName
                Domain                            = $domain
                Login                             = $groupName
                Type                              = "Group"
                Found                             = $exists
                SamAccountNameMismatch            = $samAccountNameMismatch
                DisabledInSQLServer               = $winLogin.IsDisabled
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