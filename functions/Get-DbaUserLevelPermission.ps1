function Get-DbaUserLevelPermission {
    <#
    .SYNOPSIS
        Displays detailed permissions information for the server and database roles and securables.

    .DESCRIPTION
        This command will display all server logins, server level securable, database logins and database securables.

        DISA STIG implementators will find this command useful as it uses Permissions.sql provided by DISA.

        Note that if you Ctrl-C out of this command and end it prematurely, it will leave behind a STIG schema in tempdb.

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        $cred = Get-Credential, this pass this $cred to the param.

        Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER ExcludeSystemDatabase
        Allows you to suppress output on system databases

    .PARAMETER IncludePublicGuest
        Allows you to include output for public and guest grants.

    .PARAMETER IncludeSystemObjects
        Allows you to include output on sys schema objects.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Discovery, Permissions, Security
    Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Get-DbaUserLevelPermission

    .EXAMPLE
        Get-DbaUserLevelPermission -SqlInstance sql2008, sqlserver2012
        Check server and database permissions for servers sql2008 and sqlserver2012.

    .EXAMPLE
        Get-DbaUserLevelPermission -SqlInstance sql2008 -Database TestDB
        Check server and database permissions on server sql2008 for only the TestDB database

    .EXAMPLE
        Get-DbaUserLevelPermission -SqlInstance sql2008 -Database TestDB -IncludePublicGuest -IncludeSystemObjects
        Check server and database permissions on server sql2008 for only the TestDB database,
        including public and guest grants, and sys schema objects.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Position = 1, Mandatory = $false)]
        [switch]$ExcludeSystemDatabase,
        [switch]$IncludePublicGuest,
        [switch]$IncludeSystemObjects,
        [switch][Alias('Silent')]$EnableException
    )

    BEGIN {

        $sql = [System.IO.File]::ReadAllText("$script:PSModuleRoot\bin\stig.sql")

        $endSQL = "	   BEGIN TRY DROP FUNCTION STIG.server_effective_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.server_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.members_of_server_role END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.server_roles_of END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.server_role_members END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.database_effective_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.database_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.members_of_db_role END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.database_roles_of END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.database_role_members END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP SCHEMA STIG END TRY BEGIN CATCH END CATCH;
                       GO"


        $serverSQL = "SELECT  'SERVER LOGINS' AS Type ,
                                    sl.name AS Member ,
                                    ISNULL(srm.role, 'None') AS [Role/Securable/Class] ,
                                    ' ' AS [Schema/Owner] ,
                                    ' ' AS [Securable] ,
                                    ' ' AS [Grantee Type] ,
                                    ' ' AS [Grantee] ,
                                    ' ' AS [Permission] ,
                                    ' ' AS [State] ,
                                    ' ' AS [Grantor] ,
                                    ' ' AS [Grantor Type] ,
                                    ' ' AS [Source View]
                            FROM    master.sys.syslogins sl
                                    LEFT JOIN tempdb.[STIG].[server_role_members] srm ON sl.name = srm.member
                            WHERE   sl.name NOT LIKE 'NT %'
                                    AND sl.name NOT LIKE '##%'
                            UNION
                            SELECT  'SERVER SECURABLES' AS Type ,
                                    sl.name ,
                                    sp.[Securable Class] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    ' ' ,
                                    sp.[Securable] ,
                                    sp.[Grantee Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.Grantee ,
                                    sp.Permission COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.State COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.Grantor ,
                                    sp.[Grantor Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.[Source View]
                            FROM    master.sys.syslogins sl
                                    LEFT JOIN tempdb.[STIG].[server_permissions] sp ON sl.name = sp.Grantee
                            WHERE   sl.name NOT LIKE 'NT %'
                                    AND sl.name NOT LIKE '##%';"

        $dbSQL = "SELECT  'DB ROLE MEMBERS' AS type ,
                                Member ,
                                Role ,
                                ' ' AS [Schema/Owner] ,
                                ' ' AS [Securable] ,
                                ' ' AS [Grantee Type] ,
                                ' ' AS [Grantee] ,
                                ' ' AS [Permission] ,
                                ' ' AS [State] ,
                                ' ' AS [Grantor] ,
                                ' ' AS [Grantor Type] ,
                                ' ' AS [Source View]
                        FROM    tempdb.[STIG].[database_role_members]
                        UNION
                        SELECT DISTINCT
                                'DB SECURABLES' AS Type ,
                                drm.member ,
                                dp.[Securable Type or Class] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.[Schema/Owner] ,
                                dp.Securable ,
                                dp.[Grantee Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.Grantee ,
                                dp.Permission COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.State COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.Grantor ,
                                dp.[Grantor Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.[Source View]
                        FROM    tempdb.[STIG].[database_role_members] drm
                                LEFT JOIN tempdb.[STIG].[database_permissions] dp ON ( drm.member = dp.grantee
                                                                                      OR drm.role = dp.grantee
                                                                                     )
                        WHERE	dp.Grantor IS NOT NULL
                                AND [Schema/Owner] <> 'sys'"

        if ($IncludePublicGuest) { $dbSQL = $dbSQL.Replace("LEFT JOIN", "FULL JOIN") }
        if ($IncludeSystemObjects) { $dbSQL = $dbSQL.Replace("AND [Schema/Owner] <> 'sys'", "") }

    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            if ($ExcludeSystemDatabase) {
                $dbs = $dbs | Where-Object IsSystemObject -eq $false
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible" -Continue
                }

                $sql = $sql.Replace("<TARGETDB>", $db.Name)

                #Create objects in active database
                Write-Message -Level Verbose -Message "Creating objects"
                try { $db.ExecuteNonQuery($sql) } catch {} # sometimes it complains about not being able to drop the stig schema if the person Ctrl-C'd before.

                #Grab permissions data
                if (-not $serverDT) {
                    Write-Message -Level Verbose -Message "Building data table for server objects"

                    try { $serverDT = $db.Query($serverSQL) } catch { }

                    foreach ($row in $serverDT) {
                        [PSCustomObject]@{
                            ComputerName       = $server.NetName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Object             = 'SERVER'
                            Type               = $row.Type
                            Member             = $row.Member
                            RoleSecurableClass = $row.'Role/Securable/Class'
                            SchemaOwner        = $row.'Schema/Owner'
                            Securable          = $row.Securable
                            GranteeType        = $row.'Grantee Type'
                            Grantee            = $row.Grantee
                            Permission         = $row.Permission
                            State              = $row.State
                            Grantor            = $row.Grantor
                            GrantorType        = $row.'Grantor Type'
                            SourceView         = $row.'Source View'
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Building data table for $db objects"
                try { $dbDT = $db.Query($dbSQL) } catch { }

                foreach ($row in $dbDT) {
                    [PSCustomObject]@{
                        ComputerName       = $server.NetName
                        InstanceName       = $server.ServiceName
                        SqlInstance        = $server.DomainInstanceName
                        Object             = $db.Name
                        Type               = $row.Type
                        Member             = $row.Member
                        RoleSecurableClass = $row.'Role/Securable/Class'
                        SchemaOwner        = $row.'Schema/Owner'
                        Securable          = $row.Securable
                        GranteeType        = $row.'Grantee Type'
                        Grantee            = $row.Grantee
                        Permission         = $row.Permission
                        State              = $row.State
                        Grantor            = $row.Grantor
                        GrantorType        = $row.'Grantor Type'
                        SourceView         = $row.'Source View'
                    }
                }

                #Delete objects
                Write-Message -Level Verbose -Message "Deleting objects"
                try { $db.ExecuteNonQuery($endSQL) } catch { }
                $sql = $sql.Replace($db.Name, "<TARGETDB>")

                #Sashay Away
            }
        }
    }
}