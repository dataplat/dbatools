function Invoke-DbaDbAzSqlTips {
    <#
    .SYNOPSIS
        Runs the get-sqldb-tips.sql script from the Microsoft SQL PM team against an Azure SQL Database.

    .DESCRIPTION
        Executes the get-sqldb-tips.sql script against an Azure SQL Database to collect tips for improving database
        design, health and performance.

        Tips are written by the Azure SQL PM team and you can get more details about what is included here:
        https://github.com/microsoft/azure-sql-tips

    .PARAMETER SqlInstance
        The target Azure SQL instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        SQL Server Authentication and Azure Active Directory are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER AllUserDatabases
        Run Azure SQL Tips against all user databases.

    .PARAMETER StatementTimeout
        Timeout in minutes.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Azure, Database
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaAzSqlTips

    .EXAMPLE
        PS C:\> Invoke-DbaDbAzSqlTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -Database ImportantDb

        Runs the Azure SQL Tips script against the dbatools1.database.windows.net using the specified credentials for the ImportantDb.

    .EXAMPLE
        PS C:\> Invoke-DbaDbAzSqlTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -ExcludeDatabase TestDb

        Runs the Azure SQL Tips script against all the databases on the dbatools1.database.windows.net using the specified credentials except for TestDb.

    .EXAMPLE
        PS C:\> Invoke-DbaDbAzSqlTip -SqlInstance dbatools1.database.windows.net -SqlCredential (Get-Credential) -AllUserDatabases

        Runs the Azure SQL Tips script against all the databases on the dbatools1.database.windows.net using the specified credentials.

    .EXAMPLE
        PS C:\> $cred = Get-Credential
        PS C:\> Invoke-DbaDbAzSqlTip -SqlInstance dbatools1.database.windows.net -SqlCredential $cred -Database ImportantDb

        Enter Azure AD username\password into Get-Credential, and then Invoke-DbaDbAzSqlTip will runs the Azure SQL Tips
        script against the ImportantDb database on the dbatools1.database.windows.net server using Azure AD.


    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String[]]$Database,
        [String[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [switch]$JSONOutput,
        [switch]$ReturnAllTips,
        [int]$StatementTimeout,
        [switch]$EnableException
    )

    begin {

        if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases"
            return
        }

        # get the tips query code
        $azTipsQuery = Get-Content "$PSScriptRoot\..\bin\aztips\get-sqldb-tips.sql" -Raw

        if ($ReturnAllTips) {

            # if ReturnAllTips is true set the variable to 1
            $azTipsQuery = ($azTipsQuery -replace '(?<=ReturnAllTips)(\D+)(\d+)', ('$1 1') )

        }

    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-PSFMessage -Level Output -Message ('Connecting to {0}' -f $instance)

                $connection = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -StatementTimeout ($StatementTimeout * 60)

                if ($AllUserDatabases) {
                    $Database = ($connection.Databases | Where-Object name -ne 'Master').Name
                }

            } catch {
                $failedInstConn = $true

                if ($AllUserDatabases) {
                    Write-PSFMessage -Level Warning -Message ("Could not connect at instance level to {0}, so we can't get the list of databases. You'll need to specify a list of databases with -Database." -f $_)
                    break
                }

                Write-PSFMessage -Level Warning -Message ('Could not connect at instance level, so will try to connect to database. {0}' -f $_)

            }

            # all dbs?
            foreach ($db in $Database) {

                Write-PSFMessage -Level Output -Message ('Running Azure SQL Tips against {0}' -f $db)

                if ($failedInstConn) {
                    Write-PSFMessage -Level Output -Message ('Connecting to {0}.{1}' -f $instance, $db)
                    $connection = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -StatementTimeout $StatementTimeout -Database $db
                }

                Invoke-DbaQuery -SqlInstance $connection -Database $db -Query $azTipsQuery -EnableException:$EnableException | ForEach-Object {
                    [PSCustomObject]@{
                        ComputerName        = $connection.ComputerName
                        InstanceName        = $connection.ServiceName
                        SqlInstance         = $connection.DomainInstanceName
                        Database            = $db
                        tip_id              = $PsItem.tip_id
                        description         = $PsItem.description
                        confidence_percent  = $PsItem.confidence_percent
                        additional_info_url = $PsItem.additional_info_url
                        details             = $PsItem.details
                    }
                }
            }
        }
    }
}