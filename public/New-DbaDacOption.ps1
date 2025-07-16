function New-DbaDacOption {
    <#
    .SYNOPSIS
        Creates a new sqlpackage-compatible options object for dacpac/bacpac operations

    .DESCRIPTION
        Creates a new sqlpackage-compatible options object that can be used during DacPackage extract/export operations.
        This replaces the deprecated Microsoft.SqlServer.Dac classes with a custom object that works with sqlpackage command-line tool.

        For sqlpackage parameters and properties, refer to:
        https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-extract
        https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-publish

    .PARAMETER Type
        Selecting the type of the export: Dacpac (default) or Bacpac.

    .PARAMETER Action
        Choosing an intended action: Publish or Export.

    .PARAMETER PublishXml
        Specifies the publish profile which will include options and sqlCmdVariables.

    .PARAMETER Property
        A Hashtable that would be used to initialize Options object properties.
        Common properties include:
        - ExtractAllTableData: Include table data in dacpac (default: false)
        - CommandTimeout: Command timeout in seconds (default: 30)
        - VerifyExtraction: Verify the dacpac after extraction (default: true)
        - Storage: Memory or File storage mode (default: File)

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Dacpac, sqlpackage
        Author: Kirill Kravtsov (@nvarscar), nvarscar.wordpress.com
        Updated: 2025 - Converted to use sqlpackage instead of deprecated DAC classes

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDacOption

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Export
        PS C:\> $options.ExtractAllTableData = $true
        PS C:\> $options.CommandTimeout = 0
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -DacOption $options

        Creates a sqlpackage-compatible options object and sets properties for extracting a dacpac with all table data.

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Export -Property @{ExtractAllTableData=$true;CommandTimeout=0}
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -DacOption $options

        Creates a pre-initialized DacOption object using sqlpackage parameters.

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Publish
        PS C:\> $options.DropObjectsNotInSource = $true
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2016 -Database DB1 -DacOption $options -Path c:\temp\db.dacpac

        Creates a sqlpackage-compatible options object for publishing a dacpac.

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
        if ($PScmdlet.ShouldProcess("$type", "Creating New sqlpackage-compatible options for $action")) {

            # Create a custom object that mimics the old DAC options but works with sqlpackage
            $options = [PSCustomObject]@{
                Type = $Type
                Action = $Action
                PSTypeName = "DbaTools.sqlpackage.Options"
            }

            # Set default properties based on action and type
            if ($Action -eq 'Export') {
                if ($Type -eq 'Dacpac') {
                    # Default dacpac extract options
                    $options | Add-Member -NotePropertyName 'ExtractAllTableData' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'CommandTimeout' -NotePropertyValue 30
                    $options | Add-Member -NotePropertyName 'VerifyExtraction' -NotePropertyValue $true
                    $options | Add-Member -NotePropertyName 'Storage' -NotePropertyValue 'File'
                    $options | Add-Member -NotePropertyName 'ExtractReferencedServerScopedElements' -NotePropertyValue $true
                    $options | Add-Member -NotePropertyName 'ExtractApplicationScopedObjectsOnly' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'IgnoreExtendedProperties' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'IgnorePermissions' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'IgnoreUserLoginMappings' -NotePropertyValue $false
                } elseif ($Type -eq 'Bacpac') {
                    # Default bacpac export options
                    $options | Add-Member -NotePropertyName 'CommandTimeout' -NotePropertyValue 30
                    $options | Add-Member -NotePropertyName 'Storage' -NotePropertyValue 'File'
                    $options | Add-Member -NotePropertyName 'VerifyFullTextDocumentTypesSupported' -NotePropertyValue $false
                }
            } elseif ($Action -eq 'Publish') {
                if ($Type -eq 'Dacpac') {
                    # Default dacpac publish options
                    $options | Add-Member -NotePropertyName 'CommandTimeout' -NotePropertyValue 30
                    $options | Add-Member -NotePropertyName 'GenerateDeploymentScript' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'GenerateDeploymentReport' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'BlockOnPossibleDataLoss' -NotePropertyValue $true
                    $options | Add-Member -NotePropertyName 'DropObjectsNotInSource' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'DoNotDropObjectTypes' -NotePropertyValue @()
                    $options | Add-Member -NotePropertyName 'ExcludeObjectTypes' -NotePropertyValue @()
                    $options | Add-Member -NotePropertyName 'IgnorePermissions' -NotePropertyValue $false
                    $options | Add-Member -NotePropertyName 'IgnoreUserLoginMappings' -NotePropertyValue $false

                    # Handle publish profile XML
                    if ($PublishXml) {
                        try {
                            if (Test-Path $PublishXml) {
                                [xml]$profileXml = Get-Content $PublishXml
                                $deployOptions = $profileXml.Project.PropertyGroup
                                if ($deployOptions) {
                                    foreach ($prop in $deployOptions.ChildNodes) {
                                        if ($prop.Name -and $prop.InnerText) {
                                            $options | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.InnerText -Force
                                        }
                                    }
                                }
                            }
                        } catch {
                            if ($EnableException) {
                                throw "Could not load publish profile: $_"
                            } else {
                                Write-Warning "Could not load publish profile: $_"
                            }
                        }
                    }
                } elseif ($Type -eq 'Bacpac') {
                    # Default bacpac import options
                    $options | Add-Member -NotePropertyName 'CommandTimeout' -NotePropertyValue 30
                    $options | Add-Member -NotePropertyName 'DatabaseEdition' -NotePropertyValue 'Default'
                    $options | Add-Member -NotePropertyName 'DatabaseServiceObjective' -NotePropertyValue 'Default'
                }
            }

            # Apply custom properties if provided
            if ($Property) {
                foreach ($key in $Property.Keys) {
                    $options | Add-Member -NotePropertyName $key -NotePropertyValue $Property[$key] -Force
                }
            }

            # Add a method to convert options to sqlpackage parameters
            $options | Add-Member -MemberType ScriptMethod -Name 'ToSqlPackageParameters' -Value {
                $params = @()

                foreach ($prop in $this.PSObject.Properties) {
                    if ($prop.Name -notin @('Type', 'Action', 'PSTypeName')) {
                        $value = $prop.Value
                        if ($value -is [bool]) {
                            $value = $value.ToString().ToLower()
                        } elseif ($value -is [array]) {
                            $value = $value -join ','
                        }
                        $params += "/p:$($prop.Name)=$value"
                    }
                }

                return $params -join ' '
            }

            return $options
        }
    }
}