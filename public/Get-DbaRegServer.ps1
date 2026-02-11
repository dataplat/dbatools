function Get-DbaRegServer {
    <#
    .SYNOPSIS
        Retrieves registered SQL Server instances from SSMS, Azure Data Studio, and Central Management Server

    .DESCRIPTION
        Retrieves SQL Server instances from registered server configurations stored in SQL Server Management Studio (SSMS), Azure Data Studio, and Central Management Server (CMS). DBAs use registered servers to organize and quickly connect to multiple SQL Server instances across their environment.

        When no SqlInstance is specified, returns local registered servers from SSMS and Azure Data Studio. When SqlInstance is provided, connects to that Central Management Server to retrieve its registered server inventory. This is essential for discovering what SQL Server instances are documented and organized in your environment.

        Local Registered Servers and Azure Data Studio support alternative authentication (excluding MFA) but Central Management Server does not.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Filters results to registered servers with specific display names as they appear in SSMS Registered Servers pane.
        Use this when you need to find servers by their friendly names rather than actual server names.

    .PARAMETER ServerName
        Filters results to registered servers with specific server instance names (the actual SQL Server connection strings).
        Use this when you need to find servers by their network names or instance names rather than display names.

    .PARAMETER Pattern
        Specifies a pattern for filtering registered servers using regular expressions.
        Use this when you need to match servers by pattern, such as "^prod" or ".*-db$".
        This parameter supports standard .NET regular expression syntax and matches against both Name and ServerName properties.
    
    .PARAMETER ExcludeServerName
        Excludes registered servers with specific server instance names (the actual SQL Server connection strings).
        Use this when you want to retrieve most servers but skip certain instances like those under maintenance or decommissioned.

    .PARAMETER Group
        Filters results to registered servers within specific Central Management Server groups.
        Supports hierarchical paths using backslash notation (e.g., "Production\Database Servers"). Use this to target servers organized by environment, department, or function.

    .PARAMETER ExcludeGroup
        Excludes registered servers from specific Central Management Server groups.
        Use this when you want to retrieve most servers but skip certain groups like "Test" or "Decommissioned" environments.

    .PARAMETER IncludeLocal
        Includes local SSMS and Azure Data Studio registered servers in addition to Central Management Server results.
        Use this when querying a CMS but also want to see servers registered locally on your workstation.

    .PARAMETER Id
        Filters results to registered servers with specific internal ID numbers.
        Use this when you need to retrieve specific servers by their unique identifiers, typically when working with programmatic scripts or automation.

    .PARAMETER IncludeSelf
        Includes the Central Management Server instance itself in the results along with all registered servers.
        Use this when you need to perform operations on both the CMS and its registered servers in the same workflow.

    .PARAMETER ResolveNetworkName
        Performs DNS lookups to return NetBIOS names, FQDN, and IP addresses for each registered server.
        Use this when you need network information for servers, but be aware this adds processing time due to DNS queries.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer

        Returns one RegisteredServer object per registered SQL Server instance, sourced from Central Management Server, SSMS local registered servers, or Azure Data Studio. Server objects can be sourced from one or more locations:
        - Central Management Server (CMS): When SqlInstance parameter is provided
        - Local SSMS Registered Servers: When no SqlInstance provided or -IncludeLocal is specified
        - Azure Data Studio connections: When no SqlInstance provided or -IncludeLocal is specified
        - CMS instance itself: When -IncludeSelf is specified with a CMS query

        Default display properties (via Select-DefaultView):
        - Name: The display name of the registered server as shown in SSMS Registered Servers or Azure Data Studio
        - ServerName: The actual SQL Server connection string (computer name, IP address, or instance name)
        - Group: The CMS group path (hierarchical, using backslash separators) or null for root-level servers
        - Description: Text description of the registered server
        - Source: Source location of the registration - "Central Management Servers", "Local Server Groups", or "Azure Data Studio"

        Additional available properties from the RegisteredServer object:
        - ComputerName: NetBIOS computer name of the CMS instance (for CMS-sourced servers)
        - InstanceName: The SQL Server instance name of the CMS (for CMS-sourced servers)
        - SqlInstance: The full SQL Server instance name of the CMS (for CMS-sourced servers)
        - ParentServer: The parent CMS instance name (for CMS-sourced servers)
        - ConnectionString: The connection string with decrypted password if available
        - SecureConnectionString: The connection string as a SecureString object if password was decrypted
        - Id: Internal identifier for the registered server
        - ServerType: Type of server (DatabaseEngine, AnalysisServices, ReportingServices, etc.)
        - CredentialPersistenceType: Whether credentials are stored (mainly for Azure Data Studio sources)

        All properties from the base RegisteredServer SMO object are accessible using Select-Object *.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Bryan Hamby (@galador) | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRegServer

    .EXAMPLE
        PS C:\> Get-DbaRegServer

        Gets a list of servers from the local registered servers and azure data studio

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a

        Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -IncludeSelf

        Gets a list of servers from the CMS on sqlserver2014a and includes sqlserver2014a in the output results.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName

        Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -Group HR, Accounting

        Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -Group HR\Development

        Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -Pattern "^prod"

        Returns all registered servers that match the regex pattern "^prod" (e.g., prod-server1, production-db) from the CMS on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -Group Production -ExcludeServerName "serverAlfa", "ServerBeta"

        Gets a list of servers in the Production group from the CMS on sqlserver2014a, excluding serverAlfa and ServerBeta. Useful when you need to skip specific servers during maintenance windows.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance = (Get-DbatoolsConfigValue -FullName 'commands.get-dbaregserver.defaultcms'),
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
        [string[]]$Pattern,
        [Alias("ExcludeServer")]
        [string[]]$ExcludeServerName,
        [string[]]$Group,
        [string[]]$ExcludeGroup,
        [int[]]$Id,
        [switch]$IncludeSelf,
        [switch]$ResolveNetworkName,
        [switch]$IncludeLocal = (Get-DbatoolsConfigValue -FullName 'commands.get-dbaregserver.includelocal'),
        [switch]$EnableException
    )
    begin {
        if ($ResolveNetworkName) {
            $defaults = 'ComputerName', 'FQDN', 'IPAddress', 'Name', 'ServerName', 'Group', 'Description', 'Source'
        }
        $defaults = 'Name', 'ServerName', 'Group', 'Description', 'Source'
        # thank you forever https://social.msdn.microsoft.com/Forums/sqlserver/en-US/57811d43-a2b9-4179-a97b-a9936ddb188e/how-to-retrieve-a-password-saved-by-sql-server?forum=sqltools
        function Unprotect-String([string] $base64String) {
            return [System.Text.Encoding]::Unicode.GetString([System.Security.Cryptography.ProtectedData]::Unprotect([System.Convert]::FromBase64String($base64String), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))
        }

        # Helper function to test if a name matches any of the provided regex patterns
        $matchesPattern = {
            param($name, $serverName, $patterns)
            if (!$patterns) { return $true }
            foreach ($pattern in $patterns) {
                if ($name -match $pattern -or $serverName -match $pattern) {
                    return $true
                }
            }
            return $false
        }
    }
    process {
        if (-not $PSBoundParameters.SqlInstance -and -not ($IsLinux -or $IsMacOs)) {
            $null = Get-ChildItem -Recurse "$(Get-DbatoolsPath -Name appdata)\Microsoft\*sql*" -Filter RegSrvr*.xml | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }

        $servers = @()
        $serverToServerStore = @{ }
        foreach ($instance in $SqlInstance) {

            try {
                $serverstore = Get-DbaRegServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue
            }

            if ($Group) {
                $groupservers = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup
                if ($groupservers) {
                    $servers += $groupservers.GetDescendantRegisteredServers()
                }
            } else {
                $servers += ($serverstore.DatabaseEngineServerGroup.GetDescendantRegisteredServers())
                $serverstore.ServerConnection.Disconnect()
            }

            # save the $serverstore for later usage
            foreach ($server in $servers) {
                $serverToServerStore[$server] = $serverstore
            }
        }

        # Magic courtesy of Mathias Jessen and David Shifflet
        if (-not $PSBoundParameters.SqlInstance -or $PSBoundParameters.IncludeLocal) {
            $file = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]::LocalFileStore.DomainInstanceName
            if ($file) {
                if ((Test-Path -Path $file)) {
                    $class = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]
                    $initMethod = $class.GetMethod('InitChildObjects', [Reflection.BindingFlags]'Static,NonPublic')
                    $store = ($initMethod.Invoke($null, @($file)))
                    # Local Reg Servers
                    foreach ($tempserver in $store.DatabaseEngineServerGroup.GetDescendantRegisteredServers()) {
                        $servers += $tempserver | Add-Member -Force -Name Source -Value "Local Server Groups" -MemberType NoteProperty -PassThru
                    }
                    # Azure Reg Servers
                    $azureids = @()
                    if ($store.AzureDataStudioConnectionStore.Groups) {
                        $adsconnection = Get-ADSConnection
                    }
                    foreach ($azuregroup in $store.AzureDataStudioConnectionStore.Groups) {
                        $groupname = $azuregroup.Name
                        if ($groupname -eq 'ROOT' -or $groupname -eq '') {
                            $groupname = $null
                        }
                        $tempgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup $groupname
                        $tempgroup.Description = $azuregroup.Description

                        foreach ($server in ($store.AzureDataStudioConnectionStore.Connections | Where-Object GroupId -eq $azuregroup.Id)) {
                            $azureids += [PSCustomObject]@{ id = $server.Id; group = $groupname }
                            $connname = $server.Options['connectionName']
                            if (-not $connname) {
                                $connname = $server.Options['server']
                            }
                            $adsconn = $adsconnection | Where-Object { $_.server -eq $server.Options['server'] -and -not $_.database }

                            $tempserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer $tempgroup, $connname
                            $tempserver.Description = $server.Options['Description']
                            if ($adsconn.ConnectionString) {
                                $tempserver.ConnectionString = $adsconn.ConnectionString
                            }
                            # update read-only or problematic properties
                            $tempserver | Add-Member -Force -Name Source -Value "Azure Data Studio" -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name ServerName -Value $server.Options['server'] -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name Id -Value $server.Id -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name CredentialPersistenceType -Value 1 -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name ServerType -Value DatabaseEngine -MemberType NoteProperty
                            $servers += $tempserver
                        }
                    }
                }
            }
        }

        if ($Name) {
            Write-Message -Level Verbose -Message "Filtering by name for $name"
            $servers = $servers | Where-Object Name -in $Name
        }

        if ($ServerName) {
            Write-Message -Level Verbose -Message "Filtering by servername for $servername"
            $servers = $servers | Where-Object ServerName -in $ServerName
        }

        if ($Pattern) {
            Write-Message -Level Verbose -Message "Filtering by pattern for $Pattern"
            $servers = $servers | Where-Object { & $matchesPattern $_.Name $_.ServerName $Pattern }
        }
        
        if ($ExcludeServerName) {
            Write-Message -Level Verbose -Message "Excluding servers: $ExcludeServerName"
            $servers = $servers | Where-Object ServerName -notin $ExcludeServerName
        }

        if ($Id) {
            Write-Message -Level Verbose -Message "Filtering by id for $Id (1 = default/root)"
            $servers = $servers | Where-Object Id -in $Id
        }

        foreach ($server in $servers) {
            $az = $azureids | Where-Object Id -in $server.Id
            if ($az) {
                $groupname = $az.Group
            } else {
                $groupname = Get-RegServerGroupReverseParse $server
                if ($groupname -eq $server.Name) {
                    $groupname = $null
                } else {
                    $groupname = ($groupname).Split("\")
                    $groupname = $groupname[0 .. ($groupname.Count - 2)]
                    $groupname = ($groupname -join "\")
                }
            }
            # ugly way around it but it works
            $badform = "$($server.Name.Split("\")[0])\$($server.Name.Split("\")[0])"
            if ($groupname -eq $badform) {
                $groupname = $null
            }

            if ($ExcludeGroup -and ($groupname -in $ExcludeGroup)) {
                continue
            }

            if ($server.ConnectionStringWithEncryptedPassword) {
                $encodedconnstring = $connstring = $server.ConnectionStringWithEncryptedPassword
                if ($encodedconnstring -imatch 'password="?([^";]+)"?') {
                    $password = $Matches[1]
                    $password = Unprotect-String $password
                    $connstring = $encodedconnstring -ireplace 'password="?([^";]+)"?', "password=`"$password`""
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ConnectionString -Value $connstring
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SecureConnectionString -Value (ConvertTo-SecureString -String $connstring -AsPlainText -Force)
                }
            }

            if (-not $server.Source) {
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name Source -value "Central Management Servers"
            }

            if ( $null -ne $serverToServerStore[$server] ) {
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -value $serverToServerStore[$server].ComputerName
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name InstanceName -value $serverToServerStore[$server].InstanceName
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SqlInstance -value $serverToServerStore[$server].SqlInstance
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ParentServer -Value $serverToServerStore[$server].ParentServer
            }

            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name Group -value $groupname
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $null
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null

            if ($ResolveNetworkName) {
                try {
                    $lookup = Resolve-DbaNetworkName $server.ServerName -Turbo
                    $server.ComputerName = $lookup.ComputerName
                    $server.FQDN = $lookup.FQDN
                    $server.IPAddress = $lookup.IPAddress
                } catch {
                    try {
                        $lookup = Resolve-DbaNetworkName $server.ServerName
                        $server.ComputerName = $lookup.ComputerName
                        $server.FQDN = $lookup.FQDN
                        $server.IPAddress = $lookup.IPAddress
                    } catch {
                        # here to avoid an empty catch
                        $null = 1
                    }
                }
            }

            # this is a bit dirty and should be addressed by someone who better knows recursion and regex
            if ($server.Source -ne "Central Management Servers") {
                if ($PSBoundParameters.Group -and $groupname -notin $PSBoundParameters.Group) { continue }
                if ($PSBoundParameters.ExcludeGroup -and $groupname -in $PSBoundParameters.ExcludeGroup) { continue }
            }

            Add-Member -Force -InputObject $server -MemberType ScriptMethod -Name ToString -Value { $this.ServerName }
            Select-DefaultView -InputObject $server -Property $defaults
        }

        if ($IncludeSelf -and $servers) {
            Write-Message -Level Verbose -Message "Adding CMS instance"
            $self = $servers[0].PsObject.Copy() | Select-Object -Property $defaults
            $self | Add-Member -MemberType NoteProperty -Name Name -Value "CMS Instance" -Force
            $self.ServerName = $instance
            $self.Group = $null
            $self.Description = $null
            Select-DefaultView -InputObject $self -Property $defaults
        }
    }
}