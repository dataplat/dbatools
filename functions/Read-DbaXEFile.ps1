function Read-DbaXEFile {
    <#
        .SYNOPSIS
            Read XEvents from a xel or xem file.

        .DESCRIPTION
            Read XEvents from a xel or xem file.

        .PARAMETER Path
            The path to the xel or xem file. This is relative to the computer executing the command. UNC paths are supported.

        .PARAMETER Exact
            If this switch is enabled, only an exact search will be used for the Path. By default, this command will add a wildcard to the Path because Eventing uses the file name as a template and adds characters.

        .PARAMETER Raw
            If this switch is enabled, the Microsoft.SqlServer.XEvent.Linq.PublishedEvent enumeration object will be returned.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Read-DbaXEFile

        .EXAMPLE
            Read-DbaXEFile -Path C:\temp\deadocks.xel

            Returns events from C:\temp\deadocks.xel.

        .EXAMPLE
            Get-ChildItem C:\temp\xe\*.xel | Read-DbaXEFile

            Returns events from all .xel files in C:\temp\xe.

        .EXAMPLE
            Get-DbaXESession -SqlInstance sql2014 -Session deadlocks | Read-DbaXEFile

            Reads remote XEvents by accessing the file over the admin UNC share.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('FullName')]
        [object[]]$Path,
        [switch]$Exact,
        [switch]$Raw,
        [switch][Alias('Silent')]
        $EnableException
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
                if ($file -isnot [Microsoft.SqlServer.Management.XEvent.Session]) {
                    Stop-Function -Message "Unsupported file type."
                    return
                }

                if ($file.TargetFile.Length -eq 0) {
                    Stop-Function -Message "This session does not have an associated Target File."
                    return
                }

                $instance = [dbainstance]$file.ComputerName

                if ($instance.IsLocalHost) {
                    $currentfile = $file.TargetFile
                }
                else {
                    $currentfile = $file.RemoteTargetFile
                }
            }

            if (-not $Exact) {
                $currentfile = $currentfile.Replace('.xel', '*.xel')
                $currentfile = $currentfile.Replace('.xem', '*.xem')

                if ($currentfile -notmatch "xel" -and $currentfile -notmatch "xem") {
                    $currentfile =  "$currentfile*.xel"
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