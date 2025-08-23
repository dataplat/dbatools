function Invoke-DbaAdvancedInstall {
    <#
    .SYNOPSIS
        Executes SQL Server installation on a single computer with automated restart handling.

    .DESCRIPTION
        Performs the complete SQL Server installation workflow on a target computer, including pre and post-installation restart management. This internal function handles copying configuration files to remote machines, executing setup.exe with specified parameters, configuring TCP ports, enabling volume maintenance tasks, and managing required system restarts. It provides detailed installation logging and error reporting to track the success or failure of each installation attempt.

    .PARAMETER ComputerName
        Specifies the target computer where SQL Server will be installed.
        Can be a hostname, FQDN, or IP address for remote installations.

    .PARAMETER Port
        Sets the TCP port for the SQL Server instance after installation completes.
        Use this when you need a specific port for firewall rules or application connectivity requirements.
        The service will be automatically restarted to apply the new port setting.

    .PARAMETER InstallationPath
        Specifies the full path to the SQL Server setup.exe file.
        This should point to the setup.exe in your SQL Server installation media or extracted ISO.

    .PARAMETER ConfigurationPath
        Specifies the path to the SQL Server configuration file (Configuration.ini) on the local machine.
        This file contains all installation settings and will be copied to the target computer during remote installations.
        Generate this file using SQL Server Installation Center or create it manually with your desired settings.

    .PARAMETER ArgumentList
        Provides additional command-line arguments to pass directly to setup.exe.
        Use this for installation options not covered by other parameters, such as /IACCEPTSQLSERVERLICENSETERMS.
        These arguments supplement the configuration file settings.

    .PARAMETER Version
        Specifies the SQL Server version being installed using the canonical version number.
        Examples: 10.50 for SQL Server 2008 R2, 11.0 for SQL Server 2012, 13.0 for SQL Server 2016.
        This helps the function locate installation logs and perform version-specific operations.

    .PARAMETER InstanceName
        Specifies the name for the SQL Server instance being installed.
        Use 'MSSQLSERVER' for the default instance or provide a custom name for named instances.
        This parameter is used for post-installation configuration like port changes and service restarts.

    .PARAMETER Configuration
        A hashtable with custom configuration items that you want to use during the installation.
        Overrides all other parameters.
        For example, to define a custom server collation you can use the following parameter:
        PS> Install-DbaInstance -Version 2017 -Configuration @{ SQLCOLLATION = 'Latin1_General_BIN' }

        Full list of parameters can be found here: https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt#Install

    .PARAMETER Restart
        Automatically restarts the target computer when required by the SQL Server installation and waits for it to come back online.
        Essential for multi-instance installations since most SQL Server components require a restart to complete installation.
        Without this parameter, you must manually restart the computer when installation exit code 3010 is returned.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if installation media is located on a network folder.

    .PARAMETER Authentication
        Specifies the authentication protocol for PowerShell remoting to the target computer.
        CredSSP is used by default when credentials are provided to handle network share access during installation.
        Change to Kerberos or Negotiate if your environment restricts CredSSP usage.

    .PARAMETER PerformVolumeMaintenanceTasks
        Grants the SQL Server service account the 'Perform Volume Maintenance Tasks' privilege after installation.
        This enables instant file initialization, significantly improving database file creation and growth performance.
        Recommended for production environments where large databases are created or restored frequently.

    .PARAMETER SaveConfiguration
        Specifies a path where the installation configuration file will be saved for future reference.
        Use this to preserve your installation settings for documentation or to replicate the same configuration on other servers.
        The temporary configuration file is normally deleted after installation completes.

    .PARAMETER SaCredential
        Provides the sa account password when installing SQL Server with mixed mode authentication.
        Pass a PSCredential object with 'sa' as the username and your desired password.
        Required only when your configuration file specifies mixed mode authentication (SECURITYMODE=SQL).

    .PARAMETER NoPendingRenameCheck
        Skips the check for pending file rename operations when determining if a reboot is required.
        Use this switch if you encounter false positive reboot requirements due to pending renames that don't affect SQL Server installation.
        Only disable this check if you're certain no critical system files are waiting to be renamed.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Install, Patching
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Invoke-DbaAdvancedInstall

    .EXAMPLE
    PS C:\> Invoke-DbaAdvancedUpdate -ComputerName SQL1 -Action $actions

    Invokes update actions on SQL1 after restarting it.
    #>
    [CmdletBinding()]
    Param (
        [string]$ComputerName,
        [string]$InstanceName,
        [nullable[int]]$Port,
        [string]$InstallationPath,
        [string]$ConfigurationPath,
        [string[]]$ArgumentList,
        [version]$Version,
        [hashtable]$Configuration,
        [bool]$Restart,
        [bool]$PerformVolumeMaintenanceTasks,
        [string]$SaveConfiguration,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Credssp',
        [PSCredential]$Credential,
        [PSCredential]$SaCredential,
        [switch]$NoPendingRenameCheck,
        [switch]$EnableException
    )
    Function Get-SqlInstallSummary {
        # Reads Summary.txt from the SQL Server Installation Log folder
        Param (
            [DbaInstanceParameter]$ComputerName,
            [PSCredential]$Credential,
            [parameter(Mandatory)]
            [version]$Version
        )
        $getSummary = {
            Param (
                [parameter(Mandatory)]
                [version]$Version
            )
            $versionNumber = "$($Version.Major)$($Version.Minor)".Substring(0, 3)
            $rootPath = "$([System.Environment]::GetFolderPath("ProgramFiles"))\Microsoft SQL Server\$versionNumber\Setup Bootstrap\Log"
            $summaryPath = "$rootPath\Summary.txt"
            $output = [PSCustomObject]@{
                Path              = $null
                Content           = $null
                ExitMessage       = $null
                ConfigurationFile = $null
            }
            if (Test-Path $summaryPath) {
                $output.Path = $summaryPath
                $output.Content = Get-Content -Path $summaryPath
                $output.ExitMessage = ($output.Content | Select-String "Exit message").Line -replace '^ *Exit message: *', ''
                # get last folder created - that's our setup
                $lastLogFolder = Get-ChildItem -Path $rootPath -Directory | Sort-Object -Property Name -Descending | Select-Object -First 1 -ExpandProperty FullName
                if (Test-Path $lastLogFolder\ConfigurationFile.ini) {
                    $output.ConfigurationFile = "$lastLogFolder\ConfigurationFile.ini"
                }
                return $output
            }
        }
        $params = @{
            ComputerName = $ComputerName.ComputerName
            Credential   = $Credential
            ScriptBlock  = $getSummary
            ArgumentList = @($Version.ToString())
            ErrorAction  = 'Stop'
            Raw          = $true
        }
        return Invoke-Command2 @params
    }
    $isLocalHost = ([DbaInstanceParameter]$ComputerName).IsLocalHost
    $output = [PSCustomObject]@{
        ComputerName      = $ComputerName
        Version           = $Version
        SACredential      = $SaCredential
        Successful        = $false
        Restarted         = $false
        Configuration     = $Configuration
        InstanceName      = $InstanceName
        Installer         = $InstallationPath
        Port              = $Port
        Notes             = @()
        ExitCode          = $null
        ExitMessage       = $null
        Log               = $null
        LogFile           = $null
        ConfigurationFile = $null

    }
    $restartParams = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
        For          = 'WinRM'
        Wait         = $true
        Force        = $true
    }
    if ($Credential) {
        $restartParams.Credential = $Credential
        $restartParams.WsmanAuthentication = $Authentication
    }
    $activity = "Installing SQL Server ($Version) components on $ComputerName"
    try {
        $restartNeeded = Test-PendingReboot -ComputerName $ComputerName -Credential $Credential -NoPendingRename:$NoPendingRenameCheck
    } catch {
        $restartNeeded = $false
        Stop-Function -Message "Failed to get reboot status from $computer" -ErrorRecord $_
    }
    if ($restartNeeded -and $Restart) {
        # Restart the computer prior to doing anything
        $msgPending = "Restarting computer $($ComputerName) due to pending restart"
        Write-ProgressHelper -ExcludePercent -Activity $activity -Message $msgPending
        Write-Message -Level Verbose $msgPending
        try {
            $null = Restart-Computer @restartParams
            $output.Restarted = $true
        } catch {
            Stop-Function -Message "Failed to restart computer $($ComputerName)" -ErrorRecord $_
        }
    }
    # save config if needed
    if ($SaveConfiguration) {
        try {
            $null = Copy-Item $ConfigurationPath -Destination $SaveConfiguration -ErrorAction Stop
        } catch {
            $msg = "Could not save configuration file to $SaveConfiguration"
            Stop-Function -Message $msg -ErrorRecord $_
            $output.Notes += $msg
        }
    }
    $connectionParams = @{
        ComputerName = $ComputerName
        ErrorAction  = "Stop"
        UseSSL       = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false)
    }

    [nullable[int]]$WinRMPort = Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.Port' -Fallback $null
    if (($null -ne $WinRMPort) -and ($WinRMPort -gt 0)) {
        $connectionParams.Port = $WinRMPort
        Write-Message -Level Verbose -Message "Using Port: $($connectionParams.Port)"
    }

    if ($Credential) { $connectionParams.Credential = $Credential }
    # need to figure out where to store the config file
    if ($isLocalHost) {
        $remoteConfig = $ConfigurationPath
    } else {
        try {
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Copying configuration file to $ComputerName"
            $session = New-PSSession @connectionParams
            $chosenPath = Invoke-Command -Session $session -ScriptBlock { (Get-Item ([System.IO.Path]::GetTempPath())).FullName } -ErrorAction Stop
            $remoteConfig = Join-DbaPath $chosenPath.TrimEnd('\') (Split-Path $ConfigurationPath -Leaf)
            Write-Message -Level Verbose -Message "Copying $($ConfigurationPath) to remote machine into $chosenPath"
            $null = Send-File -Path $ConfigurationPath -Destination $chosenPath -Session $session -ErrorAction Stop
            $session | Remove-PSSession
        } catch {
            Stop-Function -Message "Failed to copy file $($ConfigurationPath) to $remoteConfig on $($ComputerName), exiting" -ErrorRecord $_
            return
        }
    }
    $installParams = $ArgumentList
    $installParams += "/CONFIGURATIONFILE=`"$remoteConfig`""
    Write-Message -Level Verbose -Message "Setup starting from $($InstallationPath)"
    $execParams = @{
        ComputerName   = $ComputerName
        ErrorAction    = 'Stop'
        Authentication = $Authentication
    }
    if ($Credential) {
        $execParams.Credential = $Credential
    } else {
        if (Test-Bound -Not Authentication) {
            # Use Default authentication instead of CredSSP when Authentication is not specified and Credential is null
            $execParams.Authentication = "Default"
        }
    }
    try {
        Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Installing SQL Server on $ComputerName from $InstallationPath"
        $installResult = Invoke-Program @execParams -Path $InstallationPath -ArgumentList $installParams -Fallback
        $output.ExitCode = $installResult.ExitCode
        # Get setup log summary contents
        try {
            $summary = Get-SqlInstallSummary -ComputerName $ComputerName -Credential $Credential -Version $Version
            $output.ExitMessage = $summary.ExitMessage
            $output.Log = $summary.Content
            $output.LogFile = $summary.Path
            $output.ConfigurationFile = $summary.ConfigurationFile
        } catch {
            Write-Message -Level Warning -Message "Could not get the contents of the summary file from $($ComputerName). Related properties will be empty" -ErrorRecord $_
        }
    } catch {
        Stop-Function -Message "Installation failed" -ErrorRecord $_
        $output.Notes += $_.Exception.Message
        return $output
    } finally {
        try {
            # Cleanup remote temp
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Cleaning up temporary files on $ComputerName"
            if (-not $isLocalHost) {
                $null = Invoke-Command2 @connectionParams -ScriptBlock {
                    if ($args[0] -like '*\Configuration_*.ini' -and (Test-Path $args[0])) {
                        Remove-Item -LiteralPath $args[0] -ErrorAction Stop
                    }
                } -Raw -ArgumentList $remoteConfig
            }
            # cleanup local temp config file
            Remove-Item $ConfigurationPath
        } catch {
            Stop-Function -Message "Temp cleanup failed" -ErrorRecord $_
        }
    }
    if ($installResult.Successful) {
        $output.Successful = $true
    } else {
        $msg = "Installation failed with exit code $($installResult.ExitCode). Expand 'ExitMessage' and 'Log' property to find more details."
        $output.Notes += $msg
        Stop-Function -Message $msg
        return $output
    }
    # perform volume maintenance tasks if requested
    if ($PerformVolumeMaintenanceTasks) {
        $null = Set-DbaPrivilege -ComputerName $ComputerName -Credential $Credential -Type IFI -EnableException:$EnableException
    }
    # change port after the installation
    if ($Port) {
        $null = Set-DbaTcpPort -SqlInstance "$($ComputerName)\$($InstanceName)" -Credential $Credential -Port $Port -EnableException:$EnableException -Confirm:$false
        try {
            $null = Restart-DbaService -ComputerName $ComputerName -InstanceName $InstanceName -Credential $Credential -Type Engine -Force -EnableException:$EnableException -Confirm:$false
        } catch {
            $output.Notes += "Port for $($ComputerName)\$($InstanceName) has been changed, but instance restart failed ($_). Restart of instance is necessary for the new settings to become effective."
        }

    }
    # restart if necessary
    try {
        $restartNeeded = Test-PendingReboot -ComputerName $ComputerName -Credential $Credential -NoPendingRename:$NoPendingRenameCheck
    } catch {
        $restartNeeded = $false
        Stop-Function -Message "Failed to get reboot status from $($ComputerName)" -ErrorRecord $_
    }
    if ($installResult.ExitCode -eq 3010 -or $restartNeeded) {
        if ($Restart) {
            # Restart the computer
            $restartMsg = "Restarting computer $($ComputerName) and waiting for it to come back online"
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message $restartMsg
            Write-Message -Level Verbose -Message $restartMsg
            try {
                $null = Restart-Computer @restartParams
                $output.Restarted = $true
            } catch {
                Stop-Function -Message "Failed to restart computer $($ComputerName)" -ErrorRecord $_
                $output.Notes += "Restart is required for computer $($ComputerName) to finish the installation of Sql Server version $Version"
            }
        } else {
            $output.Notes += "Restart is required for computer $($ComputerName) to finish the installation of Sql Server version $Version"
        }
    }
    $output | Select-DefaultView -Property ComputerName, InstanceName, Version, Port, Successful, Restarted, Installer, ExitCode, LogFile, Notes
    Write-Progress -Activity $activity -Completed
}