function Read-DbaAuditFile {
    <#
    .SYNOPSIS
        Read Audit details from *.sqlaudit files.

    .DESCRIPTION
        Read Audit details from *.sqlaudit files.

    .PARAMETER Path
        The path to the *.sqlaudit file. This is relative to the computer executing the command. UNC paths are supported.

    .PARAMETER Exact
        If this switch is enabled, only an exact search will be used for the Path. By default, this command will add a wildcard to the Path because Eventing uses the file name as a template and adds characters.

    .PARAMETER Raw
        If this switch is enabled, the Microsoft.SqlServer.XEvent.Linq.PublishedEvent enumeration object will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, Audit
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
        [switch]$Exact,
        [switch]$Raw,
        [switch]$EnableException
    )
    process {
        foreach ($file in $path) {
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

                if ($file.FullName.Length -eq 0) {
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

            if (-not $Exact) {
                $currentFile = $currentFile.Replace('.sqlaudit', '*.sqlaudit')

                if ($currentFile -notmatch "sqlaudit") {
                    $currentFile = "$currentFile*.sqlaudit"
                }
            }

            $accessible = Test-Path -Path $currentFile
            $whoami = whoami

            if (-not $accessible) {
                if ($file.Status -eq "Stopped") { continue }
                Stop-Function -Continue -Message "$currentFile cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?"
            }

            if ($raw) {
                return New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentFile)
            }

            $enum = New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentFile)
            $newColumns = ($enum.Fields.Name | Select-Object -Unique)

            $actions = ($enum.Actions.Name | Select-Object -Unique)
            foreach ($action in $actions) {
                $newColumns += ($action -Split '\.')[-1]
            }

            $newColumns = $newColumns | Sort-Object
            $columns = ($columns += $newColumns) | Select-Object -Unique

            # Make it selectable, otherwise it's a weird enumeration
            foreach ($event in (New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentFile))) {
                $hash = [ordered]@{ }

                foreach ($column in $columns) {
                    $null = $hash.Add($column, $event.$column)
                }

                foreach ($action in $event.Actions) {
                    $hash[$action.Name] = $action.Value
                }

                foreach ($field in $event.Fields) {
                    $hash[$field.Name] = $field.Value
                }

                [pscustomobject]$hash
            }
        }
    }
}