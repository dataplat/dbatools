function Sync-DbaLoginPassword {
    <#
    .SYNOPSIS
    Sync the password of a login between instances

    .DESCRIPTION
    Sync the password of a login(s) between instances using the password hash

    .PARAMETER Source
    Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
    Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

    Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

    For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
    Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
    Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

    For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
    The login(s) to process. Options for this list are auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
    The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER WhatIf
    If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
    If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Migration, Login
    Author: Shawn Melton, wsmelton.github.io

    Website: https://dbatools.io
    Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Sync-DbaLoginPassword

    .EXAMPLE
    Sync-DbaLoginPassword -Source sql201901 -Destination sql201902 -Login TestLogin1

    Synchronize the password hash for login TestLogin1 between each instance. If found matching it will not overwrite.

    .EXAMPLE
    Sync-DbaLoginPassword -Source sql201901 -Destination sql201902 -Login TestLogin1 -Force

    Synchronize the password hash for login TestLogin1 between each instance. If found matching it will overwrite.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [switch]$EnableException
    )
    process {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure on $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        $allSourceLogins = Get-DbaLogin -SqlInstance $sourceServer -Login $Login -ExcludeLogin $ExcludeLogin
        if ($null -eq $allSourceLogins) {
            Stop-Function -Message "No matching logins found for $($Login -join ', ') on $Source"
            return
        } else {
            try {
                <# Get the password hash for the login(s) provided #>
                $sourceLoginsPwdHash = Get-LoginPasswordHash -Server $sourceServer -Login $allSourceLogins.Name
            } catch {
                Stop-Function -Message "Issue pulling the password hash on $Source" -ErrorRecord $_ -Target Source
                return
            }
        }

        # Get current login to not sync the password for that login.
        $currentLogin = $sourceServer.ConnectionContext.TrueLogin

        <# process destinations #>
        foreach ($dest in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $dest -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure on $dest" -Category ConnectionError -ErrorRecord $_ -Target $dest -Continue
            }

            $allDestLogins = Get-DbaLogin -SqlInstance $destServer -Login $Login -ExcludeLogin $ExcludeLogin
            if ($null -eq $allDestLogins) {
                Stop-Function -Message "No matching logins found for $($Login -join ', ') on $Destination" -Continue
            } else {
                try {
                    <# Get the password hash for the login(s) on Dest #>
                    $destLoginsPwdHash = Get-LoginPasswordHash -Server $destServer -Login $allDestLogins.Name
                } catch {
                    Stop-Function -Message "Issue pulling the password hash on $Destination" -ErrorRecord $_ -Target Destination -Continue
                }
            }
            $stepCounter = 0
            foreach ($sourceLogin in $allSourceLogins) {
                $loginName = $sourceLogin.Name
                $sourceLoginPwdHash = $sourceLoginsPwdHash.$loginName
                $destLoginName = ($allDestLogins | Where-Object Name -EQ $loginName).Name
                $destLoginPwdHash = $destLoginsPwdHash.$loginName

                $syncLoginPasswordStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $loginName
                    Type              = 'Login Password Hash'
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime][datetime]::now
                }
                $selectProps = 'DateTime', 'SourceServer', 'DestinationServer', 'Name', 'Type', 'Status', 'Notes'

                if ($null -eq $destLoginName) {
                    Write-Message -Level Verbose -Message "Login '$loginName' not found on destination. Skipping."
                    $syncLoginPasswordStatus.Status = 'Skipped'
                    $syncLoginPasswordStatus.Notes = "Login '$loginName' not found on destination."
                    $syncLoginPasswordStatus | Select-DefaultView -Property $selectProps -TypeName MigrationObject
                    continue
                }

                if ($currentLogin -eq $loginName) {
                    Write-Message -Level Verbose -Message "Sync cannot process or modify the password of the current login '$loginName'. Skipping."
                    $syncLoginPasswordStatus.Status = 'Skipping'
                    $syncLoginPasswordStatus.Notes = "Sync cannot process or modify the password of the current login '$loginName'."
                    $syncLoginPasswordStatus | Select-DefaultView -Property $selectProps -TypeName MigrationObject
                    continue
                }

                # Here we don't need the FullComputerName, but only the machine name to compare to the host part of the login name. So ComputerName should be fine.
                $serverName = $sourceServer.ComputerName
                $userBase = ($loginName.Split("\")[0]).ToLowerInvariant()
                if ($serverName -eq $userBase -or $loginName.StartsWith("NT ")) {
                    Write-Message -Level Verbose -Message "Sync does not modify the permissions of host or system login '$loginName'. Skipping."
                    $syncLoginPasswordStatus.Status = 'Skipped'
                    $syncLoginPasswordStatus.Notes = "Sync does not modify the permissions of host or system login '$loginName'."
                    $syncLoginPasswordStatus | Select-DefaultView -Property $selectProps -TypeName MigrationObject
                    continue
                }

                Write-Message -Level Verbose -Message "Source hash for $loginName [$sourceLoginPwdHash]"
                Write-Message -Level Verbose -Message "Destination hash for $loginName [$destLoginPwdHash]"
                if ($sourceLoginPwdHash -eq $destLoginPwdHash -and (Test-Bound Force -Not)) {
                    Write-Message -Level Warning -Message "Password hash already matches for login '$loginName'. Skipping"
                    $syncLoginPasswordStatus.Status = 'Skipped'
                    $syncLoginPasswordStatus.Notes = "Password hash already matches for login '$loginName'."
                    $syncLoginPasswordStatus | Select-DefaultView -Property $selectProps -TypeName MigrationObject
                    continue
                } else {
                    Write-ProgressHelper -Activity "Executing Sync-DbaLoginPassword to sync the password from $sourceServer" -StepNumber ($stepCounter++) -Message "Updating the password hash for $loginName on $destServer" -TotalSteps $allSourceLogins.Count
                    if ($PSCmdlet.ShouldProcess($loginName, "Sync the password hash for login to $destServer")) {
                        try {
                            $setLoginParams = @{
                                SqlInstance  = $destServer
                                Login        = $destLoginName
                                PasswordHash = $sourceLoginPwdHash
                            }
                            Set-DbaLogin @setLoginParams
                            $syncLoginPasswordStatus.Status = "Successful"
                            $syncLoginPasswordStatus | Select-DefaultView -Property $selectProps -TypeName MigrationObject
                        } catch {
                            $syncLoginPasswordStatus.Status = "Failed"
                            $syncLoginPasswordStatus.Notes = (Get-ErrorMessage -Record $_)
                            $syncLoginPasswordStatus | Select-DefaultView -Property $selectProps -TypeName MigrationObject
                            Stop-Function -Message "Issue syncing the password for $loginName" -Target $loginName -ErrorRecord $_ -Continue
                        }
                    }
                }
            }
        }
    }
}