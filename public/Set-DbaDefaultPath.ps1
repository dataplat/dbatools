function Set-DbaDefaultPath {
    <#
    .SYNOPSIS
        Configures the default file paths for new databases and backups on SQL Server instances

    .DESCRIPTION
        Modifies the server-level default paths that SQL Server uses when creating new databases or performing backups without specifying explicit locations. This eliminates the need to manually specify file paths for routine database operations and ensures consistent placement of files across your environment.

        The function validates that the specified path is accessible to the SQL Server service account before making changes. When changing data or log paths, a SQL Server service restart is required for the changes to take effect. Backup path changes are immediate.

        To change the error log location, use Set-DbaStartupParameter

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Type
        Specifies which default path types to configure: Data (new database data files), Log (new database log files), or Backup (backup operations).
        Use Data and Log when standardizing database file locations across instances or moving files to faster storage.
        Backup path changes take effect immediately, while Data and Log changes require a SQL Server service restart.

    .PARAMETER Path
        The directory path where SQL Server will create new database files or backups by default.
        Must be a valid path accessible to the SQL Server service account with appropriate permissions.
        Use UNC paths for shared storage or local paths like C:\Data for dedicated storage volumes.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, Logs, Backup
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDefaultPath

    .EXAMPLE
        PS C:\> Set-DbaDefaultPath -SqlInstance sql01\sharepoint -Type Data, Backup -Path C:\mssql\sharepoint\data

        Sets the data and backup default paths on sql01\sharepoint to C:\mssql\sharepoint\data

    .EXAMPLE
        PS C:\> Set-DbaDefaultPath -SqlInstance sql01\sharepoint -Type Data, Log -Path C:\mssql\sharepoint\data -WhatIf

        Shows what what happen if the command would have run
    #>
    [cmdletbinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('Data', 'Backup', 'Log')]
        [string[]]$Type,
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Path,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $Path = $Path.Trim().TrimEnd("\")

            if (-not (Test-DbaPath -SqlInstance $server -Path $Path)) {
                Stop-Function -Message "Path $Path is not accessible on $($server.Name)" -Target $instance -Continue
            }

            if ($Type -contains "Data") {
                if ($Pscmdlet.ShouldProcess($server.Name, "Changing DefaultFile to $Path")) {
                    $server.DefaultFile = $Path
                }
            }

            if ($Type -contains "Log") {
                if ($Pscmdlet.ShouldProcess($server.Name, "Changing DefaultLog to $Path")) {
                    $server.DefaultLog = $Path
                }
            }

            if ($Type -contains "Backup") {
                if ($Pscmdlet.ShouldProcess($server.Name, "Changing BackupDirectory to $Path")) {
                    $server.BackupDirectory = $Path
                }
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Committing changes")) {
                try {
                    $server.Alter()
                    if ($Type -contains "Data" -or $Type -contains "Log") {
                        Write-Message -Level Warning -Message "You must restart the SQL Service on $instance for changes to take effect"
                    }
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Data         = $server.DefaultFile
                        Log          = $server.DefaultLog
                        Backup       = $server.BackupDirectory
                    }
                } catch {
                    Stop-Function -Message "Error occurred while committing changes to $instance" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}