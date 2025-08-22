function Set-DbaLogin {
    <#
    .SYNOPSIS
        Modifies SQL Server login properties including passwords, permissions, roles, and account status

    .DESCRIPTION
        Manages SQL Server login accounts by modifying passwords, account status, security settings, and server role memberships in a single operation. Handles common DBA tasks like unlocking accounts, resetting passwords with force-change requirements, and applying password policies for security compliance. Includes a special unlock feature that preserves existing passwords by temporarily disabling policy checks, eliminating the need to reset passwords when unlocking accounts. Works across multiple instances and logins simultaneously, making it ideal for bulk user management and security maintenance workflows.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        The login that needs to be changed

    .PARAMETER SecurePassword
        The new password for the login This can be either a credential or a secure string.

    .PARAMETER DefaultDatabase
        Default database for the login

    .PARAMETER Unlock
        Switch to unlock an account. This can be used in conjunction with the -SecurePassword or -Force parameters.
        The default is false.

    .PARAMETER PasswordMustChange
        Does the user need to change his/her password. This will only be used in conjunction with the -SecurePassword parameter.
        It is required that the login have both PasswordPolicyEnforced (check_policy) and PasswordExpirationEnabled (check_expiration) enabled for the login. See the Microsoft documentation for ALTER LOGIN for more details.
        The default is false.

    .PARAMETER NewName
        The new name for the login.

    .PARAMETER Disable
        Disable the login

    .PARAMETER Enable
        Enable the login

    .PARAMETER DenyLogin
        Deny access to SQL Server

    .PARAMETER GrantLogin
        Grant access to SQL Server

    .PARAMETER PasswordPolicyEnforced
        Enable the password policy on the login (check_policy = ON). This option must be enabled in order for -PasswordExpirationEnabled to be used.

    .PARAMETER PasswordExpirationEnabled
        Enable the password expiration check on the login (check_expiration = ON). In order to enable this option the PasswordPolicyEnforced (check_policy) must also be enabled for the login.

    .PARAMETER AddRole
        Add one or more server roles to the login
        The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER RemoveRole
        Remove one or more server roles to the login
        The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER InputObject
        Allows logins to be piped in from Get-DbaLogin

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        This switch is used with -Unlock to unlock a login without providing a password. This command will temporarily disable and enable the policy settings as described at https://www.mssqltips.com/sqlservertip/2758/how-to-unlock-a-sql-login-without-resetting-the-password/.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaLogin

    .EXAMPLE
        PS C:\> $SecurePassword = (Get-Credential NoUsernameNeeded).Password
        PS C:\> $cred = New-Object System.Management.Automation.PSCredential ("username", $SecurePassword)
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -SecurePassword $cred -Unlock -PasswordMustChange

        Set the new password for login1 using a credential, unlock the account and set the option
        that the user must change password at next logon.

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -Enable

        Enable the login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1, login2, login3, login4 -Enable

        Enable multiple logins

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1, sql2, sql3 -Login login1, login2, login3, login4 -Enable

        Enable multiple logins on multiple instances

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -Disable

        Disable the login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -DenyLogin

        Deny the login to connect to the instance

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -GrantLogin

        Grant the login to connect to the instance

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -PasswordPolicyEnforced

        Enforces the password policy on a login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -PasswordPolicyEnforced:$false

        Disables enforcement of the password policy on a login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login test -AddRole serveradmin

        Add the server role "serveradmin" to the login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login test -RemoveRole bulkadmin

        Remove the server role "bulkadmin" to the login

    .EXAMPLE
        PS C:\> $login = Get-DbaLogin -SqlInstance sql1 -Login test
        PS C:\> $login | Set-DbaLogin -Disable

        Disable the login from the pipeline

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -DefaultDatabase master

        Set the default database to master on a login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -Unlock -Force

        Unlocks the login1 on the sql1 instance using the technique described at https://www.mssqltips.com/sqlservertip/2758/how-to-unlock-a-sql-login-without-resetting-the-password/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter Password")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [Alias("Password")]
        [object]$SecurePassword, #object so that it can accept credential or securestring
        [Alias("DefaultDB")]
        [string]$DefaultDatabase,
        [switch]$Unlock,
        [Alias("MustChange")]
        [switch]$PasswordMustChange,
        [string]$NewName,
        [switch]$Disable,
        [switch]$Enable,
        [switch]$DenyLogin,
        [switch]$GrantLogin,
        [switch]$PasswordPolicyEnforced,
        [switch]$PasswordExpirationEnabled,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$AddRole,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$RemoveRole,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        # Check the parameters
        if ((Test-Bound -ParameterName 'SqlInstance') -and (Test-Bound -ParameterName 'Login' -Not)) {
            Stop-Function -Message 'You must specify a Login when using SqlInstance'
        }

        if ((Test-Bound -ParameterName 'NewName') -and $Login -eq $NewName) {
            Stop-Function -Message 'Login name is the same as the value in -NewName' -Target $Login -Continue
        }

        if ((Test-Bound -ParameterName 'Disable') -and (Test-Bound -ParameterName 'Enable')) {
            Stop-Function -Message 'You cannot use both -Enable and -Disable together' -Target $Login -Continue
        }

        if ((Test-Bound -ParameterName 'GrantLogin') -and (Test-Bound -ParameterName 'DenyLogin')) {
            Stop-Function -Message 'You cannot use both -GrantLogin and -DenyLogin together' -Target $Login -Continue
        }

        if (Test-bound -ParameterName 'SecurePassword') {
            switch ($SecurePassword.GetType().Name) {
                'PSCredential' { $NewSecurePassword = $SecurePassword.Password }
                'SecureString' { $NewSecurePassword = $SecurePassword }
                default {
                    Stop-Function -Message 'Password must be a PSCredential or SecureString' -Target $Login
                }
            }
        }

        if ((Test-Bound Unlock) -and (Test-Bound SecurePassword -Not) -and (Test-Bound Force -Not)) {
            Stop-Function -Message 'You must specify a password when using the -Unlock parameter or use the -Force parameter. See the help documentation for this command.'
        }

        if ((Test-Bound PasswordMustChange) -and (Test-Bound SecurePassword -Not)) {
            Stop-Function -Message 'You must specify a password when using the -PasswordMustChange parameter. See the command help for more details.'
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        $allLogins = @{ }
        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $allLogins[$instance.ToString()] = Get-DbaLogin -SqlInstance $server
            $InputObject += $allLogins[$instance.ToString()] | Where-Object { ($_.Name -in $Login) -and ($_.Name -notlike '##*') }
        }

        # Loop through all the logins
        foreach ($l in $InputObject) {
            if ($Pscmdlet.ShouldProcess($l, "Setting Changes to Login on $($l.Parent.Name)")) {
                $server = $l.Parent

                # Create the notes
                $notes = @()

                # caller wants to unlock a login without a password and has specified the -Force param
                if ((Test-Bound Unlock) -and (Test-Bound SecurePassword -Not) -and (Test-Bound Force)) {
                    if (-not $l.IsLocked) {
                        Write-Message -Message "Login $l is not locked" -Level Warning
                    } else {
                        try {
                            # save the current state of the policy options for check_policy and check_expiration
                            $checkPolicy = $l.PasswordPolicyEnforced
                            $checkExpiration = $l.PasswordExpirationEnabled

                            # alter the login to switch off the check_policy and check_expiration. Ref: https://www.mssqltips.com/sqlservertip/2758/how-to-unlock-a-sql-login-without-resetting-the-password/
                            $l.PasswordPolicyEnforced = $false
                            $l.PasswordExpirationEnabled = $false
                            $l.Alter()

                            # restore the settings immediately
                            $l.PasswordPolicyEnforced = $checkPolicy
                            $l.PasswordExpirationEnabled = $checkExpiration
                            $l.Alter()

                            # out of an abundance of caution let's refresh the login and double check the settings to see if they match what they were before
                            $l.Refresh()

                            if ($checkPolicy -ne $l.PasswordPolicyEnforced) {
                                Stop-Function -Message "Unable to restore the check_policy setting for $l" -Target $l -Continue
                            }

                            if ($checkExpiration -ne $l.PasswordExpirationEnabled) {
                                Stop-Function -Message "Unable to restore the check_expiration setting for $l" -Target $l -Continue
                            }
                        } catch {
                            $notes += "Unable to unlock"
                            Stop-Function -Message "Unable to unlock $l. Review the 'Enforce password policy' and 'Enforce password expiration' settings for $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Change the name
                if (Test-Bound -ParameterName 'NewName') {
                    # Check if the new name doesn't already exist
                    if ($allLogins[$server.Name].Name -notcontains $NewName) {
                        try {
                            $l.Rename($NewName)
                        } catch {
                            $notes += "Couldn't rename login"
                            Stop-Function -Message "Something went wrong changing the name for $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    } else {
                        $notes += 'New login name already exists'
                        Write-Message -Message "New login name $NewName already exists on $instance" -Level Verbose
                    }
                }

                # Disable the login
                if (Test-Bound -ParameterName 'Disable') {
                    if ($l.IsDisabled) {
                        Write-Message -Message "Login $l is already disabled" -Level Verbose
                    } else {
                        try {
                            $l.Disable()
                        } catch {
                            $notes += "Couldn't disable login"
                            Stop-Function -Message "Something went wrong disabling $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Enable the login
                if (Test-Bound -ParameterName 'Enable') {
                    if (-not $l.IsDisabled) {
                        Write-Message -Message "Login $l is already enabled" -Level Verbose
                    } else {
                        try {
                            $l.Enable()
                        } catch {
                            $notes += "Couldn't enable login"
                            Stop-Function -Message "Something went wrong enabling $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Deny access
                if (Test-Bound -ParameterName 'DenyLogin') {
                    if ($l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access denied" -Level Verbose
                    } else {
                        $l.DenyWindowsLogin = $true
                    }
                }

                # Grant access
                if (Test-Bound -ParameterName 'GrantLogin') {
                    if (-not $l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access granted" -Level Verbose
                    } else {
                        $l.DenyWindowsLogin = $false
                    }
                }

                # Enforce password policy
                if (Test-Bound -ParameterName 'PasswordPolicyEnforced') {
                    if ($l.PasswordPolicyEnforced -eq $PasswordPolicyEnforced) {
                        Write-Message -Message "Login $l password policy is already set to $($l.PasswordPolicyEnforced)" -Level Verbose
                    } else {
                        $l.PasswordPolicyEnforced = $PasswordPolicyEnforced
                    }
                }

                # Enforce password expiration
                if (Test-Bound -ParameterName 'PasswordExpirationEnabled') {

                    if ($PasswordExpirationEnabled -and $l.PasswordPolicyEnforced -eq $false) {
                        $notes += "Couldn't set check_expiration = ON because check_policy = OFF for $l. See the command description for more details on these settings."
                        Stop-Function -Message "Couldn't set check_expiration = ON because check_policy = OFF for $l. See the command description for more details on these settings." -Target $l -Continue
                    }

                    if ($l.PasswordExpirationEnabled -eq $PasswordExpirationEnabled) {
                        Write-Message -Message "Login $l password expiration check is already set to $($l.PasswordExpirationEnabled)" -Level Verbose
                    } else {
                        $l.PasswordExpirationEnabled = $PasswordExpirationEnabled
                    }
                }

                # Add server roles to login
                if ($AddRole) {
                    # Loop through each of the roles
                    foreach ($role in $AddRole) {
                        try {
                            $l.AddToRole($role)
                        } catch {
                            $notes += "Couldn't add role $role"
                            Stop-Function -Message "Something went wrong adding role $role to $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Remove server roles from login
                if ($RemoveRole) {
                    # Loop through each of the roles
                    foreach ($role in $RemoveRole) {
                        try {
                            $server.Roles[$role].DropMember($l.Name)
                        } catch {
                            $notes += "Couldn't remove role $role"
                            Stop-Function -Message "Something went wrong removing role $role to $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Set the default database
                if (Test-Bound -ParameterName 'DefaultDatabase') {
                    if ($l.DefaultDatabase -eq $DefaultDatabase) {
                        Write-Message -Message "Login $l default database is already set to $($l.DefaultDatabase)" -Level Verbose
                    } else {
                        $l.DefaultDatabase = $DefaultDatabase
                    }
                }

                # Alter the login to make the changes
                $l.Alter()
                $l.Refresh()

                # Change the password after the Alter() because the must_change requires the policy settings to be enabled first.
                if (Test-bound -ParameterName 'SecurePassword') {
                    if (Test-Bound PasswordMustChange) {
                        # Validate if the check_policy and check_expiration options are enabled on the login. These are required for the must_change option for alter login.
                        if ((-not $l.PasswordPolicyEnforced) -or (-not $l.PasswordExpirationEnabled)) {
                            Stop-Function -Message "Unable to change the password and set the must_change option for $l because check_policy = $($l.PasswordPolicyEnforced) and check_expiration = $($l.PasswordExpirationEnabled). See the command help for additional information on the -MustChange parameter." -Target $l -Continue
                        }
                    }

                    try {
                        $l.ChangePassword($NewSecurePassword, $Unlock, $PasswordMustChange)
                        $passwordChanged = $true

                        if (Test-Bound PasswordMustChange) {
                            $l.Refresh()  # necessary so that the read only property PasswordMustChange is updated
                        }
                    } catch {
                        $notes += "Couldn't change password"
                        $passwordChanged = $false
                        Stop-Function -Message "Something went wrong changing the password for $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }

                # Retrieve the server roles for the login
                $roles = Get-DbaServerRoleMember -SqlInstance $server | Where-Object { $_.Name -eq $l.Name }

                # Check if there were any notes to include in the results
                if ($notes) {
                    $notes = $notes | Get-Unique
                    $notes = $notes -Join ';'
                } else {
                    $notes = $null
                }
                $rolenames = $roles.Role | Select-Object -Unique

                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name PasswordChanged -Value $passwordChanged
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name ServerRole -Value ($rolenames -join ', ')
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name Notes -Value $notes

                # backwards compatibility: LoginName, DenyLogin
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name LoginName -Value $l.Name
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name DenyLogin -Value $l.DenyWindowsLogin

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'DenyLogin', 'IsDisabled', 'IsLocked',
                'PasswordPolicyEnforced', 'PasswordExpirationEnabled', 'MustChangePassword', 'PasswordChanged', 'ServerRole', 'Notes'

                Select-DefaultView -InputObject $l -Property $defaults
            }
        }
    }
}