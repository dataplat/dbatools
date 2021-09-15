Function Invoke-DbaAdvancedUpdate {
    <#
    .SYNOPSIS
        Designed for internal use, implements parallel execution for Update-DbaInstance.

    .DESCRIPTION
        Invokes an update process for a single computer and restarts it if needed

    .PARAMETER ComputerName
        Target computer with SQL instance or instances.

    .PARAMETER Action
        An object containing the action plan

    .PARAMETER Restart
        Restart computer automatically after a successful installation of a patch and wait until it comes back online.
        Using this parameter is the only way to chain-install more than 1 patch on a computer, since every single patch will require a restart of said computer.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if update Repository is located on a network folder.

    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        If the protocol fails to establish a connection

        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host
          to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.

    .PARAMETER ExtractPath
        Lets you specify a location to extract the update file to on the system requiring the update. e.g. C:\temp

    .PARAMETER ArgumentList
        A list of extra arguments to pass to the execution file. Accepts one or more strings containing command line parameters.
        Example: ... -ArgumentList "/SkipRules=RebootRequiredCheck", "/Q"

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, Update
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaAdvancedUpdate

    .EXAMPLE
    PS C:\> Invoke-DbaAdvancedUpdate -ComputerName SQL1 -Action $actions

    Invokes update actions on SQL1 after restarting it.

    .EXAMPLE
    PS C:\> Invoke-DbaAdvancedUpdate -ComputerName SQL1 -Action $actions -ExtractPath C:\temp

    Extracts required files to the specific location "C:\temp". Invokes update actions on SQL1 after restarting it.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [string]$ComputerName,
        [object[]]$Action,
        [bool]$Restart,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Credssp',
        [pscredential]$Credential,
        [string]$ExtractPath,
        [string[]]$ArgumentList,
        [switch]$EnableException

    )
    $computer = $ComputerName
    $activity = "Updating SQL Server components on $computer"
    $restarted = $false
    $restartParams = @{
        ComputerName = $computer
        ErrorAction  = 'Stop'
        For          = 'WinRM'
        Wait         = $true
        Force        = $true
    }
    if ($Credential) {
        $restartParams.Credential = $Credential
    }
    try {
        $restartNeeded = Test-PendingReboot -ComputerName $computer -Credential $Credential
    } catch {
        $restartNeeded = $false
        Stop-Function -Message "Failed to get reboot status from $computer" -ErrorRecord $_
    }
    if ($restartNeeded -and $Restart) {
        # Restart the computer prior to doing anything
        Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Restarting computer $($computer) due to pending restart"
        Write-Message -Level Verbose "Restarting computer $($computer) due to pending restart"
        try {
            $null = Restart-Computer @restartParams
            $restarted = $true
        } catch {
            Stop-Function -Message "Failed to restart computer" -ErrorRecord $_
        }
    }
    Write-Message -Level Debug -Message "Processing $($computer) with $(($Actions | Measure-Object).Count) actions"
    #foreach action passed to the script for this particular computer
    foreach ($currentAction in $Action) {
        $output = $currentAction
        $output.Successful = $false
        $output.Restarted = $restarted
        ## Start the installation sequence
        Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Launching installation of $($currentAction.TargetLevel) KB$($currentAction.KB) ($($currentAction.Installer)) for SQL$($currentAction.MajorVersion) ($($currentAction.Build))"
        $execParams = @{
            ComputerName   = $computer
            ErrorAction    = 'Stop'
            Authentication = $Authentication
        }
        if ($Credential) {
            $execParams.Credential = $Credential
        }

        if (!$ExtractPath) {
            # Find a temporary folder to extract to - the drive that has most free space
            try {
                $chosenDrive = (Get-DbaDiskSpace -ComputerName $computer -Credential $Credential -EnableException:$true | Sort-Object -Property Free -Descending | Select-Object -First 1).Name
                if (!$chosenDrive) {
                    # Fall back to the system drive
                    $chosenDrive = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { $env:SystemDrive } -Raw -ErrorAction Stop
                }
            } catch {
                $msg = "Failed to retrieve a disk drive to extract the update"
                $output.Notes += $msg
                Stop-Function -Message $msg -ErrorRecord $_
                return $output
            }
        } else {
            $chosenDrive = $ExtractPath
        }
        $spExtractPath = $chosenDrive.TrimEnd('\') + "\dbatools_KB$($currentAction.KB)_Extract_$([guid]::NewGuid().Guid.Replace('-',''))"
        $output.ExtractPath = $spExtractPath
        try {
            # Extract file
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Extracting $($currentAction.Installer) to $spExtractPath"
            Write-Message -Level Verbose -Message "Extracting $($currentAction.Installer) to $spExtractPath"
            $extractResult = Invoke-Program @execParams -Path $currentAction.Installer -ArgumentList @("/x`:`"$spExtractPath`"", "/quiet") -Fallback
            if (-not $extractResult.Successful) {
                $msg = "Extraction failed with exit code $($extractResult.ExitCode), try specifying a different location using -ExtractPath"
                $output.Notes += $msg
                Stop-Function -Message $msg
                return $output
            }
            # Install the patch
            if ($currentAction.InstanceName) {
                $instanceClause = "/instancename=$($currentAction.InstanceName)"
            } else {
                $instanceClause = '/allinstances'
            }
            if ($currentAction.Build -like "10.0.*") {
                $programArgumentList = $ArgumentList + @('/quiet', $instanceClause)
            } else {
                $programArgumentList = $ArgumentList + @('/quiet', $instanceClause, '/IAcceptSQLServerLicenseTerms')
            }
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Now installing update SQL$($currentAction.MajorVersion)$($currentAction.TargetLevel) from $spExtractPath"
            Write-Message -Level Verbose -Message "Starting installation from $spExtractPath"
            $updateResult = Invoke-Program @execParams -Path "$spExtractPath\setup.exe" -ArgumentList $programArgumentList -WorkingDirectory $spExtractPath -Fallback
            $output.ExitCode = $updateResult.ExitCode
            if ($updateResult.Successful) {
                $output.Successful = $true
            } else {
                $msg = "Update failed with exit code $($updateResult.ExitCode)"
                $output.Notes += $msg
                Stop-Function -Message $msg
                return $output
            }
            $output.Log = $updateResult.stdout
        } catch {
            Stop-Function -Message "Upgrade failed" -ErrorRecord $_
            $output.Notes += $_.Exception.Message
            return $output
        } finally {
            ## Cleanup temp
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Cleaning up extracted files from $spExtractPath"
            try {
                Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Removing temporary files"
                $null = Invoke-CommandWithFallBack @execParams -ScriptBlock {
                    if ($args[0] -like '*\dbatools_KB*_Extract*' -and (Test-Path $args[0])) {
                        Remove-Item -Recurse -Force -LiteralPath $args[0] -ErrorAction Stop
                    }
                } -Raw -ArgumentList $spExtractPath
            } catch {
                $message = "Failed to cleanup temp folder on computer $($computer)`: $($_.Exception.Message)"
                Write-Message -Level Verbose -Message $message
                $output.Notes += $message
            }
        }
        #double check if restart is needed
        try {
            $restartNeeded = Test-PendingReboot -ComputerName $computer -Credential $Credential
        } catch {
            $restartNeeded = $false
            Stop-Function -Message "Failed to get reboot status from $computer" -ErrorRecord $_
        }
        if ($updateResult.ExitCode -eq 3010 -or $restartNeeded) {
            if ($Restart) {
                # Restart the computer
                Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Restarting computer $($computer) and waiting for it to come back online"
                Write-Message -Level Verbose "Restarting computer $($computer) and waiting for it to come back online"
                try {
                    $null = Restart-Computer @restartParams
                    $output.Restarted = $true
                } catch {
                    Stop-Function -Message "Failed to restart computer" -ErrorRecord $_
                    return $output
                }
            } else {
                $output.Notes += "Restart is required for computer $($computer) to finish the installation of SQL$($currentAction.MajorVersion)$($currentAction.TargetLevel)"
            }
        }
        $output
        Write-Progress -Activity $activity -Completed
    }
}