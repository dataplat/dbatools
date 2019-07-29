function Export-DbaPfDataCollectorSetTemplate {
    <#
    .SYNOPSIS
        Exports a new Data Collector Set XML Template.

    .DESCRIPTION
        Exports a Data Collector Set XML Template from Get-DbaPfDataCollectorSet. Exports to "$home\Documents\Performance Monitor Templates" by default.

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        The name of the collector set(s) to export.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER InputObject
        Accepts the object output by Get-DbaPfDataCollectorSetTemplate via the pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaPfDataCollectorSetTemplate

    .EXAMPLE
        PS C:\> Export-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Path C:\temp\pf

        Exports all data collector sets from to the C:\temp\pf folder.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet ComputerName sql2017 -CollectorSet 'System Correlation' | Export-DbaPfDataCollectorSetTemplate -Path C:\temp

        Exports the 'System Correlation' data collector set from sql2017 to C:\temp.

    #>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
            $Credential = $InputObject.Credential
        }

        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet
            }
        }

        foreach ($object in $InputObject) {
            if (-not $object.DataCollectorSetObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet."
                return
            }

            if (-not $FilePath) {
                $csname = Remove-InvalidFileNameChars -Name $object.Name
                $FilePath = "$Path\$csname.xml"
            }

            Write-Message -Level Verbose -Message "Wrote $csname to $filename."
            Set-Content -Path $FilePath -Value $object.Xml -Encoding Unicode
            Get-ChildItem -Path $FilePath
        }
    }
}