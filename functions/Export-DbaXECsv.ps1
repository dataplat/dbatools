function Export-DbaXECsv {
    <#
        .SYNOPSIS
            Exports Extended Events to a CSV file.

        .DESCRIPTION
            Exports Extended Events to a CSV file.

        .PARAMETER Path
            Specifies the InputObject to the output CSV file

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER InputObject
            Allows Piping

        .NOTES
            Author: Gianluca Sartori (@spaghettidba)
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT
            SmartTarget: by Gianluca Sartori (@spaghettidba)

        .LINK
            https://dbatools.io/Export-DbaXECsv

        .EXAMPLE
            Get-ChildItem -Path C:\temp\sample.xel | Export-DbaXECsv -Path c:\temp\sample.csv

            Writes Extended Events data to the file "C:\temp\events.csv".

         .EXAMPLE
            Get-DbaXESession -SqlInstance sql2014 -Session deadlocks | Export-DbaXECsv -Path c:\temp\events.csv

            Writes Extended Events data to the file "C:\temp\events.csv".
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('FullName')]
        [object[]]$InputObject,
        [parameter(Mandatory)]
        [string]$Path,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        }
        catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }

        function Get-FileFromXE ($InputObject) {
            if ($InputObject.TargetFile) {
                if ($InputObject.TargetFile.Length -eq 0) {
                    Stop-Function -Message "This session does not have an associated Target File."
                    return
                }

                $instance = [dbainstance]$InputObject.ComputerName

                if ($instance.IsLocalHost) {
                    $xelpath = $InputObject.TargetFile
                }
                else {
                    $xelpath = $InputObject.RemoteTargetFile
                }

                if ($xelpath -notmatch ".xel") {
                    $xelpath = "$xelpath*.xel"
                }

                try {
                    Get-ChildItem -Path $xelpath -ErrorAction Stop
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        $getfiles = Get-FileFromXE $InputObject

        if ($getfiles) {
            $InputObject += $getfiles
        }

        foreach ($file in $InputObject) {
            if ($file -is [System.String]) {
                $currentfile = $file
            }
            elseif ($file -is [System.IO.FileInfo]) {
                $currentfile = $file.FullName
            }
            elseif ($file -is [Microsoft.SqlServer.Management.XEvent.Session]) {
                # it was taken care of above
                continue
            }
            else {
                Stop-Function -Message "Unsupported file type."
                return
            }

            $accessible = Test-Path -Path $currentfile
            $whoami = whoami

            if (-not $accessible) {
                if ($file.Status -eq "Stopped") { continue }
                Stop-Function -Continue -Message "$currentfile cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?"
            }

            if (-not (Test-Path $Path)) {
                if ([String]::IsNullOrEmpty([IO.Path]::GetExtension($Path))) {
                    New-Item $Path -ItemType directory | Out-Null
                    $outDir = $Path
                    $outFile = [IO.Path]::GetFileNameWithoutExtension($currentfile) + ".csv"
                }
                else {
                    $outDir = [IO.Path]::GetDirectoryName($Path)
                    $outFile = [IO.Path]::GetFileName($Path)
                }
            }
            else {
                if ((Get-Item $Path) -is [System.IO.DirectoryInfo]) {
                    $outDir = $Path
                    $outFile = [IO.Path]::GetFileNameWithoutExtension($currentfile) + ".csv"
                }
                else {
                    $outDir = [IO.Path]::GetDirectoryName($Path)
                    $outFile = [IO.Path]::GetFileName($Path)
                }
            }

            $adapter = New-Object XESmartTarget.Core.Utils.XELFileCSVAdapter
            $adapter.InputFile = $currentfile
            $adapter.OutputFile = (Join-Path $outDir $outFile)

            try {
                $adapter.Convert()
                $file = Get-ChildItem -Path $adapter.OutputFile

                if ($file.Length -eq 0) {
                    Remove-Item -Path $adapter.OutputFile
                }
                else {
                    $file
                }
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
            }
        }
    }
}
