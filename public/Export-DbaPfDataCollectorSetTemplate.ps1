function Export-DbaPfDataCollectorSetTemplate {
    <#
    .SYNOPSIS
        Exports Windows Performance Monitor Data Collector Set configurations as reusable XML templates.

    .DESCRIPTION
        Exports Data Collector Set configurations from Windows Performance Monitor as XML template files that can be imported on other SQL Server hosts. This allows you to standardize performance monitoring across your SQL Server environment by saving custom counter collections, sampling intervals, and output settings as portable templates. Particularly useful for creating consistent performance baselines and troubleshooting configurations that can be quickly deployed when performance issues arise.

    .PARAMETER ComputerName
        Specifies the target computer(s) to export data collector sets from. Defaults to localhost.
        Use this to export performance monitoring templates from remote SQL Server hosts for standardization across your environment.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies the name(s) of specific data collector sets to export. If not specified, all collector sets will be exported.
        Use this when you only need to export particular performance monitoring configurations rather than all available sets.

    .PARAMETER Path
        Specifies the directory where XML template files will be created. Each collector set exports as a separate XML file.
        Defaults to the configured dbatools export path, typically used when exporting multiple collector sets.

    .PARAMETER FilePath
        Specifies the complete file path including filename for the exported XML template. Use instead of Path when exporting a single collector set.
        Automatically appends .xml extension if not provided, ideal for creating named templates for specific monitoring scenarios.

    .PARAMETER InputObject
        Accepts data collector set objects from Get-DbaPfDataCollectorSet via pipeline input. Enables pipeline workflows for filtering and processing collector sets.
        Use this when you need to chain commands together, such as filtering collector sets before exporting them.

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

    .OUTPUTS
        System.IO.FileInfo

        Returns one FileInfo object for each exported XML template file. The file contains the complete configuration of the data collector set including counter selections, sampling intervals, and output settings.

        Properties:
        - Name: The filename of the exported template (e.g., 'System Correlation.xml')
        - FullName: The complete path to the exported XML file
        - Directory: The parent folder where the file was created
        - Length: File size in bytes
        - CreationTime: When the file was created
        - LastWriteTime: When the file was last modified
        - Extension: File extension (.xml)

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