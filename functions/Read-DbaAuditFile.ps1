function Read-DbaAuditFile {
    <#
        .SYNOPSIS
            Read Audit details from a sqlaudit file.

        .DESCRIPTION
            Read Audit details from a sqlaudit file.

        .PARAMETER Path
            The path to the sqlaudit file. This is relative to the computer executing the command. UNC paths are supported.

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
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Read-DbaAuditFile

        .EXAMPLE
            Read-DbaAuditFile -Path C:\temp\logins.sqlaudit

            Returns events from C:\temp\logins.sqlaudit.

        .EXAMPLE
            Get-ChildItem C:\temp\audit\*.sqlaudit | Read-DbaAuditFile

            Returns events from all .sqlaudit files in C:\temp\audit.

        .EXAMPLE
            Get-DbaServerAudit -SqlInstance sql2014 -Audit LoginTracker | Read-DbaAuditFile

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
                $currentfile = $file
                $manualadd = $true
            }
            elseif ($file -is [System.IO.FileInfo]) {
                $currentfile = $file.FullName
                $manualadd = $true
            }
            else {
                if ($file -isnot [Microsoft.SqlServer.Management.Smo.Audit]) {
                    Stop-Function -Message "Unsupported file type."
                    return
                }

                if ($file.FullName.Length -eq 0) {
                    Stop-Function -Message "This Audit does not have an associated file."
                    return
                }

                $instance = [dbainstance]$file.ComputerName

                if ($instance.IsLocalHost) {
                    $currentfile = $file.FullName
                }
                else {
                    $currentfile = $file.RemoteFullName
                }
            }

            if (-not $Exact) {
                $currentfile = $currentfile.Replace('.sqlaudit', '*.sqlaudit')

                if ($currentfile -notmatch "sqlaudit") {
                    $currentfile = "$currentfile*.sqlaudit"
                }
            }

            $accessible = Test-Path -Path $currentfile
            $whoami = whoami

            if (-not $accessible) {
                if ($file.Status -eq "Stopped") { continue }
                Stop-Function -Continue -Message "$currentfile cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?"
            }

            if ($raw) {
                return New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentfile)
            }

            $enum = New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentfile)
            $newcolumns = ($enum.Fields.Name | Select-Object -Unique)

            $actions = ($enum.Actions.Name | Select-Object -Unique)
            foreach ($action in $actions) {
                $newcolumns += ($action -Split '\.')[-1]
            }

            $newcolumns = $newcolumns | Sort-Object
            $columns = ($columns += $newcolumns) | Select-Object -Unique

            # Make it selectable, otherwise it's a weird enumeration
            foreach ($event in (New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentfile))) {
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