#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Import-DbaRegisteredServer {
    <#
        .SYNOPSIS
            Imports stuff

        .DESCRIPTION
            Imports stuff

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Group
            Specifies one or more groups to include from SQL Server Central Management Server.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Chrissy LeMaire (@cl)
            Tags: RegisteredServer, CMS

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Import-DbaRegisteredServer

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a

            Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -IncludeSelf

            Gets a list of servers from the CMS on sqlserver2014a and includes sqlserver2014a in the output results.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName

            Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

            Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

            Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    
    begin {
        function Add-DbaRegisteredServer {
            [CmdletBinding()]
            param (
                [parameter(Mandatory)]
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter[]]$SqlInstance,
                [PSCredential]$SqlCredential,
                [parameter(ValueFromPipeline)]
                [object[]]$InputObject,
                [object[]]$Group,
                [switch]$EnableException
            )
            process {
                # Traverse down, creating groups as you go.
                foreach ($object in $Group) {
                    if ($object -isnot [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        $groupobject = $groupstore.ServerGroups[$object]
                        if (-not $groupobject) {
                            Write-Message -Level Verbose -Message "Creating group $group on $server"
                            $newgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($groupstore, $group)
                            $newgroup.create()
                            $groupstore.refresh()
                        }
                        $groupstore = $groupstore.ServerGroups[$group]
                    }
                }
                
                if ($groupstore.RegisteredServers.Name -notcontains $regservername) {
                    Write-Message -Level Verbose -Message "Adding Server $servername"
                    $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupstore, $regservername)
                    $newserver.ServerName = $servername
                    $newserver.Description = $regserverdescription
                    $newserver.Create()
                    Write-Message -Level Verbose -Message "Added Server $servername"
                }
                else {
                    Write-Message -Level Verbose -Message "Server $servername already exists. Skipped"
                }
            }
        }
        
        process {
            foreach ($instance in $SqlInstance) {
                try {
                    Write-Message -Level Verbose -Message "Connecting to $instance"
                    $server = Get-DbaRegisteredServersStore -SqlInstance $instance -SqlCredential $sqlcredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                
                foreach ($object in $InputObject) {
                    if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                        Add-DbaRegisteredServer -SqlInstance $server
                    }
                    elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        
                    }
                    else {
                        
                    }
                }
            }
        <#
        # Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer.
        
        ComputerName                          :
        FQDN                                  :
        IPAddress                             :
        SecureConnectionString                : server=workstationx; integrated security=true
        ConnectionString                      : server=workstationx; integrated security=true
        Parent                                : ServerGroup[@Name='subfolder here']
        IdentityKey                           : RegisteredServer[@Name='workstationx']
        Name                                  : workstationx
        ID                                    : 1038
        Description                           :
        ServerName                            : workstationx
        UseCustomConnectionColor              : False
        CustomConnectionColorArgb             : 0
        ServerType                            : DatabaseEngine
        ConnectionStringWithEncryptedPassword :
        CredentialPersistenceType             : None
        OtherParams                           :
        AuthenticationType                    : -2147483648
        ActiveDirectoryUserId                 :
        ActiveDirectoryTenant                 :
        IsLocal                               : False
        IsDropped                             : False
        Urn                                   : RegisteredServersStore/ServerGroup[@Name='DatabaseEngineServerGroup']/ServerGroup[@Name='Folder Name baw']/ServerGroup[@Name='subfolder here']/RegisteredServer[@Name='workstationx']
        Properties                            : {
            Name=Name/Type=System.String/Writable=True/Value=workstationx, Name=ID/Type=System.Int32/Writable=False/Value=1038, Name=Description/Type=System.String/Writable=True/Value=,
                 Name=ServerName/Type=System.String/Writable=True/Value=workstationx...
        }
        Metadata                              : Microsoft.SqlServer.Management.Sdk.Sfc.Metadata.SfcMetadataDiscovery
        #>
        }
    }
}