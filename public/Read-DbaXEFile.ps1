function Read-DbaXEFile {
    <#
    .SYNOPSIS
        Parses Extended Events trace files (.xel/.xem) into structured PowerShell objects for analysis

    .DESCRIPTION
        Converts Extended Events trace files into PowerShell objects so you can analyze captured SQL Server events without needing SQL Server Management Studio. This function takes the raw XEvent data from .xel or .xem files and transforms it into structured objects with properties for each field and action in the trace.

        Perfect for post-incident analysis of deadlocks, performance issues, or security events that were captured by your Extended Events sessions. You can pipe the results to other PowerShell cmdlets for filtering, sorting, exporting to CSV, or building reports.

        When using pipeline input from Get-DbaXESession, the function automatically skips the file currently being written to avoid access conflicts, and can read files from remote servers via admin shares.

    .PARAMETER Path
        Specifies the Extended Events file path (.xel or .xem), file objects, or XEvent session objects to read from. Supports local paths, UNC paths for remote files, and pipeline input from Get-ChildItem or Get-DbaXESession.
        When using session objects from Get-DbaXESession, automatically accesses files via admin shares and skips the current file being written to prevent access conflicts.

    .PARAMETER Raw
        Returns the native Microsoft.SqlServer.XEvent.XELite.XEvent objects instead of structured PowerShell objects. Use this when you need direct access to the XEvent object properties and methods for advanced programmatic processing.
        By default, events are converted to PSCustomObjects with all fields and actions as individual properties for easier analysis and reporting.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.XEvent.XELite.XEvent[] (when -Raw is specified)

        Returns the native XEvent objects from the XELite reader with full access to XEvent properties and methods for advanced programmatic processing.

        PSCustomObject[] (default)

        Returns one object per event in the trace file with dynamic properties based on the captured fields and actions. All objects include standard properties plus event-specific fields:

        Standard properties:
        - name: The name of the Extended Event
        - timestamp: The timestamp when the event was captured

        Dynamic properties vary based on the Extended Events session configuration and captured actions:
        - All unique field names from the XEvent.Fields collection appear as individual properties
        - All unique action names from the XEvent.Actions collection appear as individual properties (action names are normalized to remove the leading package.action prefix)

        For example, a deadlock trace might include properties like: database_id, duration, cpu_time, physical_reads, logical_reads, writes, priority, transaction_id, client_app_name, etc. A security audit trace might include: client_principal_name, server_principal_name, statement, etc.

        Use Select-Object * to see all properties returned in the results.

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
        PS C:\> Get-DbaXESession -SqlInstance sql2019 -Session deadlocks | Read-DbaXEFile

        Reads remote XEvents by accessing the file over the admin UNC share.

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
        if (Test-FunctionInterrupt) { return }
        foreach ($pathObject in $Path) {
            # in order to ensure CSV gets all fields, all columns will be
            # collected and output in the first (all all subsequent) object
            $columns = @("name", "timestamp")

            if ($pathObject -is [System.String]) {
                $files = $pathObject
            } elseif ($pathObject -is [System.IO.FileInfo]) {
                $files = $pathObject.FullName
            } elseif ($pathObject -is [Microsoft.SqlServer.Management.XEvent.Session]) {
                if ($pathObject.TargetFile.Length -eq 0) {
                    Stop-Function -Message "The session [$pathObject] does not have an associated Target File." -Continue
                }

                $instance = [DbaInstance]$pathObject.ComputerName
                if ($instance.IsLocalHost) {
                    $targetFile = $pathObject.TargetFile
                } else {
                    $targetFile = $pathObject.RemoteTargetFile
                }

                $targetFile = $targetFile.Replace('.xel', '*.xel').Replace('.xem', '*.xem')
                $files = Get-ChildItem -Path $targetFile | Sort-Object LastWriteTime
                if ($pathObject.Status -eq 'Running') {
                    $files = $files | Select-Object -SkipLast 1
                }
                Write-Message -Level Verbose -Message "Received $($files.Count) files based on [$targetFile]"
            } else {
                Stop-Function -Message "The Path [$pathObject] has an unsupported file type of [$($pathObject.GetType().FullName)]."
            }

            foreach ($file in $files) {
                if (-not (Test-Path -Path $file)) {
                    Stop-Function -Message "$file cannot be accessed from $($env:COMPUTERNAME)." -Continue
                }

                if ($Raw) {
                    try {
                        Read-XEvent -FileName $file
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                    }
                } else {
                    try {
                        $enum = Read-XEvent -FileName $file
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
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
    }
}