function Export-DbaPfDataCollectionSetTemplate {
 <#
    .SYNOPSIS
    Exports a new Data Collector Set XML Template

    .DESCRIPTION
    Exports a Data Collector Set XML Template from Get-DbaPfDataCollectorSet. Exports to "$home\Documents\Performance Monitor Templates" by default

    .PARAMETER ComputerName
    The target computer. Defaults to localhost.

    .PARAMETER Credential
     Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER CollectorSet
    The Name of the collector set(s) to export

    .PARAMETER Path
    The path to export the file. Can be .xml or directory.

    .PARAMETER InputObject
    Enables piping data collector sets

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Export-DbaPfDataCollectionSetTemplate

    .EXAMPLE
    Export-DbaPfDataCollectionSetTemplate -ComputerName sql2017 -Path C:\temp\pf
    Exports all data collector sets from to the C:\temp\pf folder.

    .EXAMPLE
    Get-DbaPfDataCollectorSet ComputerName sql2017 -CollectorSet 'System Correlation' | Export-DbaPfDataCollectionSetTemplate -Path C:\temp
    Exports the 'System Correlation' data collector set from sql2017 to C:\temp

#>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [string]$Path = "$home\Documents\Performance Monitor Templates",
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
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
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet"
                return
            }
            
            $csname = Remove-InvalidFileNameChars -Name $object.Name
            
            if ($path.EndsWith(".xml")) {
                $filename = $path
            }
            else {
                $filename = "$path\$csname.xml"
                if (-not (Test-Path -Path $path)) {
                    $null = New-Item -Type Directory -Path $path    
                }
            }
            Write-Message -Level Verbose -Message "Wrote $csname to $filename"
            Set-Content -Path $filename -Value $object.Xml -Encoding Unicode
            Get-ChildItem -Path $filename
        }
    }
}