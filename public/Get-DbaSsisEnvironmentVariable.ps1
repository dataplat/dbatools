function Get-DbaSsisEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves environment variables from SSIS Catalog with decrypted sensitive values

    .DESCRIPTION
        Retrieves all variables from specified SSIS environments stored in the SSISDB catalog database. All sensitive values are automatically decrypted and returned in plaintext for configuration management and troubleshooting purposes.

        This function queries the SSISDB database directly using symmetric keys and certificates to decrypt sensitive variable values, bypassing the standard SMO limitations that only return encrypted values. This is essential for SSIS environment configuration audits, parameter validation, and deployment verification.

        The function communicates directly with SSISDB database - the SQL Server Integration Services service isn't queried. Each parameter (besides SqlInstance and SqlCredential) acts as a filter to include or exclude specific environments or folders.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.
        This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Environment
        Specifies one or more SSIS environment names to retrieve variables from within the SSISDB catalog.
        Use this when you need variables from specific environments like 'DEV', 'QA', or 'PROD' rather than all environments in a folder.

    .PARAMETER EnvironmentExclude
        Excludes specified SSIS environment names from the results when retrieving variables.
        Most effective when used without the Environment parameter to get all environments except those specified.
        Helpful when you want to audit all non-production environments or exclude specific environments from configuration reviews.

    .PARAMETER Folder
        Specifies one or more SSISDB catalog folder names that contain the environments you want to query.
        Use this to limit your search to specific project folders when you have environments organized by application or team.
        If omitted, the function searches all folders in the SSISDB catalog.

    .PARAMETER FolderExclude
        Excludes specified SSISDB catalog folder names from the search when retrieving environment variables.
        Most effective when used without the Folder parameter to search all folders except those specified.
        Useful when you want to exclude test folders, archived projects, or specific application folders from your audit.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SSIS, SSISDB, Variable
        Author: Bartosz Ratajczyk (@b_ratajczyk)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSsisEnvironmentVariable

    .EXAMPLE
        PS C:\> Get-DbaSsisEnvironmentVariable -SqlInstance localhost -Environment DEV -Folder DWH_ETL

        Gets variables of 'DEV' environment located in 'DWH_ETL' folder on 'localhost' Server

    .EXAMPLE
        PS C:\> Get-DbaSsisEnvironmentVariable -SqlInstance localhost -Environment DEV -Folder DWH_ETL, DEV2, QA

        Gets variables of 'DEV' environment(s) located in folders 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

    .EXAMPLE
        PS C:\> Get-DbaSsisEnvironmentVariable -SqlInstance localhost -Environment DEV -FolderExclude DWH_ETL, DEV2, QA

        Gets variables of 'DEV' environments located in folders other than 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

    .EXAMPLE
        PS C:\> Get-DbaSsisEnvironmentVariable -SqlInstance localhost -Environment DEV, PROD -Folder DWH_ETL, DEV2, QA

        Gets variables of 'DEV' and 'PROD' environment(s) located in folders 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

    .EXAMPLE
        PS C:\> Get-DbaSsisEnvironmentVariable -SqlInstance localhost -EnvironmentExclude DEV, PROD -Folder DWH_ETL, DEV2, QA

        Gets variables of environments other than 'DEV' and 'PROD' located in folders 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

    .EXAMPLE
        PS C:\> Get-DbaSsisEnvironmentVariable -SqlInstance localhost -EnvironmentExclude DEV, PROD -FolderExclude DWH_ETL, DEV2, QA

        Gets variables of environments other than 'DEV' and 'PROD' located in folders other than 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

    .EXAMPLE
        PS C:\> 'localhost' | Get-DbaSsisEnvironmentVariable -EnvironmentExclude DEV, PROD

        Gets all SSIS environments except 'DEV' and 'PROD' from 'localhost' server. The server name comes from pipeline

    .EXAMPLE
        PS C:\> 'SRV1', 'SRV3' | Get-DbaSsisEnvironmentVariable

        Gets all SSIS environments from 'SRV1' and 'SRV3' servers. The server's names come from pipeline

    .EXAMPLE
        PS C:\> 'SRV1', 'SRV2' | Get-DbaSsisEnvironmentVariable DEV | Out-GridView

        Gets all variables from 'DEV' Environment(s) on servers 'SRV1' and 'SRV2' and outputs it as the GridView.
        The server names come from the pipeline.

    .EXAMPLE
        PS C:\> 'localhost' | Get-DbaSsisEnvironmentVariable -EnvironmentExclude DEV, PROD | Select-Object -Property Name, Value | Where-Object {$_.Name -match '^a'} | Out-GridView

        Gets all variables from Environments other than 'DEV' and 'PROD' on 'localhost' server,
        selects Name and Value properties for variables that names start with letter 'a' and outputs it as the GridView

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Environment,
        [object[]]$EnvironmentExclude,
        [object[]]$Folder,
        [object[]]$FolderExclude,
        [switch]$EnableException
    )
    process {
        if ($PSVersionTable.PSEdition -eq "Core") {
            Stop-Function -Message "This command is not supported on Linux or macOS"
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $server
            } catch {
                Stop-Function -Message "Can't load server" -Target $instance -ErrorRecord $_
                return
            }

            Write-Message -Message "Fetching SSIS Catalog and its folders" -Level Verbose
            $catalog = $ssis.Catalogs | Where-Object { $_.Name -eq "SSISDB" }

            # get all folders names if none provided
            if ($null -eq $Folder) {
                $searchFolders = $catalog.Folders.Name
            } else {
                $searchFolders = $Folder
            }

            # filter unwanted folders
            if ($FolderExclude) {
                $searchFolders = $searchFolders | Where-Object { $_ -notin $FolderExclude }
            }

            if ($null -eq $searchFolders) {
                Write-Message -Message "Instance: $instance > -Folder and -FolderExclude filters return an empty collection. Skipping" -Level Warning
            } else {
                foreach ($f in $searchFolders) {
                    # get all environments names if none provided
                    if ($null -eq $Environment) {
                        $searchEnvironments = $catalog.Folders.Environments.Name
                    } else {
                        $searchEnvironments = $Environment
                    }

                    #filter unwanted environments
                    if ($EnvironmentExclude) {
                        $searchEnvironments = $searchEnvironments | Where-Object { $_ -notin $EnvironmentExclude }
                    }

                    if ($null -eq $searchEnvironments) {
                        Write-Message -Message "Instance: $instance / Folder: $f > -Environment and -EnvironmentExclude filters return an empty collection. Skipping." -Level Warning
                    } else {
                        $Environments = $catalog.Folders[$f].Environments | Where-Object { $_.Name -in $searchEnvironments }

                        foreach ($e in $Environments) {
                            #encryption handling
                            $encKey = 'MS_Enckey_Env_' + $e.EnvironmentId
                            $encCert = 'MS_Cert_Env_' + $e.EnvironmentId

                            <#
                            SMO does not return sensitive values (gets data from catalog.environment_variables)
                            We have to manually query internal.environment_variables instead and use symmetric keys
                            within T-SQL code
                            #>

                            $sql = @"
                            OPEN SYMMETRIC KEY $encKey DECRYPTION BY CERTIFICATE $encCert;

                            SELECT
                                ev.variable_id,
                                ev.name,
                                ev.description,
                                ev.type,
                                ev.sensitive,
                                value = ev.value,
                                ev.sensitive_value,
                                ev.base_data_type,
                                decrypted = decrypted.value
                            FROM internal.environment_variables ev

                                CROSS APPLY (
                                    SELECT
                                        value   = CASE base_data_type
                                                    WHEN 'nvarchar' THEN CONVERT(NVARCHAR(MAX), DECRYPTBYKEY(sensitive_value))
                                                    WHEN 'bit' THEN CONVERT(NVARCHAR(MAX), CONVERT(bit, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'datetime' THEN CONVERT(NVARCHAR(MAX), CONVERT(datetime2(0), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'single' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'float' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'decimal' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'tinyint' THEN CONVERT(NVARCHAR(MAX), CONVERT(tinyint, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'smallint' THEN CONVERT(NVARCHAR(MAX), CONVERT(smallint, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'int' THEN CONVERT(NVARCHAR(MAX), CONVERT(INT, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'bigint' THEN CONVERT(NVARCHAR(MAX), CONVERT(bigint, DECRYPTBYKEY(sensitive_value)))
                                                END
                                ) decrypted
                            WHERE environment_id = $($e.EnvironmentId);
                            CLOSE SYMMETRIC KEY $encKey;
"@

                            $ssisVariables = $server.Query($sql, "SSISDB")

                            foreach ($variable in $ssisVariables) {
                                if ($variable.sensitive -eq $true) {
                                    $value = $variable.decrypted
                                } else {
                                    $value = $variable.value
                                }

                                [PSCustomObject]@{
                                    ComputerName = $server.ComputerName
                                    InstanceName = $server.ServiceName
                                    SqlInstance  = $server.DomainInstanceName
                                    Folder       = $f
                                    Environment  = $e.Name
                                    Id           = $variable.variable_id
                                    Name         = $variable.Name
                                    Description  = $variable.description
                                    Type         = $variable.type
                                    IsSensitive  = $variable.sensitive
                                    BaseDataType = $variable.base_data_type
                                    Value        = $value
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}