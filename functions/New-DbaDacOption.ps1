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

    .PARAMETER PublishXml
        Specifies the publish profile which will include options and sqlCmdVariables.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Database, Dacpac
        Author: Kirill Kravtsov (@nvarscar), nvarscar.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDacOption

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Export
        PS C:\> $options.ExtractAllTableData = $true
        PS C:\> $options.CommandTimeout = 0
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -Options $options

        Uses DacOption object to set the CommandTimeout to 0 then extracts the dacpac for SharePoint_Config on sql2016 to C:\temp\SharePoint_Config.dacpac including all table data.

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Publish
        PS C:\> $options.DeployOptions.DropObjectsNotInSource = $true
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2016 -Database DB1 -Options $options -Path c:\temp\db.dacpac

        Uses DacOption object to set Deployment Options and publish the db.dacpac dacpac file as DB1 on sql2016

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [Parameter(Mandatory)]
        [ValidateSet('Publish', 'Export')]
        [string]$Action,
        [string]$PublishXml,
        [switch]$EnableException
    )
    if ($PScmdlet.ShouldProcess("$type", "Creating New DacOptions of $action")) {
        if (-not $script:core) {
            $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"
            if ((Test-Path $dacfxPath) -eq $false) {
                Stop-Function -Message 'Dac Fx library not found.' -EnableException $EnableException
                return
            } else {
                try {
                    Add-Type -Path $dacfxPath
                    Write-Message -Level Verbose -Message "Dac Fx loaded."
                } catch {
                    Stop-Function -Message 'No usable version of Dac Fx found.' -ErrorRecord $_
                    return
                }
            }
        }

        # Pick proper option object depending on type and action
        if ($Action -eq 'Export') {
            if ($Type -eq 'Dacpac') {
                New-Object -TypeName Microsoft.SqlServer.Dac.DacExtractOptions
            } elseif ($Type -eq 'Bacpac') {
                New-Object -TypeName Microsoft.SqlServer.Dac.DacExportOptions
            }
        } elseif ($Action -eq 'Publish') {
            if ($Type -eq 'Dacpac') {
                $output = New-Object -TypeName Microsoft.SqlServer.Dac.PublishOptions
                if ($PublishXml) {
                    try {
                        $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($PublishXml)
                        $output.DeployOptions = $dacProfile.DeployOptions
                    } catch {
                        Stop-Function -Message "Could not load profile." -ErrorRecord $_
                        return
                    }
                } else {
                    $output.DeployOptions = New-Object -TypeName Microsoft.SqlServer.Dac.DacDeployOptions
                }
                $output.GenerateDeploymentScript = $false
                $output
            } elseif ($Type -eq 'Bacpac') {
                New-Object -TypeName Microsoft.SqlServer.Dac.DacImportOptions
            }
        }
    }
}