function Set-DbaLogin {
    <#
    .SYNOPSIS
        Set-DbaLogin makes it possible to make changes to one or more logins.

    .DESCRIPTION
        Set-DbaLogin will enable you to change the password, unlock, rename, disable or enable, deny or grant login privileges to the login. It's also possible to add or remove server roles from the login.

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
        Switch to unlock an account. This will only be used in conjunction with the -SecurePassword parameter.
        The default is false.

    .PARAMETER MustChange
        Does the user need to change his/her password. This will only be used in conjunction with the -SecurePassword parameter.
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
        Should the password policy be enforced.

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
        PS C:\> $SecurePassword = ConvertTo-SecureString "PlainTextPassword" -AsPlainText -Force
        PS C:\> $cred = New-Object System.Management.Automation.PSCredential ("username", $SecurePassword)
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -SecurePassword $cred -Unlock -MustChange

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
        [switch]$MustChange,
        [string]$NewName,
        [switch]$Disable,
        [switch]$Enable,
        [switch]$DenyLogin,
        [switch]$GrantLogin,
        [switch]$PasswordPolicyEnforced,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$AddRole,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$RemoveRole,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
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
    }

    process {
        if (Test-FunctionInterrupt) { return }

        $allLogins = @{ }
        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $allLogins[$instance.ToString()] = Get-DbaLogin -SqlInstance $server
            $InputObject += $allLogins[$instance.ToString()] | Where-Object { ($_.Name -in $Login) -and ($_.IsSystemObject -eq $false) -and ($_.Name -notlike '##*') }
        }

        # Loop through all the logins
        foreach ($l in $InputObject) {
            if ($Pscmdlet.ShouldProcess($l, "Setting Changes to Login on $($server.name)")) {
                $server = $l.Parent

                # Create the notes
                $notes = @()

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

                # Change the password
                if (Test-bound -ParameterName 'SecurePassword') {
                    try {
                        $l.ChangePassword($NewSecurePassword, $Unlock, $MustChange)
                        $passwordChanged = $true
                    } catch {
                        $notes += "Couldn't change password"
                        $passwordChanged = $false
                        Stop-Function -Message "Something went wrong changing the password for $l" -Target $l -ErrorRecord $_ -Continue
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

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'LoginName', 'DenyLogin', 'IsDisabled', 'IsLocked',
                'PasswordPolicyEnforced', 'MustChangePassword', 'PasswordChanged', 'ServerRole', 'Notes'

                Select-DefaultView -InputObject $l -Property $defaults
            }
        }
    }
}