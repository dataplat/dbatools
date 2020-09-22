function Export-DbaXECsv {
    <#
    .SYNOPSIS
        Exports Extended Events to a CSV file.

    .DESCRIPTION
        Exports Extended Events to a CSV file.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER InputObject
        Allows Piping

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaXECsv

    .EXAMPLE
        PS C:\> Get-ChildItem -Path C:\temp\sample.xel | Export-DbaXECsv -Path c:\temp\sample.csv

        Writes Extended Events data to the file "C:\temp\events.csv".

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2014 -Session deadlocks | Export-DbaXECsv -Path c:\temp\events.csv

        Writes Extended Events data to the file "C:\temp\events.csv".

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('FullName')]
        [object[]]$InputObject,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\libraries\third-party\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        } catch {
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
                } else {
                    $xelpath = $InputObject.RemoteTargetFile
                }
                
                #this is funny, TargetFile usually is more a path than a real file
                #Even if the filename property is set to a fixed filepath with a xel
                #extension, the produced files have something appended to it to make
                #sure max_file_size and max_rollover_files are respected.
                #so, even if file ends with .xel, we need to pick up <filename>*.xel
                if (-not($xelpath.EndsWith(".xel"))) {
                    $xelpath = "$xelpath*.xel"
                } else {
                    $xelpath = "$($xelpath.Substring(0, $xelpath.Length-4))*.xel"
                }
                try {
                    Get-ChildItem -Path $xelpath -ErrorAction Stop
                } catch {
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
            } elseif ($file -is [System.IO.FileInfo]) {
                $currentfile = $file.FullName
            } elseif ($file -is [Microsoft.SqlServer.Management.XEvent.Session]) {
                # it was taken care of above
                continue
            } else {
                Stop-Function -Message "Unsupported file type."
                return
            }

            $accessible = Test-Path -Path $currentfile
            $whoami = whoami

            if (-not $accessible) {
                if ($file.Status -eq "Stopped") { continue }
                Stop-Function -Continue -Message "$currentfile cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?"
            }

            $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type csv -ServerName $instance
            $adapter = New-Object XESmartTarget.Core.Utils.XELFileCSVAdapter
            $adapter.InputFile = $currentfile
            $adapter.OutputFile = $FilePath

            try {
                $adapter.Convert()
                $file = Get-ChildItem -Path $adapter.OutputFile

                if ($file.Length -eq 0) {
                    Remove-Item -Path $adapter.OutputFile
                } else {
                    $file
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
            }
        }
    }
}