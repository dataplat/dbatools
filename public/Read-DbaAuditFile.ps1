function Read-DbaAuditFile {
    <#
    .SYNOPSIS
        Parses SQL Server audit files (.sqlaudit) into structured event data for security analysis and compliance reporting.

    .DESCRIPTION
        Reads and parses SQL Server audit files (.sqlaudit) created by SQL Server Audit functionality, converting binary audit data into readable PowerShell objects. Each audit event is returned with its timestamp, event details, fields, and actions in a structured format that's easy to filter, export, or analyze. This is essential for security investigations, compliance reporting, and monitoring database access patterns since SQL Server audit files are stored in a proprietary binary format that can't be read directly. Works with local files, UNC paths, or can be piped from Get-DbaInstanceAudit to automatically locate and read audit files from remote instances.

    .PARAMETER Path
        The path to the *.sqlaudit file. This is relative to the computer executing the command. UNC paths are supported.

    .PARAMETER Raw
        If this switch is enabled, the enumeration object will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: XE, Audit, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Read-DbaAuditFile

    .EXAMPLE
        PS C:\> Read-DbaAuditFile -Path C:\temp\logins.sqlaudit

        Returns events from C:\temp\logins.sqlaudit.

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\audit\*.sqlaudit | Read-DbaAuditFile

        Returns events from all .sqlaudit files in C:\temp\audit.

    .EXAMPLE
        PS C:\> Get-DbaInstanceAudit -SqlInstance sql2014 -Audit LoginTracker | Read-DbaAuditFile

        Reads remote Audit details by accessing the file over the admin UNC share.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('FullName')]
        [object[]]$Path,
        [switch]$Raw,
        [switch]$EnableException
    )
    process {
        foreach ($file in $Path) {
            # in order to ensure CSV gets all fields, all columns will be
            # collected and output in the first (all all subsequent) object
            $columns = @("name", "timestamp")

            if ($file -is [System.String]) {
                $currentFile = $file
            } elseif ($file -is [System.IO.FileInfo]) {
                $currentFile = $file.FullName
            } else {
                if ($file -isnot [Microsoft.SqlServer.Management.Smo.Audit]) {
                    Stop-Function -Message "Unsupported file type."
                    return
                }

                if (-not $file.FullName) {
                    Stop-Function -Message "This Audit does not have an associated file."
                    return
                }

                $instance = [DbaInstanceParameter]$file.ComputerName

                if ($instance.IsLocalHost) {
                    $currentFile = $file.FullName
                } else {
                    $currentFile = $file.RemoteFullName
                }
            }

            # $currentFile is only the base filename and must be expanded using a wildcard
            $fileNames = (Get-ChildItem -Path ($currentFile -replace '\.sqlaudit$', '*.sqlaudit') | Sort-Object CreationTime).FullName
            $enum = @( )
            foreach ($fileName in $fileNames) {
                $accessible = Test-Path -Path $fileName
                $whoami = whoami
                if (-not $accessible) {
                    Stop-Function -Continue -Message "$fileName cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?"
                }

                $enum += Read-XEvent -FileName $fileName
            }

            if ($Raw) {
                return $enum
            }

            $newcolumns = ($enum.Fields.Name | Select-Object -Unique)

            $actions = ($enum.Actions.Name | Select-Object -Unique)
            foreach ($action in $actions) {
                $newcolumns += ($action -Split '\.')[-1]
            }

            $newcolumns = $newcolumns | Sort-Object
            $columns = ($columns += $newcolumns) | Select-Object -Unique

            # Make it selectable, otherwise it's a weird enumeration
            foreach ($event in $enum) {
                $hash = [ordered]@{ }

                foreach ($column in $columns) {
                    $null = $hash.Add($column, $event.$column)
                }

                foreach ($key in $event.Actions.Keys) {
                    $hash[$key] = $event.Actions[$key]
                }

                foreach ($key in $event.Fields.Keys) {
                    $hash[$key] = $event.Fields[$key]
                }

                [PSCustomObject]$hash
            }
        }
    }
}