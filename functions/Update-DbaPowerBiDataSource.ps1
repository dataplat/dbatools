function Update-DbaPowerBiDataSource {
    <#
        .SYNOPSIS
            Converts the results of dbatools commands for our PowerBI Dashboard related commands. This command is specific to our toolset and not a general Power BI command.

        .DESCRIPTION
            Converts the results of dbatools commands for our PowerBI Dashboard related commands. This command is specific to our toolset and not a general Power BI command.

        .PARAMETER InputObject
            Enables piping

        .PARAMETER Path
            The directory to store your files. "C:\windows\temp\dbatools\" by default

        .PARAMETER Enviornment
            Tag your data with an enviornment. Defaults to "Default"

        .PARAMETER Append
            Don't delete previous default data sources.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .EXAMPLE
            Get-DbaPfDataCollectorSet -ComputerName sql2016 | Invoke-DbaPfRelog -AllowClobber | Update-DbaPowerBiDataSource | Start-DbaPowerBi

            Converts the results of the performance monitor data source and stores it in the appropriate directory then launches our Power BI dashboard

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [pscustomobject]$InputObject,
        [string]$Path = "$env:windir\temp\dbatools",
        [string]$Enviornment = "Default",
        [switch]$Append,
        [switch]$EnableException
    )
    begin {
        if ($Environment -ne "Default" -and -not $Append) {
            $null = Remove-Item "$Path\*Default*.*sv" -ErrorAction SilentlyContinue
        }
        $orginalpath = $Path
    }
    process {
        ++$i

        if ($InputObject.RelogFile) {
            $Path = "$orginalpath\perfmon"
        }
        else {
            $Path = "$orginalpath\xevents"
        }

        try {
            if (-not (Test-Path -Path $Path)) {
                $null = New-Item -ItemType Directory -Path $Path -ErrorAction Stop
            }
        }
        catch {
            Stop-Function -Message "Failure" -Exception $_
            return
        }

        $extension = $InputObject.Extension.TrimStart(".")
        $basename = "dbatools_$i"
        if ($InputObject.TagFilter) {
            $basename = "$basename`_$($InputObject.TagFilter -join "_")"
        }

        if ($Enviornment) {
            $basename = "$basename`_$Enviornment"
        }

        $filename = "$basename.$extension"

        try {
            Write-Message -Level Verbose -Message "Writing $filename to $path"
            $inputObject | Copy-Item -Destination "$path\$filename"
            Get-ChildItem "$path\$filename"
        }
        catch {
            Stop-Function -Message "Failure" -ErrorRecord $_
            return
        }
    }
    end {
        if ($InputObject -isnot [System.IO.FileInfo] -and $InputObject -isnot [System.IO.DirectoryInfo]) {
            Stop-Function -Message "Invalid input"
            return
        }
    }
}