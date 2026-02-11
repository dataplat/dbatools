function New-DbaLinkedServer {
    <#
    .SYNOPSIS
        Creates a new linked server connection to remote SQL Server instances or heterogeneous data sources.

    .DESCRIPTION
        Creates a new linked server on a SQL Server instance, allowing you to query remote databases and heterogeneous data sources as if they were local tables. This replaces the need to manually configure linked servers through SSMS or T-SQL scripts, while providing consistent security context management for unmapped logins. The function uses SMO to create the linked server definition and automatically configures the default security mapping based on your specified security context.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        Specifies the name for the new linked server object in SQL Server. This name must be unique on the SQL Server instance.
        Use a descriptive name that identifies the remote data source or its purpose to help other DBAs understand the connection.

    .PARAMETER ServerProduct
        Specifies the product name of the remote data source as it appears in sys.servers.product column.
        Common values include 'SQL Server' for SQL Server instances, 'Oracle' for Oracle databases, or custom names for other OLE DB data sources.
        This is primarily used for documentation and identification purposes in system views.

    .PARAMETER Provider
        Specifies the OLE DB provider used to connect to the remote data source.
        For SQL Server, use 'MSOLEDBSQL' or 'MSOLEDBSQL19' (recommended) - SQL Server Native Client (SQLNCLI) is deprecated and removed from SQL Server 2022 and SSMS 19.
        Other common providers include 'OraOLEDB.Oracle' for Oracle or 'Microsoft.ACE.OLEDB.12.0' for Access databases.
        The provider must be installed and registered on the SQL Server instance.

    .PARAMETER DataSource
        Specifies the network name or connection string for the remote data source.
        For SQL Server instances, this is typically the server name or server\instance format.
        For other data sources, this could be a TNS name for Oracle or a file path for file-based sources.

    .PARAMETER Location
        Specifies the physical location information for the data source, typically used for documentation purposes.
        This parameter is rarely required for most linked server configurations and is primarily used with specific OLE DB providers.
        Leave empty unless specifically required by your data source provider.

    .PARAMETER ProviderString
        Specifies additional connection properties passed directly to the OLE DB provider.
        Use this for provider-specific settings like connection pooling, timeouts, or authentication options that cannot be set through other parameters.
        The format and available options depend on the specific OLE DB provider being used.

    .PARAMETER Catalog
        Specifies the default database or catalog name to use when connecting to the remote data source.
        For SQL Server linked servers, this sets the default database context for queries that don't specify a database name.
        This is equivalent to the 'Initial Catalog' connection property in connection strings.

    .PARAMETER SecurityContext
        Specifies the security context option found on the SSMS Security tab of the linked server. This is a separate configuration from the mapping of a local login to a remote login. It specifies the connection behavior for a login that is not explicitly mapped. 'NoConnection' means that a connection will not be made. 'WithoutSecurityContext' means the connection will be made without using a security context. 'CurrentSecurityContext' means the connection will be made using the login's current security context. 'SpecifiedSecurityContext' means the specified username and password will be used. The default value is 'WithoutSecurityContext'. For more details see the Microsoft documentation for sp_addlinkedsrvlogin and also review the SSMS Security tab of the linked server.

    .PARAMETER SecurityContextRemoteUser
        Specifies the remote login name. This param is used when SecurityContext is set to SpecifiedSecurityContext. To map a local login to a remote login use New-DbaLinkedServerLogin.

    .PARAMETER SecurityContextRemoteUserPassword
        Specifies the remote login password. This param is used when SecurityContext is set to SpecifiedSecurityContext. To map a local login to a remote login use New-DbaLinkedServerLogin. NOTE: passwords are sent to the SQL Server instance in plain text. Check with your security administrator before using this parameter.

    .PARAMETER InputObject
        Accepts SQL Server SMO objects from the pipeline, typically from Connect-DbaInstance.
        This allows you to create linked servers on multiple instances by piping server connections to this function.
        Use this when you need to create the same linked server configuration across multiple SQL Server instances.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LinkedServer, Server
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaLinkedServer

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.LinkedServer

        Returns one LinkedServer object for each linked server successfully created on the target SQL Server instance(s).
        The returned object is retrieved via Get-DbaLinkedServer after creation.

        Default display properties (via Select-DefaultView in Get-DbaLinkedServer):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Name of the linked server
        - RemoteServer: Network name or connection string for the remote data source (aliased from DataSource)
        - ProductName: Product name of the remote data source
        - Impersonate: Boolean indicating if impersonation is used for connection
        - RemoteUser: The remote login name used for connection
        - Publisher: Boolean indicating if the linked server is a replication publisher (aliased from DistPublisher)
        - Distributor: Boolean indicating if the linked server is a replication distributor
        - DateLastModified: Timestamp of when the linked server was last modified

        Additional properties available (from SMO LinkedServer object):
        - DataSource: Network name or connection string (source property for RemoteServer alias)
        - DistPublisher: Boolean indicating if the linked server is a distribution publisher (source property for Publisher alias)
        - Catalog: Default database or catalog name on the remote data source
        - Location: Physical location information for the data source
        - ProviderName: OLE DB provider used to connect to the remote data source
        - ProviderString: Additional connection properties passed to the OLE DB provider
        - RpcEnabled: Boolean indicating if remote procedure calls are enabled
        - RpcOut: Boolean indicating if outgoing RPC calls are allowed
        - ConnectTimeout: Connection timeout in seconds
        - QueryTimeout: Query timeout in seconds

    .EXAMPLE
        PS C:\>New-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1 -ServerProduct mssql -Provider MSOLEDBSQL -DataSource sql02

        Creates a new linked server named linkedServer1 on the sql01 instance. The link uses the Microsoft OLE DB Driver for SQL Server and is connected to the sql02 instance.

    .EXAMPLE
        PS C:\>Connect-DbaInstance -SqlInstance sql01 | New-DbaLinkedServer -LinkedServer linkedServer1 -ServerProduct mssql -Provider MSOLEDBSQL -DataSource sql02

        Creates a new linked server named linkedServer1 on the sql01 instance. The link uses the Microsoft OLE DB Driver for SQL Server and is connected to the sql02 instance. The sql01 instance is passed in via pipeline.

    .EXAMPLE
        PS C:\>New-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1 -ServerProduct mssql -Provider MSOLEDBSQL -DataSource sql02 -SecurityContext CurrentSecurityContext

        Creates a new linked server named linkedServer1 on the sql01 instance. The link uses the Microsoft OLE DB Driver for SQL Server and is connected to the sql02 instance. Connections with logins that are not explicitly mapped to the remote server will use the current login's security context.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$LinkedServer,
        [string]$ServerProduct,
        [string]$Provider,
        [string]$DataSource,
        [string]$Location,
        [string]$ProviderString,
        [string]$Catalog,
        [ValidateSet('NoConnection', 'WithoutSecurityContext', 'CurrentSecurityContext', 'SpecifiedSecurityContext')]
        [string]$SecurityContext = 'WithoutSecurityContext',
        [string]$SecurityContextRemoteUser,
        [Security.SecureString]$SecurityContextRemoteUserPassword,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if (Test-Bound -Not -ParameterName LinkedServer) {
            Stop-Function -Message "LinkedServer is required"
            return
        }

        if ($SecurityContext -eq "SpecifiedSecurityContext") {
            if (Test-Bound -Not -ParameterName SecurityContextRemoteUser) {
                Stop-Function -Message "SecurityContextRemoteUser is required when SpecifiedSecurityContext is used"
                return
            } elseif (Test-Bound -Not -ParameterName SecurityContextRemoteUserPassword) {
                Stop-Function -Message "SecurityContextRemoteUserPassword is required when SpecifiedSecurityContext is used"
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        }

        foreach ($server in $InputObject) {

            if ($server.LinkedServers.Name -contains $LinkedServer) {
                Stop-Function -Message "Linked server $LinkedServer already exists on $($server.Name)" -Continue
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating the linked server $LinkedServer on $($server.Name)")) {
                try {
                    $newLinkedServer = New-Object Microsoft.SqlServer.Management.Smo.LinkedServer -ArgumentList $server, $LinkedServer

                    if (Test-Bound ServerProduct) {
                        $newLinkedServer.ProductName = $ServerProduct
                    }

                    if (Test-Bound Provider) {
                        $newLinkedServer.ProviderName = $Provider
                    }

                    if (Test-Bound DataSource) {
                        $newLinkedServer.DataSource = $DataSource
                    }

                    if (Test-Bound Location) {
                        $newLinkedServer.Location = $Location
                    }

                    if (Test-Bound ProviderString) {
                        $newLinkedServer.ProviderString = $ProviderString
                    }

                    if (Test-Bound Catalog) {
                        $newLinkedServer.Catalog = $Catalog
                    }

                    $newLinkedServer.Create()

                    if (Test-Bound SecurityContext) {
                        if ($SecurityContext -eq 'NoConnection') {
                            $server.Query("EXEC master.dbo.sp_droplinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL")
                        } elseif ($SecurityContext -eq 'WithoutSecurityContext') {
                            $server.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL, @useself = N'False', @rmtuser = N''")
                        } elseif ($SecurityContext -eq 'CurrentSecurityContext') {
                            $server.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL, @useself = N'True', @rmtuser = N''")
                        } elseif ($SecurityContext -eq 'SpecifiedSecurityContext') {
                            $server.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL, @useself = N'False', @rmtuser = N'$SecurityContextRemoteUser', @rmtpassword = N'$($SecurityContextRemoteUserPassword | ConvertFrom-SecurePass)'")
                        }
                    }

                    $server | Get-DbaLinkedServer -LinkedServer $LinkedServer
                } catch {
                    Stop-Function -Message "Failure on $($server.Name) to create the linked server $LinkedServer" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}