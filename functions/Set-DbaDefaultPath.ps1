function Set-DbaDefaultPath {
    <#
    .SYNOPSIS
        Sets the default SQL Server paths for data, logs, error logs and backups

    .DESCRIPTION
        Sets the default SQL Server paths for data, logs, error logs and backups

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Type
        The type of path to modify. Options include: Data, Logs, ErrorLog, and Backups.

    .PARAMETER Path
        The path on the destination SQL Server

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Data, Logs, Backups
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDefaultPath

    .EXAMPLE
        PS C:\> Set-DbaDefaultPath -SqlInstance sql01\sharepoint -Type Data, ErrorLog -Path C:\mssql\sharepoint\data

        Sets the data and error log default paths on sql01\sharepoint to C:\mssql\sharepoint\data

    .EXAMPLE
        PS C:\> Set-DbaDefaultPath -SqlInstance sql01\sharepoint -Type Data, ErrorLog -Path C:\mssql\sharepoint\data -WhatIf

        Shows what what happen if the command would have run
    #>
    [cmdletbinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('Data', 'Backup', 'Log', 'ErrorLog')]
        [string[]]$Type,
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Path,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $Path = $Path.Trim().TrimEnd("\")

            if (-not (Test-DbaPath -SqlInstance $server -Path $Path)) {
                Stop-Function -Message "Path $Path is not accessible on $($server.Name)" -Target $instance -Continue
            }

            if ($Type -contains  "Data") {
                if ($Pscmdlet.ShouldProcess($server.Name, "Changing DefaultFile to $Path")) {
                    $server.DefaultFile = $Path
                }
            }

            if ($Type -contains  "Log") {
                if ($Pscmdlet.ShouldProcess($server.Name, "Changing DefaultLog to $Path")) {
                    $server.DefaultLog = $Path
                }
            }

            if ($Type -contains  "Backup") {
                if ($Pscmdlet.ShouldProcess($server.Name, "Changing BackupDirectory to $Path")) {
                    $server.BackupDirectory = $Path
                }
            }

            if ($Type -contains "ErrorLog") {
                if ($Pscmdlet.ShouldProcess($server.Name, "Changing ErrorlogPath to $Path")) {
                    $server.ErrorlogPath = $Path
                }
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Committing changes")) {
                try {
                    $server.Alter()
                    if ($Type -contains "Data" -or $Type -contains "Log" -or $Type -contains "ErrorLog") {
                        Write-Message -Level Warning -Message "You must restart the SQL Service on $instance for changes to take effect"
                    }
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Data         = $server.DefaultFile
                        Log          = $server.DefaultLog
                        Backup       = $server.BackupDirectory
                        ErrorLog     = $server.ErrorlogPath
                    }
                } catch {
                    Stop-Function -Message "Error occurred while committing changes to $instance" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}