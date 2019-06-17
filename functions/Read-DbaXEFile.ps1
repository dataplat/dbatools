function Read-DbaXEFile {
    <#
    .SYNOPSIS
        Read XEvents from a *.xel or *.xem file.

    .DESCRIPTION
        Read XEvents from a *.xel or *.xem file.

    .PARAMETER Path
        The path to the *.xem or *.xem file. This is relative to the computer executing the command. UNC paths are supported.

    .PARAMETER Exact
        If this switch is enabled, only an exact search will be used for the Path. By default, this command will add a wildcard to the Path because Eventing uses the file name as a template and adds characters.

    .PARAMETER Raw
        If this switch is enabled, the Microsoft.SqlServer.XEvent.Linq.PublishedEvent enumeration object will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Read-DbaXEFile

    .EXAMPLE
        PS C:\> Read-DbaXEFile -Path C:\temp\deadocks.xel

        Returns events from C:\temp\deadocks.xel.

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\xe\*.xel | Read-DbaXEFile

        Returns events from all .xel files in C:\temp\xe.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2014 -Session deadlocks | Read-DbaXEFile

        Reads remote XEvents by accessing the file over the admin UNC share.

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
    begin {
        # there's sometimes a compat issue with XE.Core. Until we get this resolved with the new dlls, here's a potential workaround.
        $hasdll = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object Fullname -like "Microsoft.SqlServer.XEvent.Linq,*"
        if (-not $hasdll.Location) {
            Stop-Function -Message "Could not load XEvent DLLs. This is a known issue and will be resolved as time allows."
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($file in $path) {
            # in order to ensure CSV gets all fields, all columns will be
            # collected and output in the first (all all subsequent) object
            $columns = @("name", "timestamp")

            if ($file -is [System.String]) {
                $currentfile = $file
                #Variable marked as unused by PSScriptAnalyzer
                #$manualadd = $true
            } elseif ($file -is [System.IO.FileInfo]) {
                $currentfile = $file.FullName
                #Variable marked as unused by PSScriptAnalyzer
                #$manualadd = $true
            } else {
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
                } else {
                    $currentfile = $file.RemoteTargetFile
                }
            }

            if (-not $Exact) {
                $currentfile = $currentfile.Replace('.xel', '*.xel')
                $currentfile = $currentfile.Replace('.xem', '*.xem')

                if ($currentfile -notmatch "xel" -and $currentfile -notmatch "xem") {
                    $currentfile = "$currentfile*.xel"
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
            foreach ($event in $enum) {
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
            $enum.Dispose()
        }
    }
}