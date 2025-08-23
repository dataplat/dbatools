Function Invoke-DbaAdvancedUpdate {
    <#
    .SYNOPSIS
        Installs SQL Server updates and patches on remote computers with automatic restart management

    .DESCRIPTION
        Executes SQL Server KB updates on a target computer by extracting patch files, running setup.exe with appropriate parameters, and managing system restarts as needed. This function handles the core installation logic for Update-DbaInstance, processing update actions for specific SQL Server instances or all instances on a machine. It automatically detects the drive with most free space for extraction, validates pending reboots, and coordinates restart sequences to ensure patches install successfully across multiple update cycles.

    .PARAMETER ComputerName
        Specifies the remote computer where SQL Server updates will be installed.
        This function handles the actual installation process after Update-DbaInstance creates the action plan.
        Must have WinRM enabled and accessible for remote operations including file extraction and system restarts.

    .PARAMETER Action
        Contains the update action plan objects created by Update-DbaInstance with details for each KB to install.
        Each action includes properties like TargetLevel, KB number, Installer path, MajorVersion, Build, and InstanceName.
        Multiple actions can be processed sequentially to chain-install several updates with automatic restarts between each.

    .PARAMETER Restart
        Automatically restarts the target computer after successful patch installation and waits for it to come back online.
        Required for installing multiple patches in sequence, as each SQL Server update typically requires a system restart to complete.
        Also handles pre-installation restarts when pending reboots are detected before beginning the update process.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if update Repository is located on a network folder.

    .PARAMETER Authentication
        Specifies the WinRM authentication protocol for remote connections to the target computer.
        Defaults to CredSSP when credentials are provided to handle network share access and avoid double-hop authentication issues.
        Use Default authentication only for local operations, as network-based update repositories require credential delegation.

    .PARAMETER ExtractPath
        Specifies the directory path where update files will be extracted on the target computer.
        If not specified, automatically selects the drive with the most free space for extraction.
        Use this when you need to control extraction location for space management or security requirements.

    .PARAMETER ArgumentList
        Additional command-line arguments passed to the SQL Server setup.exe during installation.
        Commonly used for setup customization like "/SkipRules=RebootRequiredCheck" to bypass reboot validation or "/Q" for quiet mode.
        Arguments are automatically combined with required parameters like /quiet, /allinstances or /instancename, and /IAcceptSQLServerLicenseTerms.

    .PARAMETER NoPendingRenameCheck
        Skips the pending file rename check when determining if a system restart is required before installation.
        Use this when the pending rename detection produces false positives that prevent updates from proceeding.
        The function will still check other restart conditions like registry entries and exit codes from previous installations.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Install, Patching, Update
        Author: Kirill Kravtsov (@nvarscar)

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
        [PSCredential]$Credential,
        [string]$ExtractPath,
        [string[]]$ArgumentList,
        [switch]$NoPendingRenameCheck,
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
        $restartParams.WsmanAuthentication = $Authentication
    }
    try {
        $restartNeeded = Test-PendingReboot -ComputerName $computer -Credential $Credential -NoPendingRename:$NoPendingRenameCheck
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
            Stop-Function -Message "Failed to restart computer $($computer)" -ErrorRecord $_
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
            $restartNeeded = Test-PendingReboot -ComputerName $computer -Credential $Credential -NoPendingRename:$NoPendingRenameCheck
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
                    Stop-Function -Message "Failed to restart computer $($computer)" -ErrorRecord $_
                    $output.Notes += "Restart is required for computer $($computer) to finish the installation of SQL$($currentAction.MajorVersion)$($currentAction.TargetLevel)"
                }
            } else {
                $output.Notes += "Restart is required for computer $($computer) to finish the installation of SQL$($currentAction.MajorVersion)$($currentAction.TargetLevel)"
            }
        }
        $output
        Write-Progress -Activity $activity -Completed
    }
}