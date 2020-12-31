function Connect-SqlInstance {
    <#
    .SYNOPSIS
        Internal function to establish smo connections.

    .DESCRIPTION
        Internal function to establish smo connections.

        Can interpret any of the following types of information:
        - String
        - Smo Server objects
        - Smo Linked Server objects

        Related Docs, Pull Requests and Issues:

    Connect commands and alt Windows Credential fix
    https://github.com/sqlcollaborative/dbatools/pull/3835

    Connect-*Instance, fix errors with Windows logins
    https://github.com/sqlcollaborative/dbatools/pull/4426

    Invoke-DbaSqlQuery fails to use proper Windows credentials
    https://github.com/sqlcollaborative/dbatools/issues/3780

    Fixed auth issue
    https://github.com/sqlcollaborative/dbatools/pull/3809

    Connecting to an Instance of SQL Server
    https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/connecting-to-an-instance-of-sql-server

    SQL Server Connection Pooling (ADO.NET)
    https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql-server-connection-pooling

    .PARAMETER SqlInstance
        The SQL Server instance to restore to.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER ParameterConnection
        This call is for dynamic parameters only and is no longer used, actually.

    .PARAMETER AzureUnsupported
        Throw if Azure is detected but not supported

    .PARAMETER MinimumVersion
       The minimum version that the calling command will support

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a timeout error.

    .EXAMPLE
        Connect-SqlInstance -SqlInstance sql2014

        Connect to the Server sql2014 with native credentials.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$StatementTimeout,
        [int]$MinimumVersion,
        [string]$Database,
        [switch]$AzureUnsupported,
        [switch]$NonPooled
    )
    if ($SqlInstance.InputObject.GetType().Name -eq 'Server') {
        if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
            throw "Azure SQL Database is not supported by this command"
        }
        return $SqlInstance.InputObject
    } else {
        Connect-DbaInstance @PSBoundParameters -ClientName (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname')
    }
}