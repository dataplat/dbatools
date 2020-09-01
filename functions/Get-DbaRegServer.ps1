function Get-DbaRegServer {
    <#
    .SYNOPSIS
        Gets list of SQL Server objects stored in local registered groups, azure data studio and central management server.

    .DESCRIPTION
       Gets list of SQL Server objects stored in local registered groups, azure data studio and central management server.

       Local Registered Servers and Azure Data Studio support alternative authentication (excluding MFA) but Central Management Studio does not.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies one or more names to include. Name is the visible name in SSMS interface (labeled Registered Server Name)

    .PARAMETER ServerName
        Specifies one or more server names to include. Server Name is the actual instance name (labeled Server Name)

    .PARAMETER Group
        Specifies one or more groups to include from SQL Server Central Management Server.

    .PARAMETER ExcludeGroup
        Specifies one or more Central Management Server groups to exclude.

    .PARAMETER IncludeLocal
        Include local registered servers or Azure Data Studio registered servers in results when specifying SqlInstance.

    .PARAMETER Id
        Get server by Id(s)

    .PARAMETER IncludeSelf
        If this switch is enabled and you're connecting to a Central Management Server, the CMS server itself will be included in the results, along with all other Registered Servers.

    .PARAMETER ResolveNetworkName
        If this switch is enabled, the NetBIOS name and IP address(es) of each server will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

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

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance = (Get-DbatoolsConfigValue -FullName 'commands.get-dbaregserver.defaultcms'),
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
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
    }
    process {
        if (-not $PSBoundParameters.SqlInstance -and -not ($IsLinux -or $IsMacOs)) {
            $null = Get-ChildItem -Recurse "$(Get-DbatoolsPath -Name appdata)\Microsoft\*sql*" -Filter RegSrvr.xml | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }

        $servers = @()
        foreach ($instance in $SqlInstance) {
            if ($Group) {
                $groupservers = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup
                if ($groupservers) {
                    $servers += $groupservers.GetDescendantRegisteredServers()
                }
            } else {
                try {
                    $serverstore = Get-DbaRegServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
                } catch {
                    Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue
                }
                $servers += ($serverstore.DatabaseEngineServerGroup.GetDescendantRegisteredServers())
                $serverstore.ServerConnection.Disconnect()
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
                            $azureids += [pscustomobject]@{ id = $server.Id; group = $groupname }
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
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -value $serverstore.ComputerName
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name InstanceName -value $serverstore.InstanceName
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SqlInstance -value $serverstore.SqlInstance
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name Group -value $groupname
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $null
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ParentServer -Value $serverstore.ParentServer

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