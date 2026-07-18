function Add-DbaRegServer {
    <#
    .SYNOPSIS
        Registers SQL Server instances to Central Management Server or Local Server Groups in SSMS

    .DESCRIPTION
        Registers SQL Server instances as managed servers within SSMS, either to a Central Management Server (CMS) for enterprise-wide management or to Local Server Groups for personal organization. This allows DBAs to centrally organize and quickly connect to multiple SQL Server instances from SSMS without manually typing connection details each time. The function automatically creates server groups if they don't exist and supports various authentication methods including SQL Server, Windows, and Azure Active Directory. For importing existing registered servers from other sources, use Import-DbaRegServer instead.

    .PARAMETER SqlInstance
        The target SQL Server instance if a CMS is used

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerName
        Specifies the actual SQL Server instance name or network address that will be used to connect to the server.
        This is the technical identifier that SSMS uses for the physical connection (e.g., "sql01.domain.com,1433" or "sql01\INSTANCE").

    .PARAMETER Name
        Sets the display name that appears in the SSMS Registered Servers tree or CMS interface.
        Use this to give servers meaningful, recognizable names like "Production HR Database" instead of cryptic server names. Defaults to ServerName if not specified.

    .PARAMETER Description
        Provides additional details about the registered server that appear in SSMS properties.
        Use this to document the server's purpose, environment, or important notes like "Primary OLTP for HR applications" or "Read-only replica for reporting".

    .PARAMETER Group
        Places the registered server into a specific organizational folder within CMS or Local Server Groups.
        Creates nested groups using backslash notation like "Production\OLTP" or "Dev\Testing". The group structure will be created automatically if it doesn't exist.

    .PARAMETER ActiveDirectoryTenant
        Specifies the Azure Active Directory tenant ID when registering servers that use Azure AD authentication.
        Required when connecting to Azure SQL Database or SQL Managed Instance with AAD credentials.

    .PARAMETER ActiveDirectoryUserId
        Sets the Azure Active Directory user principal name for AAD authentication scenarios.
        Use this when you want the registered server to authenticate with a specific AAD account instead of integrated authentication.

    .PARAMETER ConnectionString
        Provides a complete SQL Server connection string with all authentication and connection parameters.
        Use this when you need specific connection properties like encryption settings, timeout values, or custom authentication methods not covered by other parameters.

    .PARAMETER OtherParams
        Appends additional connection string parameters to the base connection.
        Useful for adding specific connection properties like "MultipleActiveResultSets=True" or "TrustServerCertificate=True" without rebuilding the entire connection string.

    .PARAMETER ServerObject
        Accepts an existing SMO Server object from Connect-DbaInstance to register that connection.
        This preserves all connection settings and authentication from the original connection, making it ideal for registering servers you've already successfully connected to.

    .PARAMETER InputObject
        Accepts a server group object from Get-DbaRegServerGroup to specify where the server should be registered.
        Use this when you want to programmatically target a specific group or when piping group objects from other dbatools commands.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaRegServer

    .OUTPUTS
        Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer

        Returns one RegisteredServer object for each server registered. Multiple servers can be returned when registering to different server groups or Central Management Server instances.

        Default display properties (via Select-DefaultView):
        - Name: Display name of the registered server as it appears in SSMS Registered Servers pane
        - ServerName: The actual SQL Server connection string or instance name
        - Group: The server group hierarchy path where the server is registered (null if in root)
        - Description: User-provided description of the registered server
        - Source: Origin of the registration (Central Management Servers, Local Server Groups, or Azure Data Studio)

        Additional properties available (from SMO RegisteredServer object):
        - ComputerName: The computer name of the CMS or local registration location
        - InstanceName: The instance name of the CMS or local registration location
        - SqlInstance: The full SQL instance identifier of the CMS (computer\instance)
        - ParentServer: Reference to the parent server store object
        - Id: Unique identifier of the registered server within its store
        - ConnectionString: The connection string used to connect to the server
        - SecureConnectionString: Encrypted version of the connection string
        - ActiveDirectoryTenant: Azure AD tenant ID if using Azure AD authentication
        - ActiveDirectoryUserId: Azure AD user principal name if using Azure AD authentication
        - OtherParams: Additional connection string parameters
        - CredentialPersistenceType: How credentials are stored (PersistLoginNameAndPassword, etc.)
        - ServerType: Type of server (DatabaseEngine, AnalysisServices, etc.)
        - FQDN: Fully qualified domain name (populated when -ResolveNetworkName is used on Get-DbaRegServer)
        - IPAddress: IP address of the server (populated when -ResolveNetworkName is used on Get-DbaRegServer)

    .EXAMPLE
        PS C:\> Add-DbaRegServer -SqlInstance sql2008 -ServerName sql01

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible.

    .EXAMPLE
        PS C:\> Add-DbaRegServer -ServerName sql01

        Creates a registered server in Local Server Groups which points to the SQL Server, sql01. When scrolling in Registered Servers, the name "sql01" will be visible.

    .EXAMPLE
        PS C:\> Add-DbaRegServer -SqlInstance sql2008 -ServerName sql01 -Name "The 2008 Clustered Instance" -Description "HR's Dedicated SharePoint instance"

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, "The 2008 Clustered Instance" will be visible.
        Clearly this is hard to explain ;)

    .EXAMPLE
        PS C:\> Add-DbaRegServer -SqlInstance sql2008 -ServerName sql01 -Group hr\Seattle

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible within the Seattle group which is in the hr group.

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance dockersql1 -SqlCredential sqladmin | Add-DbaRegServer -ServerName mydockerjam

        Creates a registered server called "mydockerjam" in Local Server Groups that uses SQL authentication and points to the server dockersql1.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$ServerName,
        [string]$Name = $ServerName,
        [string]$Description,
        [object]$Group,
        [string]$ActiveDirectoryTenant,
        [string]$ActiveDirectoryUserId,
        [string]$ConnectionString,
        [string]$OtherParams,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Server[]]$ServerObject,
        [switch]$EnableException
    )
    process {
        # double check in case a null name was bound
        if (-not $PSBoundParameters.ServerName -and -not $PSBoundParameters.ServerObject) {
            Stop-Function -Message "You must specify either ServerName or ServerObject"
            return
        }
        if (-not $Name) {
            if ($ServerObject) {
                $Name = $ServerObject.Name
            } else {
                $Name = $ServerName
            }
        }

        if ((-not $SqlInstance -and -not $InputObject) -or $ServerObject) {
            Write-Message -Level Verbose -Message "Parsing local"
            if (($Group)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $regServerGroup = Get-DbaRegServerGroup -Group $Group.Name
                } else {
                    Write-Message -Level Verbose -Message "String group provided"
                    $regServerGroup = Get-DbaRegServerGroup -Group $Group
                }
                if ($regServerGroup) {
                    $InputObject += $regServerGroup
                } else {
                    # Create the Group
                    if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        $InputObject += Add-DbaRegServerGroup -Name $Group.Name
                    } else {
                        Write-Message -Level Verbose -Message "String group provided"
                        $InputObject += Add-DbaRegServerGroup -Name $Group
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "No group passed, getting root"
                $InputObject += Get-DbaRegServerGroup -Id 1
            }
        }

        foreach ($instance in $SqlInstance) {
            if (($Group)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $regServerGroup = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group.Name
                } else {
                    $regServerGroup = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }

                if ($regServerGroup) {
                    $InputObject += $regServerGroup
                } else {
                    if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        $InputObject += Add-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $Group.Name
                    } else {
                        Write-Message -Level Verbose -Message "String group provided"
                        $InputObject += Add-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $Group
                    }
                }
            } else {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
            }
        }

        foreach ($reggroup in $InputObject) {
            if ($reggroup.Source -eq "Azure Data Studio") {
                Stop-Function -Message "You cannot use dbatools to remove or add registered servers in Azure Data Studio" -Continue
            }
            Write-Message -Level Verbose -Message "ID: $($reggroup.ID)"
            if ($reggroup.ID) {
                $target = $reggroup.ParentServer.SqlInstance
            } else {
                $target = "Local Registered Servers"
            }
            if ($Pscmdlet.ShouldProcess($target, "Adding $name")) {

                if ($ServerObject) {
                    foreach ($server in $ServerObject) {
                        if (-not $PSBoundParameters.Name) {
                            $Name = $server.Name
                        }
                        if (-not $PSBoundParameters.ServerName) {
                            $ServerName = $server.Name
                        }
                        try {
                            $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($reggroup, $Name)
                            $newserver.ServerName = $ServerName
                            $newserver.Description = $Description
                            $newserver.ConnectionString = $server.ConnectionContext.ConnectionString
                            $newserver.SecureConnectionString = $server.ConnectionContext.SecureConnectionString
                            $newserver.ActiveDirectoryTenant = $ActiveDirectoryTenant
                            $newserver.ActiveDirectoryUserId = $ActiveDirectoryUserId
                            $newserver.OtherParams = $OtherParams
                            $newserver.CredentialPersistenceType = "PersistLoginNameAndPassword"
                            $newserver.Create()

                            Get-DbaRegServer -SqlInstance $reggroup.ParentServer -Name $Name -ServerName $ServerName | Where-Object Source -ne 'Azure Data Studio'
                        } catch {
                            Stop-Function -Message "Failed to add $ServerName on $target" -ErrorRecord $_ -Continue
                        }
                    }
                } else {
                    try {
                        $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($reggroup, $Name)
                        $newserver.ServerName = $ServerName
                        $newserver.Description = $Description
                        $newserver.ConnectionString = $ConnectionString
                        $newserver.ActiveDirectoryTenant = $ActiveDirectoryTenant
                        $newserver.ActiveDirectoryUserId = $ActiveDirectoryUserId
                        $newserver.OtherParams = $OtherParams
                        $newserver.Create()

                        Get-DbaRegServer -SqlInstance $reggroup.ParentServer -Name $Name -ServerName $ServerName | Where-Object Source -ne 'Azure Data Studio'
                    } catch {
                        Stop-Function -Message "Failed to add $ServerName on $target" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}