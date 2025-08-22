function Invoke-DbaAzSqlDbTip {
    <#
    .SYNOPSIS
        Executes Microsoft's Azure SQL performance recommendations script against Azure SQL Database instances.

    .DESCRIPTION
        Executes Microsoft's Azure SQL Tips script against Azure SQL Database instances to identify performance optimization opportunities and design recommendations. This function runs the get-sqldb-tips.sql script developed by the Azure SQL Product Management team, which analyzes your database configuration, query patterns, and resource utilization to provide actionable improvement suggestions.

        The script examines database settings, index usage, query performance metrics, and configuration parameters to generate targeted recommendations with confidence percentages. Each tip includes detailed explanations and links to Microsoft documentation for implementation guidance.

        By default, the latest version of the tips script is automatically downloaded from the Microsoft GitHub repository at https://github.com/microsoft/azure-sql-tips. You can also specify a local copy using the -LocalFile parameter if you prefer to use a cached or customized version of the script.

    .PARAMETER SqlInstance
        The target Azure SQL instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        SQL Server Authentication and Azure Active Directory are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AzureDomain
        By default, this is set to database.windows.net In the event your AzureSqlDb is not on a database.windows.net domain,
        you can set a custom domain using the AzureDomain parameter. This tells Connect-DbaInstance to login to the
        database using the method that works best with Azure.

    .PARAMETER Tenant
        The TenantId for an Azure Instance.

        Default: (Get-DbatoolsConfigValue -FullName 'azure.tenantid')

    .PARAMETER LocalFile
        Specifies the path to a local file to run AzSqlTips from. This can be either the zip file release from GitHub or just the tips SQL script.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/microsoft/azure-sql-tips/releases

    .PARAMETER Database
        The database(s) to process.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER AllUserDatabases
        Run Azure SQL Tips against all user databases.

    .PARAMETER ReturnAllTips
        Sets the flag within the get-sqldb-tips.sql file to return all tips regardless of database state.

    .PARAMETER Compat100
        Uses the get-sqldb-tips-compat-level-100-only.sql script which is only suitable for database is using compatibility level 100

    .PARAMETER StatementTimeout
        Timeout in minutes.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, then AzSqlTips will be downloaded from the internet even if previously cached.

    .NOTES
        Tags: Azure, Database
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaAzSqlDbTip

    .EXAMPLE
        PS C:\> Invoke-DbaAzSqlDbTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -Database ImportantDb

        Runs the Azure SQL Tips script against the dbatools1.database.windows.net using the specified credentials for the ImportantDb.

    .EXAMPLE
        PS C:\> Invoke-DbaAzSqlDbTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -Database ImportantDb -ReturnAllTips

        Runs the Azure SQL Tips script against the dbatools1.database.windows.net using the specified credentials for the ImportantDb and
        will return all the tips regardless of database state.

    .EXAMPLE
        PS C:\> Invoke-DbaAzSqlDbTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -Database ImportantDb -LocalFile 'C:\temp\get-sqldb-tips.sql'

        Runs the Azure SQL Tips script that is available locally at 'C:\temp\get-sqldb-tips.sql' against the dbatools1.database.windows.net using the specified
        credentials for the ImportantDb and will return all the tips regardless of database state.

    .EXAMPLE
        PS C:\> Invoke-DbaAzSqlDbTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -ExcludeDatabase TestDb

        Runs the Azure SQL Tips script against all the databases on the dbatools1.database.windows.net using the specified credentials except for TestDb.

    .EXAMPLE
        PS C:\> Invoke-DbaAzSqlDbTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -AllUserDatabases

        Runs the Azure SQL Tips script against all the databases on the dbatools1.database.windows.net using the specified credentials.

    .EXAMPLE
        PS C:\> $cred = Get-Credential
        PS C:\> Invoke-DbaAzSqlDbTip -SqlInstance dbatools1.database.windows.net -SqlCredential $cred -Database ImportantDb

        Enter Azure AD username\password into Get-Credential, and then Invoke-DbaAzSqlDbTip will runs the Azure SQL Tips
        script against the ImportantDb database on the dbatools1.database.windows.net server using Azure AD.

    .EXAMPLE
        PS C:\> Invoke-DbaAzSqlDbTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -Database ImportantDb -Tenant GUID-GUID-GUID

        Run the Azure SQL Tips script against the ImportantDb database on the dbatools1.database.windows.net server specifying the Azure Tenant Id.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$AzureDomain = 'database.windows.net',
        [string]$Tenant,
        [ValidateScript( { Test-Path -Path $_ -PathType Leaf })]
        [string]$LocalFile,
        [String[]]$Database,
        [String[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [switch]$ReturnAllTips,
        [switch]$Compat100,
        [int]$StatementTimeout,
        [switch]$EnableException,
        [switch]$Force
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases"
            return
        }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'AzSqlTips'
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('AzSqlTips', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software AzSqlTips -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }

        # get the tips query code
        if ($Compat100) {
            $azTipsQuery = Get-Content (Join-DbaPath $localCachedCopy sqldb-tips 'get-sqldb-tips-compat-level-100-only.sql') -Raw
        } else {
            $azTipsQuery = Get-Content (Join-DbaPath $localCachedCopy sqldb-tips 'get-sqldb-tips.sql') -Raw
        }

        if ($ReturnAllTips) {
            # if ReturnAllTips is true set the variable to 1
            $azTipsQuery = ($azTipsQuery -replace '(?<=ReturnAllTips)(\D+)(\d+)', ('$1 1') )
        }

    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Message ('Connecting to {0}' -f $instance)

                $connSplat = @{
                    SqlInstance      = $instance
                    SqlCredential    = $SqlCredential
                    StatementTimeout = ($StatementTimeout * 60)
                    AzureDomain      = $AzureDomain
                    Tenant           = $Tenant
                }
                $connection = Connect-DbaInstance @connSplat

                if ($connection.DatabaseEngineType -ne 'SqlAzureDatabase') {
                    Stop-Function -Message ('{0} is not an Azure SQL Database - this function only works against Azure  SQL Databases' -f $instance) -Continue
                }

                if ($AllUserDatabases) {
                    $Database = ($connection.Databases | Where-Object name -ne 'Master').Name
                }

            } catch {
                $failedInstConn = $true

                if ($AllUserDatabases) {
                    Write-Warning -Message ("Could not connect at instance level to {0}, so we can't get the list of databases. You'll need to specify a list of databases with -Database." -f $_)
                    break
                }

                Write-Warning -Message ('Could not connect at instance level, so will try to connect to database. {0}' -f $_)

            }

            foreach ($db in $Database) {

                try {

                    Write-Message -Message ('Running Azure SQL Tips against {0}' -f $db)

                    if ($failedInstConn) {
                        Write-Message -Message ('Connecting to {0}.{1}' -f $instance, $db)
                        $connection = Connect-DbaInstance @connSplat -Database $db
                    }

                    Invoke-DbaQuery -SqlInstance $connection -Database $db -Query $azTipsQuery -EnableException:$EnableException | ForEach-Object {
                        [PSCustomObject]@{
                            ComputerName        = $connection.ComputerName
                            InstanceName        = $connection.Name
                            SqlInstance         = $connection.DomainInstanceName
                            Database            = $db
                            tip_id              = $PSItem.tip_id
                            description         = $PSItem.description
                            confidence_percent  = $PSItem.confidence_percent
                            additional_info_url = $PSItem.additional_info_url
                            details             = $PSItem.details
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to run AzSqlTips against Instance." -ErrorRecord $_ -Continue -Target $instance
                }
            }
        }
    }
}