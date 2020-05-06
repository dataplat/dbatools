function New-DbaDiagnosticAdsNotebook {
    <#
    .SYNOPSIS
        Creates a new Diagnostic Jupyter Notebook for use with Azure Data Studio

    .DESCRIPTION
        Creates a new Jupyter Notebook for use with Azure Data Studio, based on Glenn Berry's
        popular Diagnostic queries

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to the default instance on localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER TargetVersion
        If you are not creating the notebook for a specific instance of SQL Server, you can specify the version that you want to create the notebook for.
        Must be one of "2005", "2008", "2008R2", "2012", "2014", "2016", "2016SP2", "2017", "2019", "AzureSQLDatabase"

    .PARAMETER Path
        Specifies the output path of the Jupyter Notebook

    .PARAMETER IncludeDatabaseSpecific
        If this switch is enabled, the notebook will also include database-specific queries. Defaults to $false.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, GlennBerry, Notebooks, AzureDataStudio
        Author: Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDiagnosticAdsNotebook

    .EXAMPLE
        PS C:\> New-DbaDiagnosticAdsNotebook -SqlInstance localhost -Path c:\temp\myNotebook.ipynb

        Creates a new Jupyter Notebook named "myNotebook" based on the version of diagnostic queries found at localhost

    .EXAMPLE
        PS C:\> New-DbaDiagnosticAdsNotebook -TargetVersion 2016SP2 -Path c:\temp\myNotebook.ipynb

        Creates a new Jupyter Notebook named "myNotebook" based on the version "2016SP2" of diagnostic queries

    .EXAMPLE
        PS C:\> New-DbaDiagnosticAdsNotebook -TargetVersion 2017 -Path c:\temp\myNotebook.ipynb -IncludeDatabaseSpecific

        Creates a new Jupyter Notebook named "myNotebook" based on the version "2017" of diagnostic queries, including database-specific queries
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param(
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("2005", "2008", "2008R2", "2012", "2014", "2016", "2016SP2", "2017", "2019", "AzureSQLDatabase")]
        [String]$TargetVersion,
        [parameter(Mandatory = $true)]
        [String]$Path,
        [switch]$IncludeDatabaseSpecific,
        [switch]$EnableException
    )
    process {
        # validate input parameters: you cannot provide $TargetVersion and $SqlInstance
        # together. If you specify a SqlInstance, version will be determined from metadata
        if (-not $TargetVersion -and -not $SqlInstance) {
            Stop-Function -Message "At least one of $SqlInstance and $TargetVersion must be provided"
            return
        } elseif ((-not (-not $TargetVersion)) -and -not (-not $SqlInstance)) {
            Stop-Function -Message "Cannot provide both $SqlInstance and $TargetVersion"
            return
        }

        if (-not $TargetVersion) {
            $versionQuery = "
                SELECT SERVERPROPERTY('ProductMajorVersion') AS ProductMajorVersion,
                SERVERPROPERTY('ProductMinorVersion') AS ProductMinorVersion,
                SERVERPROPERTY('ProductLevel') AS ProductLevel,
                SERVERPROPERTY('Edition') AS Edition"

            $versions = @{
                "9.0"   = "2005"
                "10.0"  = "2008"
                "10.50" = "2008R2"
                "11.0"  = "2012"
                "12.0"  = "2014"
                "13.0"  = "2016"
                "14.0"  = "2017"
                "15.0"  = "2019"
            }

            try {
                $ServerInfo = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Query $versionQuery
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
                return
            }

            if ($ServerInfo.Edition -eq "SQL Azure") {
                $TargetVersion = "AzureSQLDatabase"
            } else {
                $TargetVersion = $versions["$($ServerInfo.ProductMajorVersion).$($ServerInfo.ProductMinorVersion)"]

                if ($TargetVersion -eq "2016" -and $ServerInfo.ProductLevel -eq "SP2") {
                    $TargetVersion += "SP2"
                }
            }
        }

        $diagnosticScriptPath = Get-ChildItem -Path "$($script:PSModuleRoot)\bin\diagnosticquery\" -Filter "SQLServerDiagnosticQueries_$($TargetVersion)_??????.sql" | Select-Object -First 1

        if (-not $diagnosticScriptPath) {
            Stop-Function -Message "No diagnostic queries available for `$TargetVersion = $TargetVersion"
            return
        }

        $cells = @()

        Invoke-DbaDiagnosticQueryScriptParser $diagnosticScriptPath.FullName | Where-Object { -not $_.DBSpecific -or $IncludeDatabaseSpecific } | ForEach-Object {
            $cells += [pscustomobject]@{cell_type = "markdown"; source = "## $($_.QueryName)`n`n$($_.Description)" }
            $cells += [pscustomobject]@{cell_type = "code"; source = $_.Text }
        }

        $preamble = '
        {
            "metadata": {
                "kernelspec": {
                    "name": "SQL",
                    "display_name": "SQL",
                    "language": "sql"
                },
                "language_info": {
                    "name": "sql",
                    "version": ""
                }
            },
            "nbformat_minor": 2,
            "nbformat": 4,
            "cells":
        '

        $preamble | Out-File $Path
        $cells | ConvertTo-Json | Out-File -FilePath $Path -Append
        "}}" | Out-File -FilePath $Path -Append
        Get-ChildItem -Path $Path
    }
}