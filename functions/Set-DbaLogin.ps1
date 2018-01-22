function Set-DbaLogin {

    <#
    .SYNOPSIS
    Set-DbaLogin makes it possible to make changes to one or more logins.

    .DESCRIPTION
    Set-DbaLogin will enable you to change the password, unlock, rename, disable or enable, deny or grant login privileges to the login.
    It's also possible to add or remove server roles from the login.

    .PARAMETER SqlInstance
    SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
    Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
    $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
    To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Login
    The login that needs to be changed

    .PARAMETER Password
    The new password for the login This can be either a credential or a secure string.

    .PARAMETER Unlock
    Switch to unlock an account. This will only be used in conjunction with the -Password parameter.
    The default is false.

    .PARAMETER MustChange
    Does the user need to change his/her password. This will only be used in conjunction with the -Password parameter.
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

    .PARAMETER AddRole
    Add one or more server roles to the login
    The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER RemoveRole
    Remove one or more server roles to the login
    The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Original Author: Sander Stad (@sqlstad, sqlstad.nl)
    Tags: Login

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Set-DbaLogin

    .EXAMPLE
    $password = ConvertTo-SecureString "PlainTextPassword" -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("username", $password)
    Set-DbaLogin -SqlInstance sql1 -Login login1 -Password $cred -Unlock -MustChange

    Set the new password for login1 using a credential, unlock the account and set the option
    that the usermust change password at next logon.

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -Enable

    Enable the login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1, login2, login3, login4 -Enable

    Enable multiple logins

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1, sql2, sql3 -Login login1, login2, login3, login4 -Enable

    Enable multiple logins on multiple instances

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -Disable

    Disable the login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -DenyLogin

    Deny the login to connect to the instance

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -GrantLogin

    Grant the login to connect to the instance

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login test -AddRole serveradmin

    Add the server role "serveradmin" to the login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login test -RemoveRole bulkadmin

    Remove the server role "bulkadmin" to the login

#>

    [CmdletBinding()]

    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [string[]]$Login,
        [object]$Password,
        [switch]$Unlock,
        [switch]$MustChange,
        [string]$NewName,
        [switch]$Disable,
        [switch]$Enable,
        [switch]$DenyLogin,
        [switch]$GrantLogin,
        [ValidateSet("bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin")]
        [string[]]$AddRole,
        [ValidateSet("bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin")]
        [string[]]$RemoveRole,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        # Check the parameters
        if ($Login -eq $NewName) {
            Stop-Function -Message "Login name is the same as the value in -NewName" -Target $Login -Continue
        }

        if ($Disable -and $Enable) {
            Stop-Function -Message "You cannot use both -Enable and -Disable together" -Target $Login -Continue
        }

        if ($GrantLogin -and $DenyLogin) {
            Stop-Function -Message "You cannot use both -GrantLogin and -DenyLogin together" -Target $Login -Continue
        }

        # Check the password
        if ($Password) {
            switch ($Password.GetType().Name) {
                "PSCredential" { $newPassword = $Password.Password}
                "SecureString" { $newPassword = $Password}
            }
        }
        else {
        }

    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all the logins
            $allLogins = $server.Logins | Where-Object {($_.IsSystemObject -eq $false) -and ($_.Name -notlike '##*')}
            $logins = $server.Logins | Where-Object {$Login -contains $_.Name}

            # Loop through all the logins
            foreach ($l in $logins) {

                # Create the notes
                $notes = @()

                # Change the name
                if ($NewName) {
                    # Check if the new name doesn't already exist
                    if ($allLogins.Name -notcontains $NewName) {
                        try {
                            $l.Rename($NewName)
                        }
                        catch {
                            $notes += "Couldn't rename login"
                            Stop-Function -Message "Something went wrong changing the name for $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                    else {
                        $notes += "New login name already exists"
                        Write-Message -Message "New login name $NewName already exists on $instance" -Level Verbose
                    }
                }

                # Change the password
                if ($Password) {
                    try {
                        $l.ChangePassword($newPassword, $Unlock, $MustChange)
                        $passwordChanged = $true
                    }
                    catch {
                        $notes += "Couldn't change password"
                        $passwordChanged = $false
                        Stop-Function -Message "Something went wrong changing the password for $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }

                # Disable the login
                if ($Disable) {
                    if ($l.IsDisabled) {
                        Write-Message -Message "Login $l is already disabled" -Level Verbose
                    }
                    else {
                        try {
                            $l.Disable()
                        }
                        catch {
                            $notes += "Couldn't disable login"
                            Stop-Function -Message "Something went wrong disabling $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Enable the login
                if ($Enable) {
                    if (-not $l.IsDisabled) {
                        Write-Message -Message "Login $l is already enabled" -Level Verbose
                    }
                    else {
                        try {
                            $l.Enable()
                        }
                        catch {
                            $notes += "Couldn't enable login"
                            Stop-Function -Message "Something went wrong enabling $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Deny access
                if ($DenyLogin) {
                    if ($l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access denied" -Level Verbose
                    }
                    else {
                        $l.DenyWindowsLogin = $true
                    }
                }

                # Grant access
                if ($GrantLogin) {
                    if (-not $l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access granted" -Level Verbose
                    }
                    else {
                        $l.DenyWindowsLogin = $false
                    }
                }

                # Add server roles to login
                if ($AddRole) {
                    # Loop through each of the roles
                    foreach ($role in $AddRole) {
                        try {
                            $l.AddToRole($role)
                        }
                        catch {
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
                        }
                        catch {
                            $notes += "Couldn't remove role $role"
                            Stop-Function -Message "Something went wrong removing role $role to $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Alter the login to make the changes
                $l.Alter()

                # Retrieve the server roles for the login
                $roles = Get-DbaRoleMember -SqlInstance $instance -IncludeServerLevel | Where-Object {$null -eq $_.Database -and $_.Member -eq $l.Name}

                # Check if there were any notes to include in the results
                if ($notes) {
                    $notes = $notes | Get-Unique
                    $notes = $notes -Join ';'
                }
                else {
                    $notes = $null
                }

                # Return the results
                [PSCustomObject]@{
                    ComputerName       = $server.NetName
                    InstanceName       = $server.ServiceName
                    SqlInstance        = $server.DomainInstanceName
                    LoginName          = $l.Name
                    DenyLogin          = $l.DenyWindowsLogin
                    IsDisabled         = $l.IsDisabled
                    IsLocked           = $l.IsLocked
                    MustChangePassword = $l.MustChangePassword
                    PasswordChanged    = $passwordChanged
                    ServerRole         = $roles.Role -join ","
                    Notes              = $notes
                } | Select-DefaultView -ExcludeProperty Login

            } # end for each login

        } # end for each instance

    } # end process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished changing login(s)" -Level Verbose
    }


}