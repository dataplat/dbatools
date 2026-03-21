function Mount-DbaDatabase {
    <#
    .SYNOPSIS
        Attaches detached database files to a SQL Server instance

    .DESCRIPTION
        Attaches detached database files (.mdf, .ldf, .ndf) back to a SQL Server instance, making the database available for use again. When database files exist on disk but the database is not registered in the SQL Server instance, this command reconnects them using the SQL Server Management Objects (SMO) AttachDatabase method.

        If you don't specify the file structure, the command attempts to determine the correct database files by examining backup history for the most recent full backup. This is particularly useful when restoring databases from file copies or moving databases between instances where the files already exist but need to be reattached.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the names of the detached databases to attach to the SQL Server instance.
        Use this when you have database files (.mdf, .ldf, .ndf) on disk but the database is no longer registered in SQL Server.

    .PARAMETER FileStructure
        Specifies the complete collection of database file paths (.mdf, .ldf, .ndf) required to attach the database.
        When omitted, the command attempts to determine file locations automatically using backup history from the most recent full backup.
        Use this parameter when files are in non-standard locations or when automatic detection fails.

    .PARAMETER DatabaseOwner
        Sets the login account that will own the attached database.
        When not specified, defaults to the sa account or the SQL Server sysadmin with ID 1 if sa is not available.
        Use this to assign ownership to a specific login for security or administrative requirements.

    .PARAMETER AttachOption
        Controls how SQL Server handles the database attachment process and Service Broker configuration.
        Use 'RebuildLog' when transaction log files are missing or corrupt, 'EnableBroker' to activate Service Broker, or 'NewBroker' to create a new Service Broker identifier.
        Defaults to 'None' for standard attachment without special handling.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Attach, Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Mount-DbaDatabase

    .OUTPUTS
        PSCustomObject

        Returns one object per database successfully attached to the SQL Server instance.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: The name of the database that was attached
        - AttachResult: Status of the attach operation (always "Success" when returned)
        - AttachOption: The attach option that was used (None, RebuildLog, EnableBroker, NewBroker, or ErrorBrokerConversations)
        - FileStructure: System.Collections.Specialized.StringCollection containing the file paths that were attached

    .EXAMPLE
        PS C:\> $fileStructure = New-Object System.Collections.Specialized.StringCollection
        PS C:\> $fileStructure.Add("E:\archive\example.mdf")
        PS C:\> $filestructure.Add("E:\archive\example.ldf")
        PS C:\> $filestructure.Add("E:\archive\example.ndf")
        PS C:\> Mount-DbaDatabase -SqlInstance sql2016 -Database example -FileStructure $fileStructure

        Attaches a database named "example" to sql2016 with the files "E:\archive\example.mdf", "E:\archive\example.ldf" and "E:\archive\example.ndf". The database owner will be set to sa and the attach option is None.

    .EXAMPLE
        PS C:\> Mount-DbaDatabase -SqlInstance sql2016 -Database example

        Since the FileStructure was not provided, this command will attempt to determine it based on backup history. If found, a database named example will be attached to sql2016.

    .EXAMPLE
        PS C:\> Mount-DbaDatabase -SqlInstance sql2016 -Database example -WhatIf

        Shows what would happen if the command were executed (without actually performing the command)

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [parameter(Mandatory)]
        [string[]]$Database,
        [System.Collections.Specialized.StringCollection]$FileStructure,
        [string]$DatabaseOwner,
        [ValidateSet('None', 'RebuildLog', 'EnableBroker', 'NewBroker', 'ErrorBrokerConversations')]
        [string]$AttachOption = "None",
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not $server.Logins.Item($DatabaseOwner)) {
                try {
                    $DatabaseOwner = ($server.Logins | Where-Object { $_.id -eq 1 }).Name
                } catch {
                    $DatabaseOwner = "sa"
                }
            }

            foreach ($db in $database) {

                if ($server.Databases[$db]) {
                    Stop-Function -Message "$db is already attached to $server." -Target $db -Continue
                }

                if (-Not (Test-Bound -Parameter FileStructure)) {
                    $backuphistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $db -Type Full | Sort-Object End -Descending | Select-Object -First 1

                    if (-not $backuphistory) {
                        $message = "Could not enumerate backup history to automatically build FileStructure. Rerun the command and provide the filestructure parameter."
                        Stop-Function -Message $message -Target $db -Continue
                    }

                    $backupfile = $backuphistory.Path[0]
                    $filepaths = (Read-DbaBackupHeader -SqlInstance $server -FileList -Path $backupfile).PhysicalName | Select-Object -Unique

                    $FileStructure = New-Object System.Collections.Specialized.StringCollection
                    foreach ($file in $filepaths) {
                        $exists = Test-DbaPath -SqlInstance $server -Path $file
                        if (-not $exists) {
                            $message = "Could not find the files to build the FileStructure. Rerun the command and provide the FileStructure parameter."
                            Stop-Function -Message $message -Target $file -Continue
                        }

                        $null = $FileStructure.Add($file)
                    }
                }

                If ($Pscmdlet.ShouldProcess($server, "Attaching $Database with $DatabaseOwner as database owner and $AttachOption as attachoption")) {
                    try {
                        $server.AttachDatabase($db, $FileStructure, $DatabaseOwner, [Microsoft.SqlServer.Management.Smo.AttachOptions]::$AttachOption)

                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $db
                            AttachResult  = "Success"
                            AttachOption  = $AttachOption
                            FileStructure = $FileStructure
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server
                    }
                }
            }
        }
    }
}