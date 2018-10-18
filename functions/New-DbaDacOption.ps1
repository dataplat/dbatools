function New-DbaDacOption {
    <#
    .SYNOPSIS
        Creates a new Microsoft.SqlServer.Dac.DacExtractOptions/DacExportOptions object depending on the chosen Type

    .DESCRIPTION
        Creates a new Microsoft.SqlServer.Dac.DacExtractOptions/DacExportOptions object that can be used during DacPackage extract. Basically saves you the time from remembering the SMO assembly name ;)

        See:
        https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.dac.dacexportoptions.aspx
        https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.dac.dacextractoptions.aspx
        for more information
        
    .PARAMETER Type
        Selecting the type of the export: Dacpac (default) or Bacpac.
        
    .PARAMETER Action
        Choosing an intended action: Publish or Export.

    .NOTES
        Tags: Migration, Database, Dacpac
        Author: Kirill Kravtsov (@nvarscar), nvarscar.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaScriptingOption

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac
        PS C:\> $options.ExtractAllTableData = $true
        PS C:\> $options.CommandTimeout = 0
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -Options

        Uses DacOption object to set the CommandTimeout to 0 then extracts the dacpac for SharePoint_Config on sql2016 to C:\temp\SharePoint_Config.dacpac including all table data.

#>
    Param (
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [Parameter(Mandatory)]
        [ValidateSet('Publish', 'Export')]
        [string]$Action
    )
    $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"
    if ((Test-Path $dacfxPath) -eq $false) {
        Stop-Function -Message 'Dac Fx library not found.' -EnableException $EnableException
        return
    }
    else {
        try {
            Add-Type -Path $dacfxPath
            Write-Message -Level Verbose -Message "Dac Fx loaded."
        }
        catch {
            Stop-Function -Message 'No usable version of Dac Fx found.' -ErrorRecord $_
            return
        }
    }
    # Pick proper option object depending on type and action
    if ($Action -eq 'Export') {
        if ($Type -eq 'Dacpac') {
            New-Object -TypeName Microsoft.SqlServer.Dac.DacExtractOptions
        }
        elseif ($Type -eq 'Bacpac') {
            New-Object -TypeName Microsoft.SqlServer.Dac.DacExportOptions
        }
    }
    elseif ($Action -eq 'Publish') {
        if ($Type -eq 'Dacpac') {
            $output = New-Object -TypeName Microsoft.SqlServer.Dac.PublishOptions
            $output.DeployOptions = New-Object -TypeName Microsoft.SqlServer.Dac.DacDeployOptions
            $output.GenerateDeploymentScript = $false
            $output
        }
        elseif ($Type -eq 'Bacpac') {
            New-Object -TypeName Microsoft.SqlServer.Dac.DacImportOptions
        }
    }
}
