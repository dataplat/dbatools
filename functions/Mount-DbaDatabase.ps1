function Mount-DbaDatabase {
    <#
    .SYNOPSIS
        Attach a SQL Server Database - aliased to Attach-DbaDatabase

    .DESCRIPTION
        This command will attach a SQL Server database.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to attach.

    .PARAMETER FileStructure
        A StringCollection object value that contains a list database files. If FileStructure is not specified, BackupHistory will be used to guess the structure.

    .PARAMETER DatabaseOwner
        Sets the database owner for the database. The sa account (or equivalent) will be used if DatabaseOwner is not specified.

    .PARAMETER AttachOption
        An AttachOptions object value that contains the attachment options. Valid options are "None", "RebuildLog", "EnableBroker", "NewBroker" and "ErrorBrokerConversations".

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Mount-DbaDatabase

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

                if ($server.Databases[$db].IsSystemObject) {
                    Stop-Function -Message "$db is a system database and cannot be attached using this method." -Target $db -Continue
                }

                if (-Not (Test-Bound -Parameter FileStructure)) {
                    $backuphistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $db -Type Full | Sort-Object End -Descending | Select-Object -First 1

                    if (-not $backuphistory) {
                        $message = "Could not enumerate backup history to automatically build FileStructure. Rerun the command and provide the filestructure parameter."
                        Stop-Function -Message $message -Target $db -Continue
                    }

                    $backupfile = $backuphistory.Path[0]
                    $filepaths = (Read-DbaBackupHeader -SqlInstance $server -FileList -Path $backupfile).PhysicalName

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

                        [pscustomobject]@{
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