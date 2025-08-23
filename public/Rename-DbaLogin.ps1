function Rename-DbaLogin {
    <#
    .SYNOPSIS
        Renames SQL Server logins and optionally their associated database users

    .DESCRIPTION
        Renames SQL Server logins at the instance level, solving the common problem of needing to update login names after migrations, domain changes, or when improving naming conventions.

        When migrating logins between environments or standardizing naming conventions, manually updating login names and all their database user mappings is time-consuming and error-prone. This function handles both the login rename and optionally updates all associated database users in a single operation.

        By default, only the server-level login is renamed. Use the -Force parameter to also rename the corresponding database users across all databases where the login is mapped. If any database user rename fails, the function automatically rolls back the login name change to maintain consistency.

    .PARAMETER SqlInstance
        Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        Specifies the existing login name that you want to rename on the SQL Server instance.
        This must be an exact match for a login that currently exists on the server.

    .PARAMETER NewLogin
        Specifies the new name for the login after the rename operation.
        For Windows logins, the new name must resolve to the same SID as the original login to maintain security mappings.

    .PARAMETER Force
        Renames corresponding database users across all databases where the login is mapped.
        Without this parameter, only the server-level login is renamed, leaving database users unchanged. If any database user rename fails, the entire operation rolls back to maintain consistency.

    .PARAMETER Confirm
        Prompts to confirm actions

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login
        Author: Mitchell Hamann (@SirCaptainMitch)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Rename-DbaLogin

    .EXAMPLE
        PS C:\>Rename-DbaLogin -SqlInstance localhost -Login DbaToolsUser -NewLogin captain

        SQL Login Example

    .EXAMPLE
        PS C:\>Rename-DbaLogin -SqlInstance localhost -Login domain\oldname -NewLogin domain\newname

        Change the windowsuser login name.

    .EXAMPLE
        PS C:\>Rename-DbaLogin -SqlInstance localhost -Login dbatoolsuser -NewLogin captain -WhatIf

        WhatIf Example

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Login,
        [parameter(Mandatory)]
        [string]$NewLogin,
        [switch]$Force,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible
            $currentLogin = $server.Logins[$Login]

            if ( -not $currentLogin) {
                Stop-Function -Message "Login '$login' not found on $instance" -Target login -Continue
            }

            if ($Pscmdlet.ShouldProcess($SqlInstance, "Changing Login name from  [$Login] to [$NewLogin]")) {
                $output = @()
                try {
                    $dbMappings = $currentLogin.EnumDatabaseMappings()
                    $null = $currentLogin.Rename($NewLogin)
                    $output += [PSCustomObject]@{
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.ServiceName
                        SqlInstance   = $server.DomainInstanceName
                        Database      = $null
                        PreviousLogin = $Login
                        NewLogin      = $NewLogin
                        PreviousUser  = $null
                        NewUser       = $null
                        Status        = "Successful"
                    }
                } catch {
                    $dbMappings = $null
                    [PSCustomObject]@{
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.ServiceName
                        SqlInstance   = $server.DomainInstanceName
                        Database      = $null
                        PreviousLogin = $Login
                        NewLogin      = $NewLogin
                        PreviousUser  = $null
                        NewUser       = $null
                        Status        = "Failure"
                    }
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $login -Continue
                }
            }

            if ($Force) {
                foreach ($mapping in $dbMappings) {
                    $db = $databases | Where-Object Name -eq $mapping.DBName
                    $user = $db.Users[$Login]
                    if ($user) {
                        Write-Message -Level Verbose -Message "Starting update for $db"

                        if ($Pscmdlet.ShouldProcess($SqlInstance, "Changing database $db user $user from [$Login] to [$NewLogin]")) {
                            try {
                                $oldname = $user.name
                                $null = $user.Rename($NewLogin)
                                $output += [PSCustomObject]@{
                                    ComputerName  = $server.ComputerName
                                    InstanceName  = $server.ServiceName
                                    SqlInstance   = $server.DomainInstanceName
                                    Database      = $db.name
                                    PreviousLogin = $null
                                    NewLogin      = $null
                                    PreviousUser  = $oldname
                                    NewUser       = $NewLogin
                                    Status        = "Successful"
                                }
                            } catch {
                                Write-Message -Level Warning -Message "Rolling back update to login: $Login"
                                $null = $currentLogin.Rename($Login)

                                [PSCustomObject]@{
                                    ComputerName  = $server.ComputerName
                                    InstanceName  = $server.ServiceName
                                    SqlInstance   = $server.DomainInstanceName
                                    Database      = $db.name
                                    PreviousLogin = $null
                                    NewLogin      = $null
                                    PreviousUser  = $NewLogin
                                    NewUser       = $oldname
                                    Status        = "Failure to rename. Rolled back change."
                                }
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $NewLogin
                                return
                            }
                        }
                    }
                }
            }

            $output
        }
    }
}