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
        Specifies the package type to create: Dacpac (schema and data) or Bacpac (data only). Defaults to Dacpac.
        Use Dacpac when you need to capture database schema structure along with optional data for deployment scenarios.
        Use Bacpac when you only need to export and import data without schema changes.

    .PARAMETER Action
        Determines whether you're exporting from a database or publishing to a database.
        Use Export when extracting a package from an existing database for backup or migration purposes.
        Use Publish when deploying a package to create or update a target database.

    .PARAMETER PublishXml
        Path to a DAC publish profile XML file that contains deployment options and SQLCMD variables.
        These profiles are typically created in SQL Server Data Tools (SSDT) and control how the deployment behaves.
        When specified, the profile's settings override any DeployOptions specified in the Property parameter.

    .PARAMETER Property
        Hashtable of properties to configure the DAC options object, such as CommandTimeout or ExtractAllTableData.
        For Publish actions, use the DeployOptions key to set deployment behaviors like DropObjectsNotInSource or BlockOnPossibleDataLoss.
        Common properties include CommandTimeout for long operations and ExtractAllTableData when exporting data with schema.
        Example: @{CommandTimeout=0; DeployOptions=@{DropObjectsNotInSource=$true}}

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Dacpac
        Author: Kirill Kravtsov (@nvarscar), nvarscar.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDacOption

    .OUTPUTS
        Microsoft.SqlServer.Dac.DacExtractOptions (when Type=Dacpac and Action=Export)

        Returns a DacExtractOptions object for extracting schema and data from a database into a DAC package.
        Properties include ExtractAllTableData (boolean), CommandTimeout (int), and other extraction settings.

        Microsoft.SqlServer.Dac.DacExportOptions (when Type=Bacpac and Action=Export)

        Returns a DacExportOptions object for exporting data only (without schema) from a database into a BAC package.
        Properties include CommandTimeout (int) and other export-specific settings.

        Microsoft.SqlServer.Dac.PublishOptions (when Type=Dacpac and Action=Publish)

        Returns a PublishOptions object for publishing (deploying) a DAC package to a target database.
        Contains a DeployOptions property (Microsoft.SqlServer.Dac.DacDeployOptions) with settings like DropObjectsNotInSource (boolean) and BlockOnPossibleDataLoss (boolean).
        When a PublishXml profile is provided, DeployOptions are loaded from the profile file; otherwise DeployOptions can be set via the Property parameter.
        The GenerateDeploymentScript property (boolean) is initialized based on the Property parameter or defaults to false.

        Microsoft.SqlServer.Dac.DacImportOptions (when Type=Bacpac and Action=Publish)

        Returns a DacImportOptions object for importing (deploying) a BAC package data into a target database.
        Properties include CommandTimeout (int) and other import-specific settings.

        All returned objects can be configured by setting their properties directly or by passing a Property hashtable at creation time. When using PublishOptions with a PublishXml profile, the profile's settings override Property parameter values.

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Export
        PS C:\> $options.ExtractAllTableData = $true
        PS C:\> $options.CommandTimeout = 0
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -Options $options

        Uses DacOption object to set the CommandTimeout to 0 then extracts the dacpac for SharePoint_Config on sql2016 to C:\temp\SharePoint_Config.dacpac including all table data.

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Export -Property @{ExtractAllTableData=$true;CommandTimeout=0}
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -Options $options

        Creates a pre-initialized DacOption object and uses it to extrac a DacPac from the database.

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
        [hashtable]$Property,
        [switch]$EnableException
    )
    process {
        if ($PScmdlet.ShouldProcess("$type", "Creating New DacOptions of $action")) {
            function New-DacObject {
                Param ([String]$TypeName, [hashtable]$Property = $Property)

                $dacOptionSplat = @{TypeName = $TypeName }
                if ($Property) { $dacOptionSplat.Property = $Property }
                try {
                    New-Object @dacOptionSplat -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Could not generate object $TypeName" -ErrorRecord $_
                }
            }

            # Pick proper option object depending on type and action
            if ($Action -eq 'Export') {
                if ($Type -eq 'Dacpac') {
                    New-DacObject -TypeName Microsoft.SqlServer.Dac.DacExtractOptions
                } elseif ($Type -eq 'Bacpac') {
                    New-DacObject -TypeName Microsoft.SqlServer.Dac.DacExportOptions
                }
            } elseif ($Action -eq 'Publish') {
                if ($Type -eq 'Dacpac') {
                    $output = New-DacObject -TypeName Microsoft.SqlServer.Dac.PublishOptions
                    if ($PublishXml) {
                        try {
                            $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($PublishXml)
                            $output.DeployOptions = $dacProfile.DeployOptions
                        } catch {
                            Stop-Function -Message "Could not load profile." -ErrorRecord $_
                            return
                        }
                    } else {
                        $output.DeployOptions = if ($Property -and 'DeployOptions' -in $Property.Keys) {
                            New-DacObject -TypeName Microsoft.SqlServer.Dac.DacDeployOptions -Property $Property.DeployOptions
                        } else {
                            New-DacObject -TypeName Microsoft.SqlServer.Dac.DacDeployOptions -Property @{ }
                        }
                    }
                    if ($null -eq $Property.GenerateDeploymentScript) {
                        $output.GenerateDeploymentScript = $false
                    }
                    $output
                } elseif ($Type -eq 'Bacpac') {
                    New-DacObject -TypeName Microsoft.SqlServer.Dac.DacImportOptions
                }
            }
        }
    }
}