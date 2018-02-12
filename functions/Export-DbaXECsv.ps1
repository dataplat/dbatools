function Export-DbaXECsv {
    <#
        .SYNOPSIS
            Exports Extended Events to a CSV file.

        .DESCRIPTION
            Exports Extended Events to a CSV file.

        .PARAMETER Path
            Specifies the path to the input XEL file.

        .PARAMETER OutpuPath
            Specifies the path to the output CSV file.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Export-DbaXECsv

        .EXAMPLE
            Read-DbaXEFile -Path C:\temp\events.xel | Export-DbaXECsv -Path c:\temp\events.csv
            
            Writes Extended Events data to the file "C:\temp\events.csv".
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('FullName')]
        [object[]]$Path,
        [parameter(Mandatory)]
        [object[]]$OutputPath,
        [switch][Alias('Silent')]
        $EnableException
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        }
        catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {

        foreach ($file in $path) {

            if(-not (Test-Path $OutputPath)){
                if([String]::IsNullOrEmpty([IO.Path]::GetExtension($OutputPath))) {
                    New-Item $OutputPath -ItemType directory | Out-Null
                    $outDir = $OutputPath
                    $outFile = [IO.Path]::GetFileNameWithoutExtension($file) + ".csv"
                }
                else {
                    $outDir = [IO.Path]::GetDirectoryName($OutputPath)
                    $outFile = [IO.Path]::GetFileName($OutputPath)
                }
            }
            else {
                if((Get-Item $OutputPath) -is [System.IO.DirectoryInfo]){
                    $outDir = $OutputPath
                    $outFile = [IO.Path]::GetFileNameWithoutExtension($file) + ".csv"
                }
                else {
                    $outDir = [IO.Path]::GetDirectoryName($OutputPath)
                    $outFile = [IO.Path]::GetFileName($OutputPath)
                }
            }

            $adapter = New-Object XESmartTarget.Core.Utils.XELFileCSVAdapter
            $adapter.InputFile = $file
            $adapter.OutputFile = Join-Path $outDir $outFile

            try {
                $adapter.Convert()
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
            }
        }
    }
}