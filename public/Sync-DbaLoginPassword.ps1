function Sync-DbaLoginPassword {
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
                $destLoginName = ($allDestLogins | Where-Object Name -eq $loginName).Name
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
                if ($sourceLoginPwdHash -eq $destLoginPwdHash) {
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