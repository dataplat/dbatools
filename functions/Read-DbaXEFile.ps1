function Read-DbaXEFile {
    <#
    .SYNOPSIS
    Read XEvents from a xel or xem file

    .DESCRIPTION
    Read XEvents from a xel or xem file.

    .PARAMETER Path
    The path to the file. This is relative to the computer executing the command. UNC paths supported.

    .PARAMETER Exact
    By default, this command will add a wildcard to the Path because Eventing uses the file name as a template and adds characters. Use this to skip the addition of the wildcard.

    .PARAMETER Raw
    Returns the Microsoft.SqlServer.XEvent.Linq.PublishedEvent enumeration object

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Xevent
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Read-DbaXEFile

    .EXAMPLE
    Read-DbaXEFile -Path C:\temp\deadocks.xel

    Returns events from C:\temp\deadocks.xel
    
    .EXAMPLE
    Get-ChildItem C:\temp\xe\*.xel | Read-DbaXEFile

    Returns events from all .xel files in C:\temp\xe

    .EXAMPLE
    Get-DbaXESession -SqlInstance sql2014 -Session deadlocks | Read-DbaXEFile

    Reads remote xevents by acccessing the file over the admin UNC share

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
            
            if ($file -is [System.String]) {
                $currentfile = $file
            }
            elseif ($file -is [System.IO.FileInfo]) {
                $currentfile = $file.FullName
            }
            else {
                if ($file -isnot [Microsoft.SqlServer.Management.XEvent.Session]) {
                    Stop-Function -Message "Unsupported file type"
                    return
                }
                
                if ($file.TargetFile.Length -eq 0) {
                    Stop-Function -Message "This session does not have an associated Target File"
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
            }
            
            $accessible = Test-Path -Path $currentfile
            $whoami = whoami
            
            if (-not $accessible) {
                if ($file.Status -eq "Stopped") { continue }
                Stop-Function -Continue -Message "$currentfile cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?"
            }
            
            if ($raw) {
                New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentfile)
            }
            else {
                # Make it selectable, otherwise it's a weird enumeration
                foreach ($event in (New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentfile))) {
                    # it's okay to return more rows
                    $row = [pscustomobject]@{
                        Name      = $event.Name
                        TimeStemp = $event.Timestamp
                    }
                    
                    foreach ($action in $event.Actions) {
                        Add-Member -InputObject $row -NotePropertyName $action.Name -NotePropertyValue $action.Value
                    }
                    
                    foreach ($field in $event.Fields) {
                        Add-Member -Force -InputObject $row -NotePropertyName $field.Name -NotePropertyValue $field.Value
                    }
                    
                    Select-DefaultView -InputObject $row -ExcludeProperty Fields, Actions
                }
            }
        }
    }
}