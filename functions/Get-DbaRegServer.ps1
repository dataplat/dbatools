function Get-DbaRegServer {
    <#
    .SYNOPSIS
        Gets list of SQL Server objects stored in local registered groups and central management server.

    .DESCRIPTION
       Gets list of SQL Server objects stored in local registered groups and central management server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Name
        Specifies one or more names to include. Name is the visible name in SSMS CMS interface (labeled Registered Server Name)

    .PARAMETER ServerName
        Specifies one or more server names to include. Server Name is the actual instance name (labeled Server Name)

    .PARAMETER Group
        Specifies one or more groups to include from SQL Server Central Management Server.

    .PARAMETER ExcludeGroup
        Specifies one or more Central Management Server groups to exclude.

    .PARAMETER ExcludeLocal
        Do not include local registered servers in results.

    .PARAMETER Id
        Get server by Id(s)

    .PARAMETER IncludeSelf
        If this switch is enabled, the CMS server itself will be included in the results, along with all other Registered Servers.

    .PARAMETER ResolveNetworkName
        If this switch is enabled, the NetBIOS name and IP address(es) of each server will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Bryan Hamby (@galador)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRegServer

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "Legitimate use, may switch to secureconnectionstring, we will see")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
        [object[]]$Group,
        [object[]]$ExcludeGroup,
        [int[]]$Id,
        [switch]$IncludeSelf,
        [switch]$ResolveNetworkName,
        [switch]$ExcludeLocal,
        [switch]$EnableException
    )
    begin {
        if ($ResolveNetworkName) {
            $defaults = 'ComputerName', 'FQDN', 'IPAddress', 'Name', 'ServerName', 'Group', 'Description'
        }
        $defaults = 'Name', 'ServerName', 'Group', 'Description'
        # thank you forever https://social.msdn.microsoft.com/Forums/sqlserver/en-US/57811d43-a2b9-4179-a97b-a9936ddb188e/how-to-retrieve-a-password-saved-by-sql-server?forum=sqltools
        function Unprotect-String([string] $base64String) {
            return [System.Text.Encoding]::Unicode.GetString([System.Security.Cryptography.ProtectedData]::Unprotect([System.Convert]::FromBase64String($base64String), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))
        }
    }
    process {
        if (-not $PSBoundParameters.SqlInstance) {
            $null = Get-ChildItem -Recurse "$home\AppData\Roaming\Microsoft\*sql*" -Filter RegSrvr.xml | Sort-Object LastWriteTime -Descending | Select-Object -First 1
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
        if (-not $PSBoundParameters.ExcludeLocal) {
            $file = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]::LocalFileStore.DomainInstanceName
            if ($file) {
                if ((Test-Path -Path $file)) {
                    $store = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]
                    $initMethod = $store.GetMethod('InitChildObjects', [Reflection.BindingFlags]'Static,NonPublic')
                    $servers += ($initMethod.Invoke($null, @($file))).DatabaseEngineServerGroup.GetDescendantRegisteredServers()
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

        if ($ExcludeGroup) {
            $excluded = Get-DbaRegServer -SqlInstance $serverstore.ParentServer -Group $ExcludeGroup
            Write-Message -Level Verbose -Message "Excluding $ExcludeGroup"
            $servers = $servers | Where-Object { $_.Urn.Value -notin $excluded.Urn.Value }
        }

        foreach ($server in $servers) {
            $groupname = Get-RegServerGroupReverseParse $server
            if ($groupname -eq $server.Name) {
                $groupname = $null
            } else {
                $groupname = ($groupname).Split("\")
                $groupname = $groupname[0 .. ($groupname.Count - 2)]
                $groupname = ($groupname -join "\")
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