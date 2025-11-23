function New-DbaDiagnosticAdsNotebook {
    <#
    .SYNOPSIS
        Generates a Jupyter Notebook containing Glenn Berry's SQL Server diagnostic queries for Azure Data Studio

    .DESCRIPTION
        Converts Glenn Berry's well-known SQL Server diagnostic queries into a Jupyter Notebook (.ipynb) file that can be opened and executed in Azure Data Studio. The function automatically detects your SQL Server version or accepts a target version parameter, then creates a notebook with version-specific diagnostic queries formatted as executable cells. Each query includes descriptive markdown explaining what it measures and why it's useful for performance troubleshooting and health monitoring.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to the default instance on localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER TargetVersion
        Specifies the SQL Server version to generate diagnostic queries for when not connecting to a live instance. Use this when creating notebooks for offline analysis or different environments than your current connection.
        Must be one of "2005", "2008", "2008R2", "2012", "2014", "2016", "2016SP2", "2017", "2019", "2022", "AzureSQLDatabase". Cannot be used together with SqlInstance parameter.

    .PARAMETER Path
        Specifies the full file path where the Jupyter Notebook (.ipynb file) will be created. The directory must exist and you must have write permissions to the location.
        The generated notebook can be opened in Azure Data Studio or any Jupyter-compatible environment for executing Glenn Berry's diagnostic queries.

    .PARAMETER IncludeDatabaseSpecific
        Includes database-level diagnostic queries in addition to the default instance-level queries. These queries examine database-specific performance metrics, index usage, and database settings.
        Use this when you need detailed analysis of individual databases rather than just server-wide diagnostics. Defaults to $false.

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
        [ValidateSet("2005", "2008", "2008R2", "2012", "2014", "2016", "2016SP2", "2017", "2019", "2022", "AzureSQLDatabase")]
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
                "16.0"  = "2022"
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

        $diagnosticScriptPath = Get-ChildItem -Path "$($script:PSModuleRoot)\bin\diagnosticquery\" -Filter "SQLServerDiagnosticQueries_$($TargetVersion).sql" | Select-Object -First 1

        if (-not $diagnosticScriptPath) {
            Stop-Function -Message "No diagnostic queries available for `$TargetVersion = $TargetVersion"
            return
        }

        $cells = @()

        Invoke-DbaDiagnosticQueryScriptParser $diagnosticScriptPath.FullName | Where-Object { -not $_.DBSpecific -or $IncludeDatabaseSpecific } | ForEach-Object {
            $cells += @{cell_type = "markdown"; source = "## $($_.QueryName)`n`n$($_.Description)"; metadata = "" }
            $cells += @{cell_type = "code"; source = $_.Text; metadata = "" }
        }

        $outputObject = @{
            metadata       = @{
                kernelspec    = @{
                    name         = "SQL"
                    display_name = "SQL"
                    language     = "sql"
                }
                language_info = @{
                    name    = "sql"
                    version = ""
                }
            }
            nbformat_minor = 2
            nbformat       = 4
            cells          = $cells
        }

        [IO.File]::WriteAllLines($Path, (ConvertTo-Json -InputObject $outputObject -Depth 3))
        Get-ChildItem -Path $Path
    }
}