function Invoke-DbaAdvancedInstall {
    <#
    .SYNOPSIS
        Designed for internal use, implements parallel execution for Install-DbaInstance.

    .DESCRIPTION
        Invokes an install process for a single computer and restarts it if needed

    .PARAMETER ComputerName
        Target computer with SQL instance or instances.

    .PARAMETER Port
        After successful installation, changes SQL Server TCP port to this value. Overrides the port specified in -SqlInstance.

    .PARAMETER InstallationPath
        Path to setup.exe

    .PARAMETER ConfigurationPath
        Path to Configuration.ini on a local machine

    .PARAMETER ArgumentList
        Array of command line arguments for setup.exe

    .PARAMETER Version
        Canonic version of SQL Server, e.g. 10.50, 11.0

    .PARAMETER InstanceName
        Instance name to be used for the installation

    .PARAMETER Configuration
        A hashtable with custom configuration items that you want to use during the installation.
        Overrides all other parameters.
        For example, to define a custom server collation you can use the following parameter:
        PS> Install-DbaInstance -Version 2017 -Configuration @{ SQLCOLLATION = 'Latin1_General_BIN' }

        Full list of parameters can be found here: https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt#Install

    .PARAMETER Restart
        Restart computer automatically after a successful installation of Sql Server and wait until it comes back online.
        Using this parameter is the only way to chain-install more than 1 instance, since every single patch will require a restart of said computer.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if installation media is located on a network folder.

    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        If the protocol fails to establish a connection

        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host
          to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.

    .PARAMETER PerformVolumeMaintenanceTasks
        Allow SQL Server service account to perform Volume Maintenance tasks.

    .PARAMETER SaveConfiguration
        Save installation configuration file in a custom location. Will not be preserved otherwise.

    .PARAMETER SaCredential
        Securely provide the password for the sa account when using mixed mode authentication.

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
        [pscredential]$Credential,
        [pscredential]$SaCredential,
        [switch]$EnableException
    )
    Function Get-SqlInstallSummary {
        # Reads Summary.txt from the SQL Server Installation Log folder
        Param (
            [DbaInstanceParameter]$ComputerName,
            [pscredential]$Credential,
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
                ConfigurationFile = $null
            }
            if (Test-Path $summaryPath) {
                $output.Path = $summaryPath
                $output.Content = Get-Content -Path $summaryPath | Select-String "Exit Message"
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
    $output = [pscustomobject]@{
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
    }
    $activity = "Installing SQL Server ($Version) components on $ComputerName"
    try {
        $restartNeeded = Test-PendingReboot -ComputerName $ComputerName -Credential $Credential
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
            Stop-Function -Message "Failed to restart computer" -ErrorRecord $_
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
            $output.Log = $summary.Content
            $output.LogFile = $summary.Path
            $output.ConfigurationFile = $summary.ConfigurationFile
        } catch {
            Write-Message -Level Warning -Message "Could not get the contents of the summary file from $($ComputerName). 'Log' property will be empty" -ErrorRecord $_
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
        $msg = "Installation failed with exit code $($installResult.ExitCode). Expand 'Log' property to find more details."
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
        $restartNeeded = Test-PendingReboot -ComputerName $ComputerName -Credential $Credential
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
                Stop-Function -Message "Failed to restart computer $($ComputerName)" -ErrorRecord $_ -FunctionName Install-DbaInstance
                return $output
            }
        } else {
            $output.Notes += "Restart is required for computer $($ComputerName) to finish the installation of Sql Server version $Version"
        }
    }
    $output | Select-DefaultView -Property ComputerName, InstanceName, Version, Port, Successful, Restarted, Installer, ExitCode, LogFile, Notes
    Write-Progress -Activity $activity -Completed
}
